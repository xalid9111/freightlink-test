// Payments — shared, pure logic for the payments-checkout and
// payments-webhook Edge Functions (no Deno-only APIs, so it also runs in
// Node for tests: node --experimental-strip-types --test
// supabase/functions/_shared/payments_test.ts).
//
// Security model
//  * API keys / webhook secrets live only in Edge Function secrets.
//  * The amount always comes from the database (payment_create), never
//    from the app or the provider redirect.
//  * A provider event is trusted only after its signature was verified
//    here; the database then applies it idempotently
//    (finance_apply_provider_event, unique (provider, event id)) and
//    re-checks payment id, amount, currency and provider.
//  * No real provider is wired yet: their adapters refuse
//    ("provider_not_implemented") instead of pretending to work.

export const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export const PROVIDERS = ['test', 'payriff', 'epoint', 'stripe'] as const;
export type Provider = (typeof PROVIDERS)[number];
export const METHODS = ['card', 'apple_pay', 'google_pay'] as const;
export type Method = (typeof METHODS)[number];

/** Secrets each real provider needs before it can even be considered. */
export const PROVIDER_SECRETS: Record<Exclude<Provider, 'test'>, string[]> = {
  payriff: ['PAYRIFF_SECRET_KEY', 'PAYRIFF_MERCHANT_ID', 'PAYRIFF_WEBHOOK_SECRET'],
  epoint: ['EPOINT_PUBLIC_KEY', 'EPOINT_PRIVATE_KEY'],
  stripe: ['STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET'],
};

export function missingSecrets(provider: Provider, env: (name: string) => string | undefined): string[] {
  if (provider === 'test') return env('PAYMENTS_TEST_WEBHOOK_SECRET') ? [] : ['PAYMENTS_TEST_WEBHOOK_SECRET'];
  return PROVIDER_SECRETS[provider].filter((k) => !env(k));
}

const enc = new TextEncoder();

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(message)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, '0')).join('');
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** Signature header of the built-in test provider: "t=<unix>,v1=<hex>",
 *  hex = HMAC-SHA256(secret, "<unix>.<raw body>") — same scheme as the
 *  big card providers, so the webhook path is exercised for real. */
export async function signEvent(secret: string, body: string, unix: number): Promise<string> {
  return `t=${unix},v1=${await hmacSha256Hex(secret, `${unix}.${body}`)}`;
}

export async function verifySignature(
  secret: string, header: string | null, body: string, nowUnix: number, toleranceSec = 300,
): Promise<boolean> {
  if (!secret || !header) return false;
  const parts = Object.fromEntries(
    header.split(',').map((p) => p.trim().split('=', 2)).filter((kv) => kv.length === 2) as [string, string][],
  );
  const t = Number(parts['t']);
  const v1 = parts['v1'] ?? '';
  if (!Number.isFinite(t) || !/^[0-9a-f]{64}$/.test(v1)) return false;
  if (Math.abs(nowUnix - t) > toleranceSec) return false; // replayed / old
  return timingSafeEqual(await hmacSha256Hex(secret, `${t}.${body}`), v1);
}

export interface ProviderEvent {
  id: string;
  type: 'payment.succeeded' | 'payment.failed';
  payment_id: string;
  amount: number;
  currency: string;
  provider_ref: string | null;
  reason?: string;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Strict parse of an event body; null when anything is off. */
export function parseEvent(raw: string): ProviderEvent | null {
  let j: unknown;
  try {
    j = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!j || typeof j !== 'object') return null;
  const o = j as Record<string, unknown>;
  const id = typeof o.id === 'string' && /^[A-Za-z0-9_.:-]{3,200}$/.test(o.id) ? o.id : null;
  const type = o.type === 'payment.succeeded' || o.type === 'payment.failed' ? o.type : null;
  const pid = typeof o.payment_id === 'string' && UUID.test(o.payment_id) ? o.payment_id : null;
  const amount = typeof o.amount === 'number' && Number.isFinite(o.amount) && o.amount > 0 ? Math.round(o.amount * 100) / 100 : null;
  const currency = typeof o.currency === 'string' && /^[A-Za-z]{3}$/.test(o.currency) ? o.currency.toUpperCase() : null;
  if (!id || !type || !pid || amount === null || !currency) return null;
  const ref = typeof o.provider_ref === 'string' && o.provider_ref.length <= 200 ? o.provider_ref : null;
  const reason = typeof o.reason === 'string' ? o.reason.slice(0, 200) : undefined;
  return { id, type, payment_id: pid, amount, currency, provider_ref: ref, ...(reason ? { reason } : {}) };
}

/** Event the built-in test provider sends after the test checkout. */
export function testEvent(
  payment: { id: string; amount: number | string; currency: string },
  outcome: 'success' | 'fail',
  eventId: string,
): ProviderEvent {
  return {
    id: eventId,
    type: outcome === 'success' ? 'payment.succeeded' : 'payment.failed',
    payment_id: payment.id,
    amount: Math.round(Number(payment.amount) * 100) / 100,
    currency: payment.currency.toUpperCase(),
    provider_ref: `test_${payment.id}`,
    ...(outcome === 'fail' ? { reason: 'test_declined' } : {}),
  };
}

export function isUuid(v: unknown): v is string {
  return typeof v === 'string' && UUID.test(v);
}

export function isIdempotencyKey(v: unknown): v is string {
  return typeof v === 'string' && /^[A-Za-z0-9_-]{8,80}$/.test(v);
}

/** Last path segment = provider name for the webhook (".../payments-webhook/test"). */
export function providerFromPath(pathname: string): Provider | null {
  const last = pathname.replace(/\/+$/, '').split('/').pop() ?? '';
  return (PROVIDERS as readonly string[]).includes(last) ? (last as Provider) : null;
}

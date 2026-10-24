// Supabase Edge Function: payments-checkout — starts a card / Apple Pay /
// Google Pay checkout for one of the caller's ad orders, TIR Bazarı VIP
// orders or load VIP orders.
//
// POST { action: 'create', order_id | vip_order_id | cargo_vip_order_id, method, idempotency_key }
//   → payment_create (ad order), market_vip_payment_create (VIP order,
//     0044) or cargo_vip_payment_create (load VIP order, 0062) runs WITH
//     THE CALLER'S JWT, so the database checks the owner,
//     the order state, the amount (from the order) and the "one open
//     payment per order" rule. Same key twice = same payment.
//   → TEST mode: the built-in test provider (no money moves).
//   → a real provider is refused until it is connected
//     ("provider_not_configured" / "provider_not_implemented").
// POST { action: 'test_complete', payment_id, outcome: 'success'|'fail' }
//   → TEST payments only: the test provider signs an event and sends it to
//     payments-webhook — the same verified path a real provider will use.
// POST { action: 'status', payment_id } → the payment as the database has it.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   PAYMENTS_TEST_WEBHOOK_SECRET   random string, also used by payments-webhook
// Provided by Supabase: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { CORS_HEADERS, isIdempotencyKey, isUuid, METHODS, missingSecrets, signEvent, testEvent, type Provider } from '../_shared/payments.ts';

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

type Payment = { id: string; order_id: string | null; market_vip_order_id?: string | null; amount: number | string; currency: string; method: string; provider: Provider; mode: string; status: string };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } });
}

const KNOWN_ERRORS = ['payments_disabled', 'invalid_method', 'invalid_idempotency_key', 'order_not_found', 'order_not_payable', 'already_paid', 'not_authenticated'];

async function rest(url: string, path: string, key: string, auth: string, init: { method?: string; body?: unknown } = {}): Promise<Response> {
  return fetch(`${url}/rest/v1/${path}`, {
    method: init.method ?? 'POST',
    headers: { apikey: key, Authorization: auth, 'Content-Type': 'application/json', Accept: 'application/json' },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
}

async function errorOf(res: Response): Promise<string> {
  const e = await res.json().catch(() => null) as { message?: unknown } | null;
  const msg = typeof e?.message === 'string' ? e.message : '';
  return KNOWN_ERRORS.find((k) => msg.includes(k)) ?? 'checkout_failed';
}

async function myPayment(url: string, anonKey: string, auth: string, id: string): Promise<Payment | null> {
  // RLS: the caller sees only his own payments.
  const res = await rest(url, `ad_payments?id=eq.${id}&select=id,order_id,market_vip_order_id,amount,currency,method,provider,mode,status,confirmed_at,failure_reason`,
    anonKey, auth, { method: 'GET' });
  if (!res.ok) return null;
  const rows = await res.json().catch(() => []) as Payment[];
  return rows[0] ?? null;
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) return json({ error: 'not_configured' }, 503);

  const auth = req.headers.get('authorization') ?? '';
  if (!/^Bearer\s+\S+$/i.test(auth)) return json({ error: 'not_authenticated' }, 401);
  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  const action = body?.action;

  if (action === 'create') {
    const orderId = body?.order_id, vipOrderId = body?.vip_order_id, cargoVipOrderId = body?.cargo_vip_order_id;
    const method = body?.method, key = body?.idempotency_key;
    // Exactly one order: an ad order, a TIR Bazarı VIP order or a load VIP order.
    const targets = [orderId, vipOrderId, cargoVipOrderId].filter(isUuid).length;
    const unknown = [orderId, vipOrderId, cargoVipOrderId].some((v) => v !== undefined && v !== null && !isUuid(v));
    if (targets !== 1 || unknown || !(METHODS as readonly unknown[]).includes(method) || !isIdempotencyKey(key)) {
      return json({ error: 'invalid_request' }, 400);
    }
    const res = isUuid(cargoVipOrderId)
      ? await rest(url, 'rpc/cargo_vip_payment_create', anonKey, auth, { body: { p_vip_order: cargoVipOrderId, p_method: method, p_key: key } })
      : isUuid(vipOrderId)
      ? await rest(url, 'rpc/market_vip_payment_create', anonKey, auth, { body: { p_vip_order: vipOrderId, p_method: method, p_key: key } })
      : await rest(url, 'rpc/payment_create', anonKey, auth, { body: { p_order: orderId, p_method: method, p_key: key } });
    if (!res.ok) {
      const err = await errorOf(res);
      return json({ error: err }, err === 'payments_disabled' || err === 'not_authenticated' ? 403 : 400);
    }
    const payment = await res.json() as Payment;
    if (payment.provider !== 'test') {
      const missing = missingSecrets(payment.provider, (k) => Deno.env.get(k));
      // Never pretend: no real provider is wired in this version.
      return json({ error: missing.length ? 'provider_not_configured' : 'provider_not_implemented', payment }, 503);
    }
    if (missingSecrets('test', (k) => Deno.env.get(k)).length) return json({ error: 'provider_not_configured', payment }, 503);
    if (payment.status === 'created') {
      const att = await rest(url, 'rpc/payment_attach_provider', serviceKey, `Bearer ${serviceKey}`,
        { body: { p_payment: payment.id, p_ref: `test_${payment.id}` } });
      if (att.ok) Object.assign(payment, await att.json());
    }
    return json({ payment, checkout: { type: 'test' } });
  }

  if (action === 'test_complete') {
    const id = body?.payment_id, outcome = body?.outcome;
    if (!isUuid(id) || (outcome !== 'success' && outcome !== 'fail')) return json({ error: 'invalid_request' }, 400);
    const secret = Deno.env.get('PAYMENTS_TEST_WEBHOOK_SECRET');
    if (!secret) return json({ error: 'provider_not_configured' }, 503);
    const payment = await myPayment(url, anonKey, auth, id);
    if (!payment) return json({ error: 'payment_not_found' }, 404);
    if (payment.mode !== 'test' || payment.provider !== 'test') return json({ error: 'not_a_test_payment' }, 403);
    if (payment.status !== 'pending' && payment.status !== 'created') return json({ payment, result: 'already_final' });
    const event = testEvent(payment, outcome, `evt_test_${crypto.randomUUID()}`);
    const raw = JSON.stringify(event);
    const signature = await signEvent(secret, raw, Math.floor(Date.now() / 1000));
    const hook = await fetch(`${url}/functions/v1/payments-webhook/test`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-fl-signature': signature, apikey: anonKey },
      body: raw,
    });
    const result = await hook.json().catch(() => ({})) as { result?: string; error?: string };
    return json({ payment: await myPayment(url, anonKey, auth, id), result: result.result ?? result.error ?? 'webhook_failed' },
      hook.ok ? 200 : 502);
  }

  if (action === 'status') {
    const id = body?.payment_id;
    if (!isUuid(id)) return json({ error: 'invalid_request' }, 400);
    const payment = await myPayment(url, anonKey, auth, id);
    return payment ? json({ payment }) : json({ error: 'payment_not_found' }, 404);
  }
  return json({ error: 'invalid_request' }, 400);
}

Deno.serve(handle);

// Supabase Edge Function: wa-verify-start — WhatsApp phone verification PoC.
//
// Called by the signed-in app (admin test screen) with { phone }.
//   1. Checks the caller's Supabase JWT (deployed WITH JWT verification,
//      and re-checked here against /auth/v1/user).
//   2. Normalises the number to E.164.
//   3. Creates a random single-use code (120 bits), stores ONLY its
//      SHA-256 hash, bound to this user + number, valid 10 minutes.
//   4. Returns a wa.me click-to-chat link with the code prefilled.
// It never sends any SMS / WhatsApp message itself.
//
// Secrets / settings (Supabase → Edge Functions → Secrets):
//   WA_BUSINESS_NUMBER     FreightLink's WhatsApp Business number, e.g. +994XXXXXXXXX (public, not secret)
//   WA_POC_ALLOW_ALL_USERS optional; "true" lets any signed-in user test (default: admins only)
// Provided automatically by Supabase: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { CORS_HEADERS, maskPhone, newChallenge, normalizeE164, prefilledMessage, sha256Hex, supabaseHeaders, waMeDigits, waMeLink } from '../_shared/wa_verify.ts';

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

const TTL_SECONDS = 600;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } });
}

async function currentUserId(req: Request, url: string, anonKey: string): Promise<string | null> {
  const auth = req.headers.get('authorization') ?? '';
  if (!/^Bearer\s+\S+$/i.test(auth)) return null;
  const res = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: auth } });
  if (!res.ok) return null;
  const u = await res.json().catch(() => null) as { id?: unknown } | null;
  return u && typeof u.id === 'string' ? u.id : null;
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const business = waMeDigits(Deno.env.get('WA_BUSINESS_NUMBER') ?? '');
  if (!url || !anonKey || !serviceKey || !business) {
    console.error('wa-verify-start: not configured (WA_BUSINESS_NUMBER or Supabase env missing)');
    return json({ error: 'not_configured' }, 503);
  }

  const userId = await currentUserId(req, url, anonKey);
  if (!userId) return json({ error: 'not_signed_in' }, 401);

  const body = await req.json().catch(() => null) as { phone?: unknown } | null;
  const phone = normalizeE164(body?.phone);
  if (!phone) return json({ error: 'invalid_phone' }, 400);

  const code = newChallenge();
  const res = await fetch(`${url}/rest/v1/rpc/wa_poc_start`, {
    method: 'POST',
    headers: supabaseHeaders(serviceKey),
    body: JSON.stringify({
      p_user: userId,
      p_phone: phone,
      p_hash: await sha256Hex(code),
      p_ttl_seconds: TTL_SECONDS,
      p_require_admin: (Deno.env.get('WA_POC_ALLOW_ALL_USERS') ?? '').toLowerCase() !== 'true',
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => null) as { message?: unknown } | null;
    const msg = typeof err?.message === 'string' ? err.message : '';
    const known = ['admin_only', 'rate_limited', 'invalid_phone'].find((k) => msg.includes(k));
    console.warn('wa-verify-start: start refused', known ?? res.status);
    return json({ error: known ?? 'start_failed' }, known === 'admin_only' ? 403 : known === 'rate_limited' ? 429 : known ? 400 : 500);
  }
  const rows = await res.json() as Array<{ id: string; expires_at: string }>;
  const row = rows[0];
  if (!row) return json({ error: 'start_failed' }, 500);

  console.log('wa-verify-start: started', row.id, maskPhone(phone));
  const message = prefilledMessage(code);
  return json({
    challenge_id: row.id,
    phone_e164: phone,
    expires_at: row.expires_at,
    wa_link: waMeLink(business, message),
    message,
  });
}

Deno.serve(handle);

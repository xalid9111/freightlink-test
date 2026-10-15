// Supabase Edge Function: payments-webhook — the ONLY way a payment
// becomes "succeeded". Deployed WITHOUT JWT verification (providers call it
// directly); every request is authenticated by the provider's signature.
//
//   POST /functions/v1/payments-webhook/<provider>
//     header x-fl-signature: t=<unix>,v1=<hmac-sha256 of "<unix>.<raw body>">
//
// 1. Verify the signature over the RAW body (5-minute window → no replays).
// 2. Strictly parse the event.
// 3. finance_apply_provider_event (service role): idempotent per event id;
//    checks payment, provider, amount, currency; only LIVE successes mark
//    the ad order as paid; everything goes to the finance audit log.
// Real providers are refused (501) until their own verification is added —
// an unsigned or unknown event can never change a payment.
//
// Secrets: PAYMENTS_TEST_WEBHOOK_SECRET (same value as payments-checkout).
// Provided by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { CORS_HEADERS, parseEvent, providerFromPath, verifySignature } from '../_shared/payments.ts';

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' } });
}

export async function handle(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return json({ error: 'not_configured' }, 503);

  const provider = providerFromPath(new URL(req.url).pathname);
  if (!provider) return json({ error: 'unknown_provider' }, 404);
  if (provider !== 'test') return json({ error: 'provider_not_implemented' }, 501);

  const secret = Deno.env.get('PAYMENTS_TEST_WEBHOOK_SECRET') ?? '';
  const raw = await req.text();
  if (!await verifySignature(secret, req.headers.get('x-fl-signature'), raw, Math.floor(Date.now() / 1000))) {
    console.warn('payments-webhook: bad signature');
    return json({ error: 'invalid_signature' }, 401);
  }
  const event = parseEvent(raw);
  if (!event) return json({ error: 'invalid_event' }, 400);

  const res = await fetch(`${url}/rest/v1/rpc/finance_apply_provider_event`, {
    method: 'POST',
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_provider: provider, p_event_id: event.id, p_payment: event.payment_id, p_type: event.type,
      p_amount: event.amount, p_currency: event.currency, p_provider_ref: event.provider_ref,
      p_payload: { reason: event.reason ?? null },
    }),
  });
  if (!res.ok) {
    console.error('payments-webhook: apply failed', res.status);
    return json({ error: 'apply_failed' }, 500); // provider retries later
  }
  const result = await res.json() as string;
  console.log('payments-webhook:', provider, event.id, result);
  return json({ result });
}

Deno.serve(handle);

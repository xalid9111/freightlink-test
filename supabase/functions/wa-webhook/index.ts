// Supabase Edge Function: wa-webhook — WhatsApp phone verification PoC.
//
// Receives Meta WhatsApp Cloud API webhooks for FreightLink's WhatsApp
// Business number.
//   GET  — Meta's subscription check (hub.mode / hub.verify_token / hub.challenge)
//   POST — events. The X-Hub-Signature-256 header is verified against the
//          RAW body with the Meta App Secret before anything is parsed.
//          Only incoming user text messages that contain a FreightLink code
//          ("FL-…") are processed; status updates and everything else are
//          acknowledged and ignored.
//
// Meta calls this without a Supabase JWT, so deploy it with JWT
// verification OFF (`--no-verify-jwt`, see supabase/config.toml). The
// Meta signature is the authentication.
//
// Secrets (Supabase → Edge Functions → Secrets; never in Flutter):
//   META_APP_SECRET          Meta App → App settings → Basic → App secret
//   WA_WEBHOOK_VERIFY_TOKEN  any long random string, also typed into Meta
//   WA_PHONE_NUMBER_ID       WhatsApp → API Setup → Phone number ID
// Provided automatically by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Stores nothing from the message except Meta's message id (retry
// de-duplication) and, on the matching challenge row, the outcome and the
// KIND of sender identity (phone / bsuid_only / conflict / none).
// Logs never contain message text, codes, phone numbers or BSUIDs.

import { extractChallenge, maskPhone, parseInbound, sha256Hex, supabaseHeaders, timingSafeEqual, verifyMetaSignature } from '../_shared/wa_verify.ts';

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): unknown;
};

const MAX_BODY = 256 * 1024;

function text(body: string, status = 200): Response {
  return new Response(body, { status, headers: { 'Content-Type': 'text/plain' } });
}

async function callInbound(args: Record<string, unknown>): Promise<string> {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) throw new Error('supabase_env_missing');
  const res = await fetch(`${url}/rest/v1/rpc/wa_poc_inbound`, {
    method: 'POST',
    headers: supabaseHeaders(key),
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(`rpc_failed_${res.status}`);
  return String(await res.json());
}

export async function handle(req: Request): Promise<Response> {
  const url = new URL(req.url);

  if (req.method === 'GET') {
    const verifyToken = Deno.env.get('WA_WEBHOOK_VERIFY_TOKEN') ?? '';
    const mode = url.searchParams.get('hub.mode');
    const token = url.searchParams.get('hub.verify_token') ?? '';
    const challenge = url.searchParams.get('hub.challenge') ?? '';
    if (verifyToken && mode === 'subscribe' && timingSafeEqual(token, verifyToken) && /^[0-9A-Za-z_-]{1,128}$/.test(challenge)) {
      return text(challenge);
    }
    return text('forbidden', 403);
  }

  if (req.method !== 'POST') return text('method not allowed', 405);

  const appSecret = Deno.env.get('META_APP_SECRET') ?? '';
  const ourPhoneNumberId = Deno.env.get('WA_PHONE_NUMBER_ID') ?? '';
  if (!appSecret || !ourPhoneNumberId) {
    console.error('wa-webhook: META_APP_SECRET / WA_PHONE_NUMBER_ID not configured');
    return text('not configured', 503);
  }

  const declared = Number(req.headers.get('content-length') ?? '0');
  if (declared > MAX_BODY) return text('too large', 413);
  const raw = new Uint8Array(await req.arrayBuffer());
  if (raw.byteLength > MAX_BODY) return text('too large', 413);

  if (!(await verifyMetaSignature(raw, req.headers.get('x-hub-signature-256'), appSecret))) {
    console.warn('wa-webhook: bad or missing signature');
    return text('invalid signature', 401);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return text('bad json', 400);
  }

  let failed = false;
  for (const m of parseInbound(payload)) {
    if (m.phoneNumberId !== ourPhoneNumberId) continue; // not our number
    const code = m.type === 'text' ? extractChallenge(m.text) : null;
    // PoC evidence: which identity fields Meta sent (presence only).
    console.log('wa-webhook: inbound', JSON.stringify({
      type: m.type, hasCode: code !== null, senderKind: m.senderKind, hasBsuid: m.hasBsuid, fields: m.fields,
      sender: maskPhone(m.senderDigits),
    }));
    if (!code) continue; // not a verification message — nothing stored
    try {
      const outcome = await callInbound({
        p_message_id: m.messageId,
        p_hash: await sha256Hex(code),
        p_sender_kind: m.senderKind,
        p_sender_digits: m.senderDigits,
        p_has_bsuid: m.hasBsuid,
      });
      console.log('wa-webhook: outcome', outcome);
    } catch (e) {
      failed = true; // let Meta retry; processing is idempotent per message id
      console.error('wa-webhook: processing failed', e instanceof Error ? e.message : 'error');
    }
  }
  return failed ? text('retry', 500) : text('ok');
}

Deno.serve(handle);

// Supabase Edge Function: push-send — Web Push for TırLink (SQL 0121).
//
//   GET  /functions/v1/push-send          → { publicKey }  (the VAPID public key;
//                                            not secret — the app needs it to subscribe)
//   POST /functions/v1/push-send {id}     ← only the database (pg_net trigger),
//        header x-push-secret              checked against Supabase Vault through
//                                            push_hook_check (service role)
//
// 1. push_outbox_take(id): the notification + the user's devices, once.
// 2. Send to each device with VAPID (web-push); only the real push services.
// 3. push_outbox_done: the result; devices answering 404 / 410 are removed.
//
// Deployed WITHOUT JWT verification (the database calls it); every POST is
// authenticated by the Vault secret instead.
// Secrets (Supabase → Edge Functions → Secrets): VAPID_PUBLIC_KEY,
// VAPID_PRIVATE_KEY, VAPID_SUBJECT (e.g. mailto:noreply@tirlink.app).
// Provided by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import webpush from 'npm:web-push@3.6.7';
import { endpointOk, isGone, isUuid, parseJob, payloadOf, topicOf } from '../_shared/push.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

async function rpc(url: string, key: string, fn: string, params: Record<string, unknown>): Promise<unknown> {
  const res = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });
  if (!res.ok) throw new Error(`${fn}: ${res.status}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  const publicKey = Deno.env.get('VAPID_PUBLIC_KEY') ?? '';
  if (req.method === 'GET') return json({ publicKey: publicKey || null });
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const privateKey = Deno.env.get('VAPID_PRIVATE_KEY') ?? '';
  const subject = Deno.env.get('VAPID_SUBJECT') || 'mailto:noreply@tirlink.app';
  if (!url || !key || !publicKey || !privateKey) return json({ error: 'not_configured' }, 503);

  try {
    const secret = req.headers.get('x-push-secret') ?? '';
    if ((await rpc(url, key, 'push_hook_check', { p_secret: secret })) !== true) return json({ error: 'unauthorized' }, 401);

    const body = await req.json().catch(() => null) as { id?: unknown } | null;
    if (!isUuid(body?.id)) return json({ error: 'bad_request' }, 400);
    const job = parseJob(await rpc(url, key, 'push_outbox_take', { p_id: body!.id }));
    if (!job) return json({ skipped: true });

    webpush.setVapidDetails(subject, publicKey, privateKey);
    const payload = payloadOf(job);
    const topic = topicOf(job.tag);
    let sent = 0;
    let failed = 0;
    const gone: string[] = [];
    let lastError: string | null = null;
    await Promise.all(job.subscriptions.map(async (s) => {
      if (!endpointOk(s.endpoint)) {
        gone.push(s.endpoint);
        return;
      }
      try {
        await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload,
          { TTL: 86400, urgency: 'high', topic, timeout: 10000 });
        sent++;
      } catch (e) {
        failed++;
        const status = (e as { statusCode?: number }).statusCode;
        if (isGone(status)) gone.push(s.endpoint);
        lastError = String(status ?? (e as Error).message ?? 'error').slice(0, 200);
      }
    }));
    await rpc(url, key, 'push_outbox_done', { p_id: job.id, p_sent: sent, p_failed: failed, p_gone: gone, p_error: lastError });
    return json({ sent, failed, gone: gone.length });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e).slice(0, 200) }, 500);
  }
});

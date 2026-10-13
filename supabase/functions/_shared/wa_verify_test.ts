// Tests for the WhatsApp verification PoC (pure logic + both handlers with
// a stubbed Deno/fetch). Run with either:
//   node --experimental-strip-types --test supabase/functions/_shared/wa_verify_test.ts
//   deno test supabase/functions/_shared/wa_verify_test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  classifySender, extractChallenge, hmacSha256Hex, maskPhone, newChallenge, normalizeE164, parseInbound,
  prefilledMessage, sha256Hex, timingSafeEqual, verifyMetaSignature, waMeDigits, waMeLink,
} from './wa_verify.ts';

// ---- stub Deno + fetch so the real handlers can be imported -----------
const env: Record<string, string> = {
  SUPABASE_URL: 'https://proj.supabase.test',
  SUPABASE_ANON_KEY: 'anon.jwt.key',
  SUPABASE_SERVICE_ROLE_KEY: 'service.jwt.key',
  META_APP_SECRET: 'test-app-secret',
  WA_WEBHOOK_VERIFY_TOKEN: 'verify-me-123',
  WA_PHONE_NUMBER_ID: '111222333',
  WA_BUSINESS_NUMBER: '+994 12 000 00 00',
};
(globalThis as any).Deno = { env: { get: (k: string) => env[k] }, serve: () => {} };
type Call = { url: string; body: any; headers: Record<string, string> };
const calls: Call[] = [];
let rpcReply: () => Response = () => new Response('"verified"', { status: 200 });
globalThis.fetch = (async (input: string, init?: RequestInit) => {
  const body = init?.body ? JSON.parse(String(init.body)) : null;
  calls.push({ url: String(input), body, headers: (init?.headers ?? {}) as Record<string, string> });
  if (String(input).endsWith('/auth/v1/user')) {
    const auth = (init?.headers as Record<string, string>)?.Authorization;
    return auth === 'Bearer good-user-jwt'
      ? new Response(JSON.stringify({ id: 'u-1' }), { status: 200 })
      : new Response('{}', { status: 401 });
  }
  if (String(input).endsWith('/rpc/wa_poc_start')) {
    return new Response(JSON.stringify([{ id: 'c-1', expires_at: '2026-01-01T00:10:00Z' }]), { status: 200 });
  }
  return rpcReply();
}) as typeof fetch;

const webhook = await import('../wa-webhook/index.ts');
const start = await import('../wa-verify-start/index.ts');

function payload(message: Record<string, unknown>, contacts: unknown[] = [], phoneNumberId = '111222333') {
  return {
    object: 'whatsapp_business_account',
    entry: [{ id: 'WABA', changes: [{ field: 'messages', value: {
      messaging_product: 'whatsapp',
      metadata: { display_phone_number: '994120000000', phone_number_id: phoneNumberId },
      contacts,
      messages: [message],
    } }] }],
  };
}
const CODE = 'ABCDEFGHIJKLMNOPQRSTUVWX';
const textMsg = (extra: Record<string, unknown> = {}) => ({ id: 'wamid.1', timestamp: '1', type: 'text', text: { body: prefilledMessage(CODE) }, ...extra });

async function signedPost(body: unknown, secret = env.META_APP_SECRET, tamper = false): Promise<Response> {
  const raw = new TextEncoder().encode(JSON.stringify(body));
  const sig = 'sha256=' + await hmacSha256Hex(secret, raw);
  const sent = tamper ? new TextEncoder().encode(JSON.stringify(body).replace('wamid', 'wamiX')) : raw;
  return webhook.handle(new Request('https://fn/wa-webhook', { method: 'POST', body: sent, headers: { 'x-hub-signature-256': sig, 'content-type': 'application/json' } }));
}

// ---- pure logic -------------------------------------------------------
test('E.164 normalisation', () => {
  assert.equal(normalizeE164('+994 50 123-45-67'), '+994501234567');
  assert.equal(normalizeE164('00994501234567'), '+994501234567');
  assert.equal(normalizeE164('0501234567'), null); // no country code
  assert.equal(normalizeE164('+0123456789'), null);
  assert.equal(normalizeE164('+1234567890123456'), null); // 16 digits
  assert.equal(normalizeE164(12345), null);
  assert.equal(waMeDigits('+994 12 000 00 00'), '994120000000');
  assert.equal(waMeDigits('994120000000'), '994120000000');
  assert.equal(maskPhone('+994501234567'), '+994******567');
});

test('challenge: random, base32, 24 chars, found in the prefilled text only', () => {
  const a = newChallenge(), b = newChallenge();
  assert.match(a, /^[A-Z2-7]{24}$/);
  assert.notEqual(a, b);
  assert.equal(extractChallenge(prefilledMessage(a)), a);
  assert.equal(extractChallenge(`fl-${a.toLowerCase()}`), a);
  assert.equal(extractChallenge(`xFL-${a}`), null);
  assert.equal(extractChallenge(`FL-${a}Z`), null);
  assert.equal(extractChallenge('hello'), null);
  assert.equal(extractChallenge(null), null);
});

test('sha256 + constant-time compare', async () => {
  assert.equal(await sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.ok(timingSafeEqual('abc', 'abc'));
  assert.ok(!timingSafeEqual('abc', 'abd'));
  assert.ok(!timingSafeEqual('abc', 'abcd'));
  assert.equal(waMeLink('994120000000', 'a b'), 'https://wa.me/994120000000?text=a%20b');
});

test('Meta signature over the raw body', async () => {
  const raw = new TextEncoder().encode('{"x":1}');
  const good = 'sha256=' + await hmacSha256Hex('s3cret', raw);
  assert.ok(await verifyMetaSignature(raw, good, 's3cret'));
  assert.ok(!await verifyMetaSignature(raw, good, 'other'));
  assert.ok(!await verifyMetaSignature(new TextEncoder().encode('{"x":2}'), good, 's3cret'));
  assert.ok(!await verifyMetaSignature(raw, null, 's3cret'));
  assert.ok(!await verifyMetaSignature(raw, 'sha1=abc', 's3cret'));
  assert.ok(!await verifyMetaSignature(raw, good, ''));
});

test('sender classification', () => {
  assert.deepEqual(classifySender('994501234567', '994501234567', 'AZ.1'), { kind: 'phone', digits: '994501234567' });
  assert.deepEqual(classifySender('994501234567', null, null), { kind: 'phone', digits: '994501234567' });
  assert.deepEqual(classifySender(null, null, 'AZ.123'), { kind: 'bsuid_only', digits: null });
  assert.deepEqual(classifySender(null, '994501234567', 'AZ.123'), { kind: 'bsuid_only', digits: null });
  assert.deepEqual(classifySender('AZ.123', null, null), { kind: 'bsuid_only', digits: null });
  assert.deepEqual(classifySender('994501234567', '994559999999', null), { kind: 'conflict', digits: null });
  assert.deepEqual(classifySender(null, null, null), { kind: 'none', digits: null });
});

test('parser: phone sender, BSUID-only sender, statuses ignored', () => {
  const withPhone = parseInbound(payload(textMsg({ from: '994501234567', from_user_id: 'AZ.1' }), [{ wa_id: '994501234567', user_id: 'AZ.1', profile: { name: 'X' } }]));
  assert.equal(withPhone.length, 1);
  assert.equal(withPhone[0].senderKind, 'phone');
  assert.equal(withPhone[0].senderDigits, '994501234567');
  assert.equal(withPhone[0].hasBsuid, true);
  assert.equal(withPhone[0].phoneNumberId, '111222333');

  const bsuidOnly = parseInbound(payload(textMsg({ from_user_id: 'AZ.1' }), [{ user_id: 'AZ.1', profile: { username: 'x' } }]));
  assert.equal(bsuidOnly[0].senderKind, 'bsuid_only');
  assert.equal(bsuidOnly[0].senderDigits, null);

  const statuses = { object: 'whatsapp_business_account', entry: [{ changes: [{ field: 'messages', value: { metadata: { phone_number_id: '111222333' }, statuses: [{ id: 'wamid.s', status: 'delivered' }] } }] }] };
  assert.equal(parseInbound(statuses).length, 0);
  assert.equal(parseInbound({ object: 'page', entry: [] }).length, 0);
  assert.equal(parseInbound(null).length, 0);
});

// ---- webhook handler --------------------------------------------------
test('GET: Meta subscription challenge', async () => {
  const ok = await webhook.handle(new Request('https://fn/wa-webhook?hub.mode=subscribe&hub.verify_token=verify-me-123&hub.challenge=1158201444'));
  assert.equal(ok.status, 200);
  assert.equal(await ok.text(), '1158201444');
  const bad = await webhook.handle(new Request('https://fn/wa-webhook?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=1'));
  assert.equal(bad.status, 403);
});

test('POST: unsigned / wrongly signed / tampered bodies are rejected before parsing', async () => {
  calls.length = 0;
  const body = payload(textMsg({ from: '994501234567' }));
  const unsigned = await webhook.handle(new Request('https://fn/wa-webhook', { method: 'POST', body: JSON.stringify(body) }));
  assert.equal(unsigned.status, 401);
  assert.equal((await signedPost(body, 'not-the-secret')).status, 401);
  assert.equal((await signedPost(body, env.META_APP_SECRET, true)).status, 401);
  assert.equal(calls.length, 0);
});

test('POST: matching message → RPC gets hash (not the code), kind and digits', async () => {
  calls.length = 0;
  rpcReply = () => new Response('"verified"', { status: 200 });
  const res = await signedPost(payload(textMsg({ from: '994501234567', from_user_id: 'AZ.1' }), [{ wa_id: '994501234567', user_id: 'AZ.1' }]));
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
  const c = calls[0];
  assert.ok(c.url.endsWith('/rest/v1/rpc/wa_poc_inbound'));
  assert.equal(c.body.p_hash, await sha256Hex(CODE));
  assert.ok(!JSON.stringify(c.body).includes(CODE));
  assert.equal(c.body.p_sender_kind, 'phone');
  assert.equal(c.body.p_sender_digits, '994501234567');
  assert.equal(c.body.p_message_id, 'wamid.1');
  assert.equal(c.headers.apikey, env.SUPABASE_SERVICE_ROLE_KEY);
});

test('POST: BSUID-only sender is passed as bsuid_only with no digits', async () => {
  calls.length = 0;
  await signedPost(payload(textMsg({ from_user_id: 'AZ.1' }), [{ user_id: 'AZ.1' }]));
  assert.equal(calls[0].body.p_sender_kind, 'bsuid_only');
  assert.equal(calls[0].body.p_sender_digits, null);
});

test('POST: other number, no code, statuses → acknowledged, nothing stored', async () => {
  calls.length = 0;
  assert.equal((await signedPost(payload(textMsg({ from: '994501234567' }), [], '999'))).status, 200);
  assert.equal((await signedPost(payload({ id: 'wamid.2', type: 'text', from: '994501234567', text: { body: 'hello' } }))).status, 200);
  assert.equal((await signedPost(payload({ id: 'wamid.3', type: 'image', from: '994501234567', image: {} }))).status, 200);
  assert.equal(calls.length, 0);
});

test('POST: database error → 500 so Meta retries (processing is idempotent)', async () => {
  rpcReply = () => new Response('{"message":"boom"}', { status: 500 });
  assert.equal((await signedPost(payload(textMsg({ from: '994501234567' })))).status, 500);
  rpcReply = () => new Response('"duplicate"', { status: 200 });
  assert.equal((await signedPost(payload(textMsg({ from: '994501234567' })))).status, 200);
});

// ---- start handler ----------------------------------------------------
test('start: requires a signed-in user and a valid number', async () => {
  const anon = await start.handle(new Request('https://fn/wa-verify-start', { method: 'POST', body: '{"phone":"+994501234567"}' }));
  assert.equal(anon.status, 401);
  const badPhone = await start.handle(new Request('https://fn/wa-verify-start', { method: 'POST', body: '{"phone":"0501234567"}', headers: { authorization: 'Bearer good-user-jwt' } }));
  assert.equal(badPhone.status, 400);
  const pre = await start.handle(new Request('https://fn/wa-verify-start', { method: 'OPTIONS' }));
  assert.equal(pre.headers.get('access-control-allow-origin'), '*');
});

test('start: stores only the hash and returns a wa.me link with the code', async () => {
  calls.length = 0;
  const res = await start.handle(new Request('https://fn/wa-verify-start', { method: 'POST', body: '{"phone":"+994 50 123 45 67"}', headers: { authorization: 'Bearer good-user-jwt' } }));
  assert.equal(res.status, 200);
  const out = await res.json();
  const rpc = calls.find((c) => c.url.endsWith('/rpc/wa_poc_start'))!;
  assert.equal(rpc.body.p_user, 'u-1');
  assert.equal(rpc.body.p_phone, '+994501234567');
  assert.match(rpc.body.p_hash, /^[0-9a-f]{64}$/);
  assert.equal(rpc.body.p_require_admin, true);
  const code = extractChallenge(out.message)!;
  assert.equal(rpc.body.p_hash, await sha256Hex(code));
  assert.ok(!JSON.stringify(rpc.body).includes(code));
  assert.ok(out.wa_link.startsWith('https://wa.me/994120000000?text='));
  assert.equal(decodeURIComponent(out.wa_link.split('text=')[1]), out.message);
  assert.equal(out.challenge_id, 'c-1');
});

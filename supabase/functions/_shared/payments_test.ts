// Tests for the payment Edge Functions (pure logic + both handlers with a
// stubbed Deno/fetch). Run with either:
//   node --experimental-strip-types --test supabase/functions/_shared/payments_test.ts
//   deno test supabase/functions/_shared/payments_test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isIdempotencyKey, missingSecrets, parseEvent, providerFromPath, signEvent, testEvent, verifySignature } from './payments.ts';

const env: Record<string, string> = {
  SUPABASE_URL: 'https://proj.supabase.test',
  SUPABASE_ANON_KEY: 'anon.key',
  SUPABASE_SERVICE_ROLE_KEY: 'service.key',
  PAYMENTS_TEST_WEBHOOK_SECRET: 'whsec_test_123',
};
(globalThis as any).Deno = { env: { get: (k: string) => env[k] }, serve: () => {} };

const PID = '11111111-2222-4333-8444-555555555555';
const OID = '99999999-2222-4333-8444-555555555555';
type Call = { url: string; body: any; headers: Record<string, string> };
const calls: Call[] = [];
let payment: any = { id: PID, order_id: OID, amount: 20, currency: 'AZN', method: 'card', provider: 'test', mode: 'test', status: 'created' };
let createReply: () => Response = () => new Response(JSON.stringify(payment), { status: 200 });
let applyResult = 'applied';
let webhookHandle: (r: Request) => Promise<Response>;

globalThis.fetch = (async (input: string, init?: RequestInit) => {
  const u = String(input);
  const raw = init?.body ? String(init.body) : '';
  calls.push({ url: u, body: raw && raw.startsWith('{') ? JSON.parse(raw) : raw, headers: (init?.headers ?? {}) as Record<string, string> });
  if (u.endsWith('/rpc/payment_create')) return createReply();
  if (u.endsWith('/rpc/payment_attach_provider')) {
    payment = { ...payment, status: 'pending' };
    return new Response(JSON.stringify(payment), { status: 200 });
  }
  if (u.includes('/rest/v1/ad_payments?id=eq.')) {
    const auth = (init?.headers as Record<string, string>)?.Authorization;
    return new Response(JSON.stringify(auth === 'Bearer user-jwt' ? [payment] : []), { status: 200 });
  }
  if (u.endsWith('/functions/v1/payments-webhook/test')) {
    return webhookHandle(new Request('https://fn/payments-webhook/test', { method: 'POST', body: raw, headers: init?.headers as HeadersInit }));
  }
  if (u.endsWith('/rpc/finance_apply_provider_event')) {
    if (applyResult === 'applied') payment = { ...payment, status: JSON.parse(raw).p_type === 'payment.succeeded' ? 'succeeded' : 'failed' };
    return new Response(JSON.stringify(applyResult), { status: 200 });
  }
  return new Response('{}', { status: 404 });
}) as typeof fetch;

const checkout = await import('../payments-checkout/index.ts');
const webhook = await import('../payments-webhook/index.ts');
webhookHandle = webhook.handle;

const post = (h: (r: Request) => Promise<Response>, path: string, body: unknown, headers: Record<string, string> = {}) =>
  h(new Request(`https://fn/${path}`, { method: 'POST', body: typeof body === 'string' ? body : JSON.stringify(body), headers }));

// ---- pure logic -------------------------------------------------------
test('signature: valid, tampered, wrong secret, old (replay), malformed', async () => {
  const now = 1_800_000_000;
  const body = '{"a":1}';
  const h = await signEvent('s3cret', body, now);
  assert.ok(await verifySignature('s3cret', h, body, now));
  assert.ok(await verifySignature('s3cret', h, body, now + 299));
  assert.ok(!await verifySignature('s3cret', h, body, now + 301), 'older than 5 minutes = replay');
  assert.ok(!await verifySignature('s3cret', h, '{"a":2}', now), 'body changed');
  assert.ok(!await verifySignature('other', h, body, now));
  assert.ok(!await verifySignature('', h, body, now));
  assert.ok(!await verifySignature('s3cret', null, body, now));
  assert.ok(!await verifySignature('s3cret', 't=abc,v1=zz', body, now));
});

test('event parsing is strict', () => {
  const ok = parseEvent(JSON.stringify({ id: 'evt_1', type: 'payment.succeeded', payment_id: PID, amount: 20.004, currency: 'azn', provider_ref: 'r' }));
  assert.deepEqual(ok, { id: 'evt_1', type: 'payment.succeeded', payment_id: PID, amount: 20, currency: 'AZN', provider_ref: 'r' });
  assert.equal(parseEvent('not json'), null);
  assert.equal(parseEvent(JSON.stringify({ id: 'evt_1', type: 'payment.refunded', payment_id: PID, amount: 1, currency: 'AZN' })), null);
  assert.equal(parseEvent(JSON.stringify({ id: 'evt_1', type: 'payment.succeeded', payment_id: 'x', amount: 1, currency: 'AZN' })), null);
  assert.equal(parseEvent(JSON.stringify({ id: 'evt_1', type: 'payment.succeeded', payment_id: PID, amount: -1, currency: 'AZN' })), null);
  assert.equal(parseEvent(JSON.stringify({ id: 'evt_1', type: 'payment.succeeded', payment_id: PID, amount: '20', currency: 'AZN' })), null);
});

test('helpers', () => {
  assert.ok(isIdempotencyKey('chk_abcdef12'));
  assert.ok(!isIdempotencyKey('short'));
  assert.ok(!isIdempotencyKey('has space 123'));
  assert.equal(providerFromPath('/functions/v1/payments-webhook/test'), 'test');
  assert.equal(providerFromPath('/payments-webhook/payriff/'), 'payriff');
  assert.equal(providerFromPath('/payments-webhook/evil'), null);
  assert.deepEqual(missingSecrets('payriff', () => undefined), ['PAYRIFF_SECRET_KEY', 'PAYRIFF_MERCHANT_ID', 'PAYRIFF_WEBHOOK_SECRET']);
  assert.deepEqual(missingSecrets('test', (k) => env[k]), []);
  assert.equal(testEvent({ id: PID, amount: '45.5', currency: 'azn' }, 'fail', 'e').reason, 'test_declined');
});

// ---- checkout handler ---------------------------------------------------
test('create: needs a signed-in user and a valid request', async () => {
  assert.equal((await post(checkout.handle, 'payments-checkout', { action: 'create' })).status, 401);
  const bad = await post(checkout.handle, 'payments-checkout', { action: 'create', order_id: OID, method: 'bitcoin', idempotency_key: 'chk_abcdef12' }, { authorization: 'Bearer user-jwt' });
  assert.equal(bad.status, 400);
});

test('create: amount is NOT taken from the app; DB runs with the caller JWT; test checkout returned', async () => {
  calls.length = 0;
  const res = await post(checkout.handle, 'payments-checkout',
    { action: 'create', order_id: OID, method: 'card', idempotency_key: 'chk_abcdef12', amount: 0.01 }, { authorization: 'Bearer user-jwt' });
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.equal(j.checkout.type, 'test');
  assert.equal(j.payment.status, 'pending');
  const create = calls.find((c) => c.url.endsWith('/rpc/payment_create'))!;
  assert.deepEqual(create.body, { p_order: OID, p_method: 'card', p_key: 'chk_abcdef12' }, 'no amount sent');
  assert.equal(create.headers.Authorization, 'Bearer user-jwt');
  const attach = calls.find((c) => c.url.endsWith('/rpc/payment_attach_provider'))!;
  assert.equal(attach.headers.Authorization, 'Bearer service.key');
});

test('create: database refusal is passed on (e.g. payments disabled, already paid)', async () => {
  createReply = () => new Response(JSON.stringify({ message: 'payments_disabled' }), { status: 403 });
  let r = await post(checkout.handle, 'payments-checkout', { action: 'create', order_id: OID, method: 'card', idempotency_key: 'chk_abcdef12' }, { authorization: 'Bearer user-jwt' });
  assert.equal(r.status, 403);
  assert.equal((await r.json()).error, 'payments_disabled');
  createReply = () => new Response(JSON.stringify({ message: 'already_paid' }), { status: 400 });
  r = await post(checkout.handle, 'payments-checkout', { action: 'create', order_id: OID, method: 'card', idempotency_key: 'chk_abcdef12' }, { authorization: 'Bearer user-jwt' });
  assert.equal((await r.json()).error, 'already_paid');
  createReply = () => new Response(JSON.stringify(payment), { status: 200 });
});

test('create: a real provider is refused, never faked', async () => {
  createReply = () => new Response(JSON.stringify({ ...payment, provider: 'payriff', mode: 'live' }), { status: 200 });
  const r = await post(checkout.handle, 'payments-checkout', { action: 'create', order_id: OID, method: 'card', idempotency_key: 'chk_abcdef12' }, { authorization: 'Bearer user-jwt' });
  assert.equal(r.status, 503);
  assert.equal((await r.json()).error, 'provider_not_configured');
  createReply = () => new Response(JSON.stringify(payment), { status: 200 });
});

test('test_complete: goes through the SIGNED webhook and the DB decides', async () => {
  payment = { ...payment, status: 'pending' };
  calls.length = 0;
  const r = await post(checkout.handle, 'payments-checkout', { action: 'test_complete', payment_id: PID, outcome: 'success' }, { authorization: 'Bearer user-jwt' });
  assert.equal(r.status, 200);
  const j = await r.json();
  assert.equal(j.result, 'applied');
  assert.equal(j.payment.status, 'succeeded');
  const hook = calls.find((c) => c.url.endsWith('/payments-webhook/test'))!;
  assert.match(hook.headers['x-fl-signature'], /^t=\d+,v1=[0-9a-f]{64}$/);
  const apply = calls.find((c) => c.url.endsWith('/rpc/finance_apply_provider_event'))!;
  assert.equal(apply.body.p_amount, 20);
  assert.equal(apply.body.p_provider, 'test');
  assert.equal(apply.headers.Authorization, 'Bearer service.key');
});

test('test_complete: only the owner, only test payments, no second success', async () => {
  let r = await post(checkout.handle, 'payments-checkout', { action: 'test_complete', payment_id: PID, outcome: 'success' }, { authorization: 'Bearer someone-else' });
  assert.equal(r.status, 404);
  r = await post(checkout.handle, 'payments-checkout', { action: 'test_complete', payment_id: PID, outcome: 'success' }, { authorization: 'Bearer user-jwt' });
  assert.equal((await r.json()).result, 'already_final');
  payment = { ...payment, status: 'pending', mode: 'live', provider: 'payriff' };
  r = await post(checkout.handle, 'payments-checkout', { action: 'test_complete', payment_id: PID, outcome: 'success' }, { authorization: 'Bearer user-jwt' });
  assert.equal(r.status, 403);
  payment = { ...payment, mode: 'test', provider: 'test' };
});

// ---- webhook handler ------------------------------------------------------
test('webhook: unsigned / tampered / unknown provider are refused', async () => {
  const raw = JSON.stringify(testEvent({ id: PID, amount: 20, currency: 'AZN' }, 'success', 'evt_w1'));
  assert.equal((await post(webhook.handle, 'payments-webhook/test', raw)).status, 401);
  const sig = await signEvent(env.PAYMENTS_TEST_WEBHOOK_SECRET, raw, Math.floor(Date.now() / 1000));
  assert.equal((await post(webhook.handle, 'payments-webhook/test', raw.replace('20', '2'), { 'x-fl-signature': sig })).status, 401);
  assert.equal((await post(webhook.handle, 'payments-webhook/payriff', raw, { 'x-fl-signature': sig })).status, 501);
  assert.equal((await post(webhook.handle, 'payments-webhook/evil', raw, { 'x-fl-signature': sig })).status, 404);
});

test('webhook: signed event reaches the database; duplicates are acknowledged', async () => {
  payment = { ...payment, status: 'pending' };
  const raw = JSON.stringify(testEvent({ id: PID, amount: 20, currency: 'AZN' }, 'success', 'evt_w2'));
  const sig = await signEvent(env.PAYMENTS_TEST_WEBHOOK_SECRET, raw, Math.floor(Date.now() / 1000));
  let r = await post(webhook.handle, 'payments-webhook/test', raw, { 'x-fl-signature': sig });
  assert.equal(r.status, 200);
  assert.equal((await r.json()).result, 'applied');
  applyResult = 'duplicate';
  r = await post(webhook.handle, 'payments-webhook/test', raw, { 'x-fl-signature': sig });
  assert.equal((await r.json()).result, 'duplicate');
  applyResult = 'applied';
});

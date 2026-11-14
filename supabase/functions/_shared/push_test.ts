import { test } from 'node:test';
import assert from 'node:assert/strict';
import { endpointOk, isGone, parseJob, payloadOf, safeUrl, topicOf } from './push.ts';

test('only the real push services are called', () => {
  assert.equal(endpointOk('https://fcm.googleapis.com/fcm/send/abc'), true);
  assert.equal(endpointOk('https://web.push.apple.com/QabcDEF'), true);
  assert.equal(endpointOk('https://updates.push.services.mozilla.com/wpush/v2/abc'), true);
  assert.equal(endpointOk('https://wns2-db5p.notify.windows.com/w/?token=abc'), true);
  assert.equal(endpointOk('http://fcm.googleapis.com/fcm/send/abc'), false);
  assert.equal(endpointOk('https://evil.example.com/fcm.googleapis.com/'), false);
  assert.equal(endpointOk('https://fcm.googleapis.com.evil.com/x'), false);
  assert.equal(endpointOk(42), false);
});

test('the job from the database', () => {
  const j = parseJob({
    id: '0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f',
    kind: 'message',
    title: 'Əli',
    body: 'Yeni mesajınız var',
    url: '/#/chat/0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f',
    tag: 'chat-0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f',
    subscriptions: [{ endpoint: 'https://fcm.googleapis.com/x', p256dh: 'p', auth: 'a' }, { endpoint: 1 }],
  });
  assert.ok(j);
  assert.equal(j!.subscriptions.length, 1);
  assert.deepEqual(JSON.parse(payloadOf(j!)), {
    title: 'Əli',
    body: 'Yeni mesajınız var',
    url: '/#/chat/0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f',
    tag: 'chat-0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f',
    kind: 'message',
  });
  assert.equal(parseJob(null), null);
  assert.equal(parseJob({ id: 'not-a-uuid' }), null);
});

test('a notification opens only the app\'s own pages', () => {
  assert.equal(safeUrl('/#/admin-reports'), '/#/admin-reports');
  assert.equal(safeUrl('https://evil.example.com'), '/');
  assert.equal(safeUrl('/#/x"><script>'), '/');
  assert.equal(safeUrl(undefined), '/');
});

test('topic: at most 32 URL-safe characters, the same per chat', () => {
  const t = topicOf('chat-0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f');
  assert.ok(t.length <= 32 && /^[A-Za-z0-9_-]+$/.test(t));
  assert.equal(t, topicOf('chat-0b0e9d7e-3f2a-4f1b-9a1d-2c3b4a5d6e7f'));
  assert.equal(topicOf('admin-reports'), 'admin-reports');
});

test('gone devices are 404 / 410 only', () => {
  assert.equal(isGone(410), true);
  assert.equal(isGone(404), true);
  assert.equal(isGone(429), false);
  assert.equal(isGone(undefined), false);
});

// Web Push (0121): the pure parts of push-send, tested with
// `node --experimental-strip-types --test supabase/functions/_shared/push_test.ts`.

/** Only the real push services (the same list as SQL _push_endpoint_ok). */
const PUSH_ENDPOINT =
  /^https:\/\/(fcm\.googleapis\.com|android\.googleapis\.com|updates\.push\.services\.mozilla\.com|push\.services\.mozilla\.com|web\.push\.apple\.com|[a-z0-9-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)\//;

export function endpointOk(endpoint: unknown): boolean {
  return typeof endpoint === 'string' && endpoint.length <= 1000 && PUSH_ENDPOINT.test(endpoint);
}

export interface PushDevice {
  endpoint: string;
  p256dh: string;
  auth: string;
}

export interface PushJob {
  id: string;
  kind: string;
  title: string;
  body: string;
  url: string;
  tag: string;
  subscriptions: PushDevice[];
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(x: unknown): x is string {
  return typeof x === 'string' && UUID.test(x);
}

function str(x: unknown, max: number): string {
  return typeof x === 'string' ? x.slice(0, max) : '';
}

/** push_outbox_take's answer → a job (null = nothing to send). */
export function parseJob(x: unknown): PushJob | null {
  if (!x || typeof x !== 'object') return null;
  const o = x as Record<string, unknown>;
  if (!isUuid(o.id)) return null;
  const subs = Array.isArray(o.subscriptions) ? o.subscriptions : [];
  return {
    id: o.id,
    kind: str(o.kind, 40),
    title: str(o.title, 120) || 'TırLink',
    body: str(o.body, 200),
    url: safeUrl(o.url),
    tag: str(o.tag, 80) || 'tirlink',
    subscriptions: subs
      .map((s) => s as Record<string, unknown>)
      .filter((s) => s && typeof s.endpoint === 'string' && typeof s.p256dh === 'string' && typeof s.auth === 'string')
      .map((s) => ({ endpoint: s.endpoint as string, p256dh: s.p256dh as string, auth: s.auth as string })),
  };
}

/** Only the app's own pages ("/#/chat/…"); anything else opens the start page. */
export function safeUrl(x: unknown): string {
  return typeof x === 'string' && /^\/#\/[A-Za-z0-9/_-]{0,180}$/.test(x) ? x : '/';
}

/** What the service worker receives (kept small: the push services allow ~4 KB). */
export function payloadOf(job: PushJob): string {
  return JSON.stringify({ title: job.title, body: job.body, url: job.url, tag: job.tag, kind: job.kind });
}

/**
 * The Topic header (≤ 32 URL-safe characters): an undelivered push with the
 * same topic is replaced, so an offline phone gets one per chat, not many.
 */
export function topicOf(tag: string): string {
  const clean = tag.replace(/[^A-Za-z0-9_-]/g, '');
  return clean.length <= 32 ? clean : clean.slice(clean.length - 32);
}

/** The device unsubscribed / expired: remove it. */
export function isGone(status: unknown): boolean {
  return status === 404 || status === 410;
}

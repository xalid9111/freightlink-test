// WhatsApp phone verification PoC — shared, dependency-free logic.
//
// Used by the `wa-webhook` and `wa-verify-start` Edge Functions. Only Web
// APIs (crypto.subtle, TextEncoder) are used, so the same file runs in
// Supabase Edge (Deno) and in the Node test runner.
//
// Nothing here reads secrets; callers pass them in.

const enc = new TextEncoder();

// ---------------------------------------------------------------------
// Phone numbers
// ---------------------------------------------------------------------

/** "+994 50 123-45-67" / "00994501234567" → "+994501234567"; null if not E.164. */
export function normalizeE164(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  let s = input.trim().replace(/[\s\-(). ]/g, '');
  if (s.startsWith('00')) s = '+' + s.slice(2);
  if (!/^\+[1-9][0-9]{6,14}$/.test(s)) return null;
  return s;
}

/** Business number for wa.me: "+994 12 345 67 89" or "994123456789" → "994123456789". */
export function waMeDigits(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  const t = input.trim();
  const e = normalizeE164(t.startsWith('+') || t.startsWith('00') ? t : '+' + t);
  return e ? e.slice(1) : null;
}

/** Show only the last 3 digits in logs: "+994*******567". */
export function maskPhone(e164OrDigits: string | null | undefined): string {
  if (!e164OrDigits) return '-';
  const s = String(e164OrDigits);
  return s.length <= 4 ? '***' : s.slice(0, s.startsWith('+') ? 4 : 3) + '*'.repeat(Math.max(0, s.length - 7)) + s.slice(-3);
}

// ---------------------------------------------------------------------
// One-time challenge
// ---------------------------------------------------------------------

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
export const CHALLENGE_PREFIX = 'FL-';
export const CHALLENGE_LEN = 24; // 15 random bytes = 120 bits
const CHALLENGE_RE = /(?:^|[^A-Za-z0-9])FL-([A-Z2-7]{24})(?![A-Za-z0-9])/i;

function base32(bytes: Uint8Array): string {
  let bits = 0, value = 0, out = '';
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

/** Cryptographically secure code body (without the "FL-" prefix). */
export function newChallenge(): string {
  const bytes = new Uint8Array(15);
  crypto.getRandomValues(bytes);
  return base32(bytes);
}

/** First FreightLink code found in a message text (upper-cased), or null. */
export function extractChallenge(text: unknown): string | null {
  if (typeof text !== 'string' || text.length > 4096) return null;
  const m = CHALLENGE_RE.exec(text);
  return m ? m[1].toUpperCase() : null;
}

export function prefilledMessage(code: string): string {
  return `FreightLink verification code: ${CHALLENGE_PREFIX}${code}\n` +
    'Send this message without changing it. Do not share this code with anyone.';
}

export function waMeLink(businessDigits: string, text: string): string {
  return `https://wa.me/${businessDigits}?text=${encodeURIComponent(text)}`;
}

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function sha256Hex(text: string): Promise<string> {
  return toHex(await crypto.subtle.digest('SHA-256', enc.encode(text)));
}

// ---------------------------------------------------------------------
// Meta webhook signature: X-Hub-Signature-256: sha256=<hex HMAC of raw body>
// ---------------------------------------------------------------------

/** Constant-time comparison of two strings. */
export function timingSafeEqual(a: string, b: string): boolean {
  const ab = enc.encode(a), bb = enc.encode(b);
  let diff = ab.length ^ bb.length;
  const n = Math.max(ab.length, bb.length);
  for (let i = 0; i < n; i++) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

export async function hmacSha256Hex(secret: string, body: Uint8Array): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return toHex(await crypto.subtle.sign('HMAC', key, body as BufferSource));
}

export async function verifyMetaSignature(rawBody: Uint8Array, header: string | null, appSecret: string): Promise<boolean> {
  if (!header || !appSecret) return false;
  const m = /^sha256=([0-9a-fA-F]{64})$/.exec(header.trim());
  if (!m) return false;
  const expected = await hmacSha256Hex(appSecret, rawBody);
  return timingSafeEqual(expected, m[1].toLowerCase());
}

// ---------------------------------------------------------------------
// Incoming message parsing (Meta WhatsApp Cloud API webhook)
//
// value.messages[].from       sender phone number (digits, no "+") — may be
//                             ABSENT when the user has a WhatsApp username
//                             and Meta withholds the number.
// value.messages[].from_user_id   business-scoped user id (BSUID)
// value.contacts[].wa_id      phone number again (conditional, like from)
// value.contacts[].user_id    BSUID again
// value.statuses[]            delivery receipts — ignored here.
// ---------------------------------------------------------------------

export type SenderKind = 'phone' | 'bsuid_only' | 'conflict' | 'none';

export interface InboundMessage {
  messageId: string;
  phoneNumberId: string | null; // which of our business numbers received it
  type: string;
  text: string | null;
  senderKind: SenderKind;
  senderDigits: string | null; // only when senderKind === 'phone'
  hasBsuid: boolean;
  // Which identity fields were present (for the PoC log — no values).
  fields: { from: boolean; fromUserId: boolean; contactWaId: boolean; contactUserId: boolean };
}

type Json = Record<string, unknown>;
const obj = (v: unknown): Json | null => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Json) : null);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === 'string' && v.length > 0 ? v : null);
const PHONE_DIGITS = /^[1-9][0-9]{6,14}$/;

export function classifySender(from: string | null, contactWaId: string | null, bsuid: string | null): { kind: SenderKind; digits: string | null } {
  const fromOk = from !== null && PHONE_DIGITS.test(from);
  const waOk = contactWaId !== null && PHONE_DIGITS.test(contactWaId);
  if (fromOk && waOk && from !== contactWaId) return { kind: 'conflict', digits: null };
  if (fromOk) return { kind: 'phone', digits: from };
  // `from` missing / not a phone number. A contacts wa_id alone is not
  // trusted as the sender of THIS message.
  if (bsuid || (from !== null && !fromOk)) return { kind: 'bsuid_only', digits: null };
  return { kind: 'none', digits: null };
}

/** All incoming user messages in a webhook body; statuses and other events are skipped. */
export function parseInbound(payload: unknown): InboundMessage[] {
  const out: InboundMessage[] = [];
  const root = obj(payload);
  if (!root || root.object !== 'whatsapp_business_account') return out;
  for (const entry of arr(root.entry)) {
    for (const change of arr(obj(entry)?.changes)) {
      const ch = obj(change);
      if (!ch || ch.field !== 'messages') continue;
      const value = obj(ch.value);
      if (!value) continue;
      const phoneNumberId = str(obj(value.metadata)?.phone_number_id);
      const contacts = arr(value.contacts).map(obj).filter((c): c is Json => c !== null);
      for (const raw of arr(value.messages)) {
        const m = obj(raw);
        const messageId = str(m?.id);
        if (!m || !messageId) continue;
        const from = str(m.from);
        const fromUserId = str(m.from_user_id);
        // The matching contact: same BSUID, else same wa_id, else the only contact.
        const contact = contacts.find((c) => fromUserId && str(c.user_id) === fromUserId)
          ?? contacts.find((c) => from && str(c.wa_id) === from)
          ?? (contacts.length === 1 ? contacts[0] : null);
        const contactWaId = contact ? str(contact.wa_id) : null;
        const contactUserId = contact ? str(contact.user_id) : null;
        const bsuid = fromUserId ?? contactUserId;
        const { kind, digits } = classifySender(from, contactWaId, bsuid);
        const type = str(m.type) ?? 'unknown';
        out.push({
          messageId,
          phoneNumberId,
          type,
          text: type === 'text' ? str(obj(m.text)?.body) : null,
          senderKind: kind,
          senderDigits: digits,
          hasBsuid: bsuid !== null,
          fields: { from: from !== null, fromUserId: fromUserId !== null, contactWaId: contactWaId !== null, contactUserId: contactUserId !== null },
        });
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------
// Small helpers for the Edge Functions
// ---------------------------------------------------------------------

/** New (sb_secret_…) API keys are not JWTs and go only in `apikey`. */
export function supabaseHeaders(key: string): Record<string, string> {
  const h: Record<string, string> = { apikey: key, 'Content-Type': 'application/json' };
  if (key.split('.').length === 3) h.Authorization = `Bearer ${key}`;
  return h;
}

export const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

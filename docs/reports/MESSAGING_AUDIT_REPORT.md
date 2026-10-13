# Messaging audit — carrier ↔ cargo owner (FreightLink)

## Root cause of "sometimes I can write, sometimes not"
1. **Silent no-op in the chat screen (main cause).** The thread computed
   the receiver from the cached *conversation list*
   (`myConversationsProvider`, a one-shot FutureProvider). Right after a
   carrier tapped "Mesaj göndər" on a cargo for the first time, the new
   conversation was not in that cached list → `_receiverId()` returned
   null → `_sendText` simply `return`ed. No error, text cleared, nothing
   saved. After any refresh it "worked" — hence the random behaviour.
   The header (name / online / call) was empty for the same reason.
2. **Owner did not see new chats.** The owner's conversation list was a
   one-time fetch and `conversations` was not in the Realtime
   publication, so a carrier's first message did not create a visible
   chat on the owner's side until a manual refresh → owner "can't reply".
3. **Double tap race.** "Mesaj göndər" did SELECT-then-INSERT from the
   client with no busy guard; two quick taps → second INSERT hit the
   unique key (cargo_id, carrier_user_id) → unhandled error.
4. **Errors swallowed.** The button had no try/catch; the composer
   ignored the "no receiver" case.

## RLS / data problems found
- `conversations_create`: only required auth.uid() to be one of the two
  ids; it never checked that `cargo_owner_id` is the cargo's real owner
  (a chat could be opened with the wrong user).
- `messages_send`: only `sender_id = auth.uid()` — any signed-in user
  could insert into any conversation with any receiver. A mis-addressed
  row is invisible to the other participant (SELECT was sender/receiver
  based).
- `messages_mark_read`: receiver could update ANY column (e.g. rewrite
  the text), not just read_at.
- No monetization gate was found in the messaging path (no
  contact_unlock / credits / subscription check in RLS or client); the
  only credit gate (contact unlock) was already removed from the UI.

## Fix (migration 0011_messaging_hardening.sql — no data deleted)
- RPC `get_or_create_conversation(p_cargo_id, p_carrier_user_id, p_carrier_id)`
  (SECURITY DEFINER): owner taken from the cargo, carrier from auth.uid()
  (or, for the owner, the chosen carrier), INSERT … ON CONFLICT DO
  NOTHING, returns the single row. Atomic — no duplicates, no wrong
  recipient, double-tap safe. Only carrier/driver/admin accounts can
  open a chat on someone else's cargo.
- `conversations_create` now also requires the real cargo owner.
- `messages_send` requires: sender = auth.uid(), sender is a participant,
  receiver = the OTHER participant.
- Extra SELECT policy: participants see every message of their
  conversations.
- Trigger `guard_message_update`: non-admins can only set read_at.
- `conversations` (and `messages`, if missing) added to supabase_realtime.
- Repair: legacy messages with a wrong receiver_id are re-addressed to
  the other participant (no deletion).

## App changes
- Chat screen loads its conversation **by id** (`conversationByIdProvider`)
  and derives me/other from it; sending throws on any problem, so the
  composer keeps the text and shows "Göndərilmədi".
- Conversation list is a **live stream** (new chats appear instantly).
- "Mesaj göndər" uses the RPC, is busy-guarded, shows errors
  ("only carriers can message" / "could not open chat").
- Cargo owner can start a chat from any received offer ("Daşıyıcıya yaz").
- On resume / tab shown (iOS PWA & Safari drop the websocket in the
  background) all chat streams re-subscribe automatically.
- Location send distinguishes "no location" from "not sent".
- Fallback paths keep the app working even before 0011 is run.

## Tests
- `supabase/tests/messaging_audit_test.sql` — 2 owners + 2 carriers,
  7 scenarios (create once, wrong receiver blocked, isolation between
  users, owner sees & replies, owner→carrier reuse, non-carrier blocked,
  mark-read can't edit text). Runs in ONE transaction that is ROLLED BACK.
- Static checks in this environment (no Flutter SDK / no network here):
  code review + bracket/structure checks; real build via GitHub Actions.

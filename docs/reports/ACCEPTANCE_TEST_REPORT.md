# Acceptance Test Report — Two-Phone Flow (Cargo Owner ↔ Carrier)

## Read this first: what I could and couldn't actually verify

No Flutter SDK, Dart SDK, or network access exists in the environment I
work in — confirmed again before starting this pass, same as every
prior phase. **I have not run this app.** Everything below is the
result of:
1. Writing the code to match the existing, already-partially-verified
   architecture (repositories, RLS, providers) from Phases 1–4.
2. Three static validator scripts (`validate_dart.py`,
   `validate_sql.py`, `validate_i18n.py`) — all passing, re-run after
   every change.
3. Careful manual, line-by-line tracing of the exact acceptance-test
   flow against the database schema and RLS policies — described
   below — which is how I found and fixed two real, serious bugs
   before you ever get to try it.

Real verification is `flutter analyze` + `flutter build` + the actual
two-phone test, on your machine, per `SETUP_GUIDE.md`.

## Two real bugs found and fixed during this pass (do this first)

**You must run `supabase db push` again** — two new migrations exist
that fix bugs this acceptance test would have hit immediately:

1. **`0007_auto_create_carrier_profile.sql`** — a carrier signing up
   never got a `carriers` table row created for them. Every offer,
   credit-wallet, and "am I a carrier" check depends on that row
   existing. Without this fix, **User B (carrier) would be able to log
   in but every attempt to submit an offer would fail.**
2. **`0008_fix_shipments_insert_policy.sql`** — the `shipments` table
   had no INSERT policy for a regular user at all (only admin). Without
   this fix, **User A accepting an offer would appear to succeed (the
   offer's status would flip) but silently fail to create the actual
   shipment record**, and the Shipments tab would stay empty for both
   users.

Both were found by deliberately tracing the acceptance test step by
step against the RLS policies rather than just writing UI code and
assuming the backend would cooperate — see `PWA_TECHNICAL_NOTES.md`
(to be updated) for the full technical detail.

**If you already ran `supabase db push` before this message**, run it
again — it only applies new migration files, it won't re-run 0001–0006.

## Walking through the exact acceptance test

### USER A (cargo owner, iPhone) publishes a real cargo load
- Registers (as built and verified in Phase 3) → lands on the Home tab.
- Taps the **"Yeni yük yerləşdir"** floating button (only shown to
  cargo owners) → real form → **Publish cargo** → writes to
  `public.cargo` via `CargoRepository.create()`, `owner_id` is A's own
  id (RLS-enforced, not just client-trusted).
- Redirects to the new cargo's detail page.
- **Status: should work**, contingent on migrations + a real compile.

### USER B (carrier, Android) sees that same cargo from the shared database
- Registers as a carrier → migration 0007's trigger creates their
  `carriers` row → migration 0006's existing trigger fires off that
  insert and grants 3 free contact-unlock credits.
- Opens the Home tab → `marketplaceProvider` fetches
  `public.cargo` directly from Supabase — **the exact same table A just
  wrote to.** No mock data anywhere in this path. Pull-to-refresh or a
  simple re-open picks up A's new listing.
- **Status: should work**, same caveats as above.

### USER B opens the cargo, submits an offer, and sends a message
- Taps the card → cargo detail screen → sees the real "Your offer"
  form → **Submit offer** → `OfferRepository.submit()` → RLS
  (`offers_carrier_insert`) requires `carrier_id = current_carrier_id()`,
  which now resolves correctly (see bug #1 fix).
- Taps **"Mesaj göndər"** → `getOrCreateConversation()` → RLS
  (`conversations_create`) allows it since B is `carrier_user_id` →
  thread screen opens, B types and sends → **Supabase Realtime**
  delivers it (migration 0001 already publishes `public.messages` for
  this — unchanged, pre-existing).
- **Status: should work.**

### USER A can see the offer/message and respond
- A's cargo detail screen shows **"Daxil olan təkliflər"** (offers
  received) via `offersForCargoProvider` — RLS already scoped this
  correctly (unchanged from Phase 2).
- A's **Messages tab** shows the conversation B started (A is
  `cargo_owner_id` on that row, covered by the existing
  `conversations_participants` select policy) → opens the same
  real-time thread, can reply.
- A taps **accept** on B's offer → `OfferRepository.respond()` (status
  → accepted) → `ShipmentRepository.createFromAcceptedOffer()` — this
  is exactly where bug #2 would have silently failed. With the fix,
  this now creates a real `shipments` row.
- **Status: should work, specifically because of the 0008 fix** — this
  step was actually broken before this pass.

## Known gaps / rough edges (not blockers for this specific test, but worth knowing)

- **No "message this carrier" button from A's offers-received list.**
  A can only open a conversation that already exists (started by a
  carrier). Since the acceptance test has B message first, this
  doesn't block it — but A can't proactively message a carrier who
  hasn't messaged yet. Worth adding next.
- **Accepting one offer doesn't auto-reject the others**, and doesn't
  change `cargo.status`. If more than one carrier offers, A can
  currently accept more than one — the second acceptance attempt would
  fail at the database level (shipments.cargo_id is UNIQUE) but surface
  as a generic error rather than a clear "already accepted" message.
  Not reachable with exactly one carrier, as in this test.
- **"Start Navigation" only appears if A filled in optional
  latitude/longitude** on the create-cargo form. If skipped, the
  button area just shows "koordinatlar mövcud deyil" instead of
  crashing — honest, but means this specific piece of the test needs A
  to fill in those two optional coordinate fields to actually see it
  fire.
- **Date formatting locale fix**: while wiring this, I found pickup/
  delivery dates would have silently stayed in English month names
  regardless of the selected app language (a real but easy-to-miss i18n
  gap). Fixed — all date displays now follow the active language.
- **Contact-unlock** requires the carrier to have at least 1 credit
  (new carriers get 3 automatically via the migration 0006→0007 trigger
  chain — but only for accounts created *after* 0007 is applied).

## What was NOT touched

Per your explicit instruction: no existing PWA config, no auth flow,
no bottom nav structure, and no already-correct RLS policy was
rewritten — only two genuinely missing policies/triggers were added as
new, additive migrations (0007, 0008), consistent with the
never-edit-an-applied-migration rule established since Phase 2.

## Bottom line

Every piece of the acceptance test has a real, wired implementation —
no mock/demo data anywhere in this flow. Two real backend bugs were
found and fixed that would have broken it at the exact two steps you
specified (carrier submitting an offer; owner's acceptance creating a
shipment). The honest remaining risk is what static analysis can't
catch: you have not yet run `flutter analyze`/`flutter build`, and I
have not been able to either. That is the next real gate before the
actual two-phone test — see `SETUP_GUIDE.md` for exact commands.

# FreightLink — Phase 2 Report: Database

## 0. Phase 1 review — findings and fixes

| # | Check | Result |
|---|---|---|
| 1 | Flutter project structure really works | **Caveat.** The folders/files are hand-written to a correct Dart/Flutter package layout, but I have no Flutter SDK or network in this sandbox, so I could not run `flutter pub get` or `flutter analyze` to prove it compiles. Treat it as unverified until you run those locally. |
| 2 | Supabase configuration correct | Yes, with one design fix: Phase 1's schema mixed Azerbaijani status values (`'boş'`, `'məşğul'`) with English ones (`'new'`, `'carrier_found'`) across different tables. Fixed in migration 0001: **all workflow statuses (cargo, shipments, offers, verification) are now English enums**, stored language-neutral; only the UI layer localizes them via `assets/i18n/*.json`. Truck/carrier operational status (`boş/məşğul/yola_hazır/servisdə`) was intentionally left in Azerbaijani since the brief gave those exact labels as the domain vocabulary, not as translatable UI copy. |
| 3 | Migration SQL syntax errors | **One real bug found and fixed**: a malformed generated column (`carrier_payout amount_check numeric(10,2)` — a leftover invalid token) in the `payments` table while drafting. Caught by static review, fixed to a proper `generated always as (...) stored` column. Full validation: `scripts/validate_sql.py` (parenthesis/quote balance, dangling FK targets, duplicate policy names) — see §5. |
| 4 | RLS policies correct | Phase 1 had gaps: no RLS on `drivers`, no participant-scoped policy for `shipment_status`, and `ai_matches`/`payments` had no policy at all (meaning read access was fully closed, not intentionally scoped). All fixed in migration 0002 — see §4 below for the full table. |
| 5 | Environment variables separated correctly | Yes, unchanged from Phase 1 — `.env` / `.env.example`, `Env` class, nothing hardcoded. |
| 6 | i18n structure works | Yes, unchanged — `assets/i18n/az.json` and `en.json` populated, `tr/ru/ka.json` stubbed, referenced in `pubspec.yaml` assets. |
| 7 | Anything blocking future AI matching | No blocker. `ai_matches` schema is richer now (`matching_reasons`, `estimated_distance`, `estimated_duration`, `distance_to_pickup` as separate fields instead of one bundled `reasons` object) so the Phase 11 Edge Function has room to return everything the brief's example (`96% uyğunluq`, pickup distance, estimated route, estimated earnings) needs without another migration. |

## 1. What was created

**Migrations** (`supabase/migrations/`):
- `0001_schema.sql` — all 21 tables, FKs, indexes
- `0002_rls.sql` — RLS enabled + policies on every table
- `0003_seed.sql` — demo data, all flagged `is_demo = true`

**Validation tool:** `scripts/validate_sql.py` — static structural checker (see §5).

**Dart data layer** (`lib/`):
- `models/`: `cargo_model.dart` (rewritten), `offer_model.dart`, `shipment_model.dart`, `rating_model.dart`, `ai_match_model.dart`, `message_model.dart` (+`ConversationModel`) — all new
- `features/cargo/domain|data/`: `cargo_repository.dart` / `cargo_repository_impl.dart` — field names updated to match the finalized schema, plus a new `fetchReturnCandidates()` method for the return-cargo AI feature
- `features/chat/domain|data/`: `message_repository.dart` / `message_repository_impl.dart` — new, uses Supabase Realtime (`.stream()`) against `public.messages`
- `repositories/`: `offer_repository.dart`, `shipment_repository.dart`, `rating_repository.dart`, `ai_match_repository.dart` — new, cross-feature repositories per the Phase 1 README's stated pattern

## 2. Files changed since Phase 1

- **Replaced:** `supabase/migrations/0001_init.sql` → split into `0001_schema.sql` + `0002_rls.sql` + `0003_seed.sql` (real projects keep schema, security, and seed data as separate, independently-revertible migrations)
- **Rewritten:** `lib/models/cargo_model.dart`, `lib/features/cargo/domain/cargo_repository.dart`, `lib/features/cargo/data/cargo_repository_impl.dart` — field names now match the exact spec (`weight_kg`, `pickup_country/city/address/latitude/longitude`, etc.) instead of Phase 1's placeholder names (`weight_tons`, `from_country`)
- **Added:** everything listed in §1 above
- **Unchanged:** `lib/core/*`, `lib/main.dart`, `lib/features/auth/*`, `lib/services/{map,payment,notification}_service.dart`, `pubspec.yaml`, `.env.example`

## 3. Database structure (21 tables)

```
users ──┬── companies ──┬── carriers ──┬── drivers
        │               │              ├── trucks
        │               │              └── (ai_matches, offers, ...)
        └── cargo ──┬── cargo_documents
                     ├── offers ──── shipments ──┬── shipment_status
                     │                            ├── routes
                     │                            ├── locations
                     │                            └── payments
                     └── conversations ──── messages ──── message_attachments

ratings, verification_documents, notifications, ai_matches, platform_settings
```

Every table has `id uuid` (`uuid_generate_v4()`), and every mutable table has both `created_at` and `updated_at` (append-only tables like `shipment_status`, `locations`, `messages` intentionally have only `created_at`/`recorded_at`, since a log row is never edited).

Notable additions beyond the literal table list, both necessary for the fields you explicitly requested:
- **`conversations`** — `messages.conversation_id` needs something to reference; one conversation groups a cargo + its two participants.
- **`message_attachments`** is its own table (not inlined on `messages`) so one attachment could in principle be referenced by more than one message without duplicating the file URL.

## 4. Security / RLS status

RLS is **enabled on all 21 tables**, default-deny (a table with RLS on and no matching policy blocks every request). Summary:

| Rule from your brief | Enforced by |
|---|---|
| Cargo owner edits only their own cargo | `cargo_owner_write` policy: `auth.uid() = owner_id` |
| Carrier edits only their own truck/profile | `trucks_carrier_write`, `carriers_owner_write`: scoped via `current_carrier_id()` |
| Driver edits only their own profile | `drivers_self_update`: `auth.uid() = user_id` |
| Users cannot alter others' private data / cannot self-promote to admin | `users_update_self` — `with check` re-asserts the stored `role`, so a user can update their name but never their own role |
| Messages visible only to conversation participants | `messages_participants_select`: `auth.uid() = sender_id or receiver_id` |
| Payments visible only to involved parties | `payments_participants_select`: `auth.uid() = payer_id or payee_id`; no client insert/update policy exists at all — only a service-role Edge Function can write payments (Phase 15) |
| Admin has full access | `is_admin()` security-definer function, used in an `is_admin()`-gated policy on every table |

Two deliberate "closed" spots, not oversights: `ai_matches` and `payments` have **no client-side insert policy** — those rows are only ever written by a service-role key inside an Edge Function (Phase 11 / Phase 15), so a compromised anon-key client can never fabricate a match score or a payment.

## 5. What was tested (and what could not be)

**Could run in this sandbox (no network, no Postgres/Supabase CLI available):**
- `scripts/validate_sql.py` — static checker across all 3 migration files: parenthesis/quote balance, every `references public.X(...)` points at a table actually defined, no duplicate RLS policy names, every `create policy` targets a table where RLS was enabled. **Result: 0 problems** (after fixing the `payments.carrier_payout` typo found during drafting).
- Manual line-by-line review of every RLS policy against the specific rule it's meant to enforce (table in §4).
- Rough brace-balance sweep across every new/changed Dart file — all balanced.

**Could not run here, needs to happen on your machine / a real Supabase project:**
- `supabase db push` against a live Postgres instance (the actual syntax test that matters)
- `flutter pub get` / `flutter analyze` to confirm the Dart compiles against the real `supabase_flutter` package API
- Actual RLS behavior testing (sign in as a demo cargo owner and a demo carrier, confirm cross-account writes are rejected) — the seed data in `0003_seed.sql` creates exactly the two owner accounts + one carrier account needed to do this by hand

Suggested commands once you have the Supabase CLI linked to a project:
```
supabase db push
supabase db execute --file supabase/migrations/0003_seed.sql   # or let db push run it if in the migrations dir
flutter pub get && flutter analyze
```

## 6. Open items / known limitations going into Phase 3

- `pickup_latitude/longitude` indexes are plain B-tree, not PostGIS — fine at MVP scale, but "nearby cargo/trucks" (brief §14) will want `geography(Point)` + a GiST index once you have real query volume. Left a comment on `idx_cargo_pickup_geo` noting this.
- `offers` has a `unique (cargo_id, carrier_id, created_at)` constraint rather than one-active-offer-per-carrier — a carrier can currently submit multiple offers over time on the same cargo (e.g. after a rejection). If you want to hard-limit to one *pending* offer at a time, that needs a partial unique index (`where status = 'pending'`), which I did not add without confirming that's the behavior you want.
- Row Level Security is only as strong as the app never using the service-role key on the client — `SupabaseConfig` in Phase 1 already only exposes the anon key, so this is consistent, just flagging it as a standing rule for every future phase.

Phase 2 is otherwise complete per your checklist. Let me know if you want the one-active-offer constraint added before we move to Phase 3 (Authentication UI), or if we should proceed as-is.

## Addendum — one-active-pending-offer rule

Added via **`supabase/migrations/0004_offer_resubmission_rule.sql`**, a new
migration (existing ones were left untouched — see the migration's own
header comment for why editing an already-applied migration is unsafe).

- Added `'expired'` to `offers.status`'s allowed values (drop + recreate
  the check constraint — Postgres has no `ADD VALUE` for inline checks).
- Added a **partial unique index**: `unique (cargo_id, carrier_id) where
  status = 'pending'`. Non-pending rows are invisible to this index, so
  history is preserved without limit, and Postgres itself rejects a
  second concurrent pending insert (`23505 unique_violation`) — this is
  safe under a race because the index is enforced inside Postgres'
  normal transactional locking, not by application logic checking first.
- `lib/repositories/offer_repository.dart` was updated to match: `submit()`
  catches `23505` and raises a friendly `AppException` instead of a raw
  Postgrest error; added `updatePendingOffer()` and `withdraw()` so the
  UI has the "update or withdraw instead of resubmitting" path the rule
  implies, and `markExpired()` for a future scheduled sweep.
- Static validation re-run (`scripts/validate_sql.py`) after the change:
  0 problems across all 4 migration files.

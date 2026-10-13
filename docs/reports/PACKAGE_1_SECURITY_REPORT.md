# Package 1 — Critical database security

Status: **ready for review. NOT applied to production.** Nothing in this package touches the production database automatically.

## Files changed

| File | Change |
|---|---|
| `supabase/migrations/0018_package1_security.sql` | **New** forward-only corrective migration (0001–0017 untouched) |
| `lib/features/services/data/services_repository.dart` | Explicit column lists for `service_providers`; `admin_note` fetched via new RPC (with pre-0018 fallback) |
| `supabase/tests/local/00_supabase_stub.sql` | **New** – minimal Supabase stand-in (roles, `auth.*`, `storage.*`, default grants) for a disposable Postgres |
| `supabase/tests/local/10_fixtures.sql` | **New** – test users/providers/reports |
| `supabase/tests/local/15_test_helpers.sql` | **New** – `tests.login/err/check/summary` |
| `supabase/tests/local/20_package1_before.sql` | **New** – reproduces each vulnerability on 0001–0017 |
| `supabase/tests/local/30_package1_after.sql` | **New** – 58 role-based checks on 0001–0018 |
| `supabase/tests/local/run_local.sh` | **New** – runner (refuses any DB whose name lacks `test`) |

## Findings and fixes

### 1. Anyone could register as an admin — CRITICAL (found during the SECURITY DEFINER review)
- **Root cause:** `handle_new_auth_user()` (0005) copies `raw_user_meta_data->>'role'` into `users.role`. That metadata is whatever the client sends to `auth.signUp(data: …)`, and the `role` CHECK allows `'admin'`.
- **Impact:** with only the public anon key, `signUp(..., data: {'role': 'admin'})` creates a full admin: every admin RPC, all users' data, moderation, deletes.
- **Fix:** only `cargo_owner`, `carrier`, `driver` are accepted from signup; anything else becomes `cargo_owner`. Normal signups behave exactly as before.
- **Action for you:** run the read-only audit query at the end of 0018 to list every admin and the role each one requested at signup. The migration does not change any existing account.

### 2. Pending service profiles visible to everyone — HIGH
- **Root cause:** policy `service_providers_select` allowed `status in ('pending','approved')` for all users; `nearby_services()` filtered the same way.
- **Impact:** unmoderated profiles (unverified phone numbers, addresses, possibly spam) were shown on the public map and detail pages.
- **Fix:** ordinary users see `approved` profiles whose owner is not blocked; owners see their own profile in any status; admins see all. `nearby_services()` returns approved only (also for the owner and admins; the admin moderation list is separate).
- **Behaviour change:** a newly registered service no longer appears on the map until an admin approves it. This is what the brief asks for, but the owner should be told; the existing status note on the owner's screen already shows "pending".

### 3. `admin_note` readable by every signed-in user — HIGH
- **Root cause:** RLS filters rows, not columns. Any user could `select admin_note` from any visible profile, and `nearby_services()` returned `to_jsonb(s.*)` including the note.
- **Impact:** internal moderation remarks (e.g. reasons for suspicion or rejection) disclosed to the public.
- **Fix:** column privileges — API roles can read every column except `admin_note`. New `service_provider_notes(uuid[])` (SECURITY DEFINER) returns the note only for the caller's own profile or, for admins, any profile. `nearby_services()` builds its result from an explicit column list without the note.
- **Consequence for clients:** `select()` / `select('*')` on `service_providers` is now refused, which is why the Flutter repository was changed (see Deployment order).

### 4. `guard_service_provider()` bypass — HIGH
- **Root cause:** the trigger let any change through when the session setting `app.service_rating_sync` was `on`. Session settings can be set by any SQL session with `set_config()`; they are not a security boundary. The function was SECURITY DEFINER, so it could not see who really issued the statement. Blocked owners could also keep editing.
- **Impact:** an owner who can run `set_config` in the same transaction could self-approve, self-verify, set any rating, or transfer ownership (reproduced in test R5). I could not find a way to do this through the standard Supabase REST API today, but any future RPC or direct connection that lets user code set a setting would open it.
- **Fix:** trigger is now SECURITY INVOKER and decides on `current_user`, which a client cannot forge: `anon`/`authenticated` = API request, rules enforced (admins excepted via `is_admin()`); any other role (SQL editor, `service_role`, every SECURITY DEFINER function such as `admin_*` and `recalc_service_rating`) = trusted server code. The session flag is gone from both functions. Blocked users get `account_blocked` on update. `id` and `created_at` are now pinned too.

### 5. SECURITY DEFINER, EXECUTE privileges, search_path — MEDIUM
- **Root cause:** `is_admin()` and `current_carrier_id()` (0002) had no `search_path`; all other definer functions had `public` without `pg_temp` last. Supabase grants EXECUTE on every new function to `anon`, so all admin and user RPCs were callable without login (each refuses inside, but the entry point existed).
- **Fix:** every SECURITY DEFINER function in `public` now has `search_path = public, pg_temp` (bodies unchanged; the migration fails and rolls back if one is missed). EXECUTE on all 39 RPCs the app uses is revoked from `anon`/`PUBLIC` and kept for `authenticated`; `_require_admin()` is internal only. Helpers used inside RLS policies keep their grants on purpose, because revoking them would turn anonymous table reads into errors (test D7).

### 6. Broad `reports` constraint rewrite in 0017 — MEDIUM (reliability)
- **Root cause:** 0017 dropped every CHECK on `reports` whose text mentioned `target_type`, whatever its name, then added a fixed list. Any stored value outside that list would abort the migration.
- **Fix:** 0018 touches only `reports_target_type_check` by exact name, keeps every target type already stored (reported in a NOTICE), and does nothing when the constraint is already correct. On a database where 0017 succeeded it is a no-op (verified).

## Tests actually executed (disposable PostgreSQL 16.15, Supabase stand-in)

| Suite | Result |
|---|---|
| All migrations 0001–0017 apply on a clean DB | OK |
| `20_package1_before.sql` — reproduce issues on 0001–0017 | **9/9 reproduced** (R1 admin signup, R2 pending visible, R3 notes readable, R4 RPC leaks pending+notes, R5 guard bypass, R6 blocked owner edits, R7 anon EXECUTE, R8 no search_path, R9 block_reason readable) |
| Data preservation — row count + MD5 of all 38 public tables before/after 0018 | **Identical** |
| `30_package1_after.sql` on 0001–0018 | **58/58 passed** |
| Re-apply 0018, run after-suite again (idempotency) | **58/58 passed** |
| Existing `supabase/tests/messaging_audit_test.sql` on 0001–0018 | **T1–T7 passed** |
| `reports` edge case: constraint loosened by hand + an `'ad'` report stored | `'ad'` kept, constraint rebuilt, no row lost |
| EXECUTE matrix for the 39 RPCs the app calls | all `authenticated`=yes, `anon`=no |
| `scripts/validate_dart.py` (project's static checker) | 103 files, no structural issues |

Roles covered in the after-suite: owner (pending, rejected, suspended, approved), unrelated user, admin, blocked user, unauthenticated, plus trusted server paths (admin RPCs, rating recalculation, signup trigger).

## Tests NOT executed, and why
- **`flutter pub get / analyze / test / build web`** — the Flutter SDK cannot be downloaded in this environment (Google storage returns 403). The Dart change is small and uses APIs already used elsewhere in the project (`select(cols)`, `inFilter`, `PostgrestException.code`), but it has **not been compiled**. Please run `flutter analyze` before deploying.
- **Against real Supabase** (PostgREST, GoTrue, Realtime, Storage) — not reachable from here, and not allowed by the brief. The local stand-in reproduces roles, `auth.uid()`, grants and RLS exactly, but not PostgREST itself. Recommended on a staging/branch project: open the services map, a profile detail, your own profile (status note visible), the admin services list (notes visible), and register a test account with `role: 'admin'` in metadata.
- **Concurrency / rating races, claims, reviews** — Package 2 scope.

## Deployment order (important)
1. Back up production.
2. Run `flutter analyze`, then deploy the new web build. It works **before and after** 0018.
3. Wait for clients to pick up the new build (PWA reload). Clients still on the **old** build will get "permission denied" on service detail/edit/admin-services after 0018 because they read `select *`.
4. Apply `0018_package1_security.sql` (`supabase db push`, or the SQL Editor; with psql use `--single-transaction`).
5. Run the admin audit query from the bottom of the migration.

## Remaining risks / open items
1. **`users.block_reason`, `is_blocked`, `blocked_until`, also `email`/`phone` are readable by every signed-in user (R9). Not fixed.** The fix (column privileges plus RPCs) breaks the admin Users page, which streams `users` with `select *` over Realtime, and the public profile screen. It needs an admin-panel data-loading change I can't compile here. **Decision needed:** fix it as a "Package 1b" now, or schedule it into Package 4.
2. Other guards (`guard_user_protected_columns`, `guard_cargo_hidden`, `guard_message_update`) still use the `auth.uid() is null` shortcut. Not exploitable today (anonymous users have no write policy on those tables), but it's the same fragile pattern. Low priority; can move to the `current_user` model later.
3. Owners can still change name/address/location/photos of an **approved** profile without re-approval — Package 2, item 1.
4. Reviews of non-approved providers, blocked users editing existing reviews, and claims on rejected/suspended unowned profiles are still possible — Package 2.
5. `is_blocked(uuid)` can be called by any signed-in user for any id (same information is already exposed by item 1).
6. New columns added to `service_providers` later are **not** readable until granted explicitly (deny by default). Future migrations must add a `grant select (new_col)`.

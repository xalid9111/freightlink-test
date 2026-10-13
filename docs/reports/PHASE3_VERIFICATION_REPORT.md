# FreightLink — Phase 3 Verification Report

Scope of this pass: **no new features.** Full review of the existing
Phase 3 project for compile-time errors and integration problems, and
preparation for running on a real device with a real Supabase project.

This sandbox still has no Flutter SDK, no Dart SDK, and no network
access (checked again at the start of this pass — same as every prior
phase). Everything below is either (a) something I found and fixed
through careful manual/static review, clearly marked as such, or (b)
explicitly flagged as **not run here** and left for you to run per
`SETUP_GUIDE.md`. Nothing here claims a compile or a live Supabase test
actually happened in this environment.

## 1. Real bugs found and fixed

### 1.1 — Registration would have failed on every real Supabase project (critical)
`public.users` had RLS enabled with **no INSERT policy** for a normal
user — only an admin-only policy existed. The original
`AuthRepositoryImpl.signUp()` tried `.from('users').insert(...)` as the
newly-registered (non-admin) user, which Postgres would reject outright.
This is exactly the kind of bug that's invisible without a real
Postgres+RLS instance to test against, which is why it survived Phase 2
and 3's own reports (both honestly noted this couldn't be tested here).

**Fix:** `supabase/migrations/0005_fix_user_registration_trigger.sql` —
a `SECURITY DEFINER` trigger on `auth.users` that creates the
`public.users` row itself, server-side, independent of RLS. This is the
standard Supabase pattern for this exact problem.

### 1.2 — The email-confirmation edge case (item 3 you asked me to check) compounds bug 1.1
Even with an RLS policy allowing self-insert (`with check (auth.uid() =
id)`), if the Supabase project has **"Confirm email" enabled — the
default for new projects** — `auth.signUp()` returns with `session ==
null` until the user clicks the emailed link. With no session, there is
no `auth.uid()` yet, so a client-side insert would fail for a *second*,
different reason even after fixing 1.1 in isolation.

**Fix:** same trigger as 1.1 — it runs at the database level regardless
of session state, so it works identically whether "Confirm email" is on
or off. On the Flutter side: `signUp()` now returns a new
`SignUpResult(user, needsEmailConfirmation)` instead of a bare
`AppUser`, and `RegisterScreen` shows an explicit "check your email"
dialog when `needsEmailConfirmation` is true, instead of silently doing
nothing while the router waits for a session that isn't coming until
the user checks their inbox.

### 1.3 — Seed migration used `crypt()`/`gen_salt()` without enabling `pgcrypto`
`0003_seed.sql` calls these functions to fake password hashes for demo
accounts, but never ran `create extension if not exists pgcrypto;`.
Supabase projects normally have this enabled already (GoTrue itself
depends on it), but the migration was silently relying on that being
true rather than declaring it.

**Fix:** added the `create extension if not exists pgcrypto;` line.
Also hardened the `insert into auth.users` statement with explicit
`instance_id`/`aud`/`role` values (matching what a real `signUp()` call
produces) to reduce the chance of hitting a schema mismatch on your
specific Supabase project version, and added an explicit comment
flagging that writing directly to `auth.users` is a community pattern,
not an officially stable API — with the exact fallback if it fails (see
`SETUP_GUIDE.md` Part 4, step 7).

### 1.4 — A type-variance bug in the Google/Apple button wiring
`login_screen.dart`'s `_OAuthRow` had a local `tryOAuth(Future<void>
Function() call)` helper, called as `tryOAuth(repo.signInWithGoogle)`.
`signInWithGoogle`/`signInWithApple` return `Future<AppUser>`. In Dart,
`Future<AppUser> Function()` is **not** a subtype of `Future<void>
Function()` — the "any return type is compatible with void" exception
in Dart only applies to a literal `void` return type, not a generic
like `Future<void>`. This would very likely have been flagged by
`flutter analyze` as a real type error.

**Fix:** changed `tryOAuth`'s parameter type to `Future<dynamic>
Function()`, which `Future<AppUser> Function()` legitimately satisfies.

### 1.5 — `mapbox_maps_flutter` / `firebase_core` / `firebase_messaging` would likely break a real build before Phase 10/12
Confirmed via grep: **no Dart file imports any of these three
packages** — they were declared in `pubspec.yaml` in Phase 1 purely so
later phases wouldn't need a pubspec change. But merely declaring
`mapbox_maps_flutter` is enough to break `flutter run` on Android before
you've written a single line of map code: it needs a Mapbox *downloads*
token as a Gradle property to even resolve its native dependency, or
Gradle sync fails with 401. `firebase_core`/`firebase_messaging` have a
similar risk without `flutterfire configure` having been run. Since you
asked specifically to make Phase 3 runnable, and Phase 3 touches neither
package, this was a real blocker for the stated goal, not a hypothetical
one.

**Fix:** commented out all three in `pubspec.yaml` with an explanatory
block, to be uncommented when Phase 10 (Map) / Phase 12 (Notifications)
actually start, after their one-time external setup is done.

### 1.6 — Minor: `Riverpod`'s `.asData?.value` swapped for `.valueOrNull`
Not a confirmed bug — `.asData` still exists in `flutter_riverpod
^2.5.1` — but `.valueOrNull` is the current, unambiguously-supported
accessor for "give me the last known value regardless of loading/error
state", and there was no reason to risk a deprecation warning (or worse,
if a transitive dependency pin drifts) for a one-line change.

## 2. What was verified by careful review (not by compiling)

Since `flutter analyze` isn't available here, every changed/new file
was manually cross-checked line-by-line against:
- the actual public API of the pinned package versions
  (`supabase_flutter ^2.5.6`, `go_router ^14.2.0`, `flutter_riverpod
  ^2.5.1`, `intl_phone_field ^3.2.0`, `equatable ^2.0.5`),
- every provider (`appRouterProvider`, `authRepositoryProvider`,
  `authStateProvider`, `currentUserProvider`) confirmed defined exactly
  once and imported everywhere it's used (grepped, not assumed),
- every relative `import '...'` confirmed to resolve to a real file via
  `scripts/validate_dart.py` (see §3),
- the full auth flow (item 2 of your request) traced screen-by-screen
  against the router's `redirect` logic and the auth provider stream —
  documented step-by-step in `SETUP_GUIDE.md`'s "What you should see"
  section, which doubles as the manual test script since there's no
  automated one here,
- migration 0004 (item 4) re-verified specifically:
  - `offers_status_check` constraint name confirmed correct (Postgres'
    default `<table>_<column>_check` naming for an unnamed inline CHECK,
    matching exactly how it was declared in `0001_schema.sql`),
  - the partial unique index (`(cargo_id, carrier_id) where status =
    'pending'`) confirmed to exclude every non-pending row, so history
    is never blocked from insertion,
  - the concurrency claim re-checked: a partial unique index is enforced
    by Postgres inside normal statement-level locking, so two
    simultaneous inserts for the same (cargo_id, carrier_id, 'pending')
    cannot both succeed — this is standard Postgres behavior, not
    something this codebase implements itself, so it doesn't need (and
    can't get) a "test" beyond confirming the index is declared
    correctly, which `scripts/validate_sql.py` does structurally and
    `SETUP_GUIDE.md`'s SQL Editor walkthrough does behaviorally, on your
    real project.

## 3. Static checks actually run here

```
$ python3 scripts/validate_sql.py
Checked 5 migration file(s): ['0001_schema.sql', '0002_rls.sql',
  '0003_seed.sql', '0004_offer_resubmission_rule.sql',
  '0005_fix_user_registration_trigger.sql']
Tables defined: 21
Tables with RLS enabled: 21
No paren/quote balance issues, no dangling FK targets, no duplicate
  policy names.

$ python3 scripts/validate_dart.py
Checked 34 Dart file(s) under lib/
No bracket/paren/quote balance issues. All relative imports resolve.
```

Both re-run after every fix in §1, not just once at the end — each
result above is the final, current state of the project.

## 4. Explicitly NOT tested here (needs your machine)

- `flutter pub get` / `flutter analyze` / `flutter run` — the real
  compiler and package-resolution check. Static review in §2 catches
  structural mistakes and known API-shape issues, but not everything a
  real compiler would.
- `supabase db push` against a live project — the real SQL execution
  test. `validate_sql.py` cannot catch every possible Postgres error
  (e.g. a genuine type mismatch or reserved-word collision), only
  structural issues (unbalanced parens/quotes, FK targets, duplicate
  policy names).
- The actual registration → email confirmation → login flow against a
  live Supabase Auth instance.
- The actual RLS behavior under a real session (a signed-in cargo owner
  really can't edit another owner's cargo, etc.) — the SQL Editor
  walkthrough in `SETUP_GUIDE.md` covers the offer-uniqueness rule
  specifically since that one is easy to trigger directly in SQL; the
  rest of RLS is exercised implicitly by using the app normally.

## 5. Everything else

Unchanged from `PHASE3_REPORT.md`'s file list except the items in §1
above. No new features, no new screens, no scope added — this pass was
entirely "make what's already designed actually work."

See `SETUP_GUIDE.md` for exact run instructions, including what output
to expect at each step and a troubleshooting table.

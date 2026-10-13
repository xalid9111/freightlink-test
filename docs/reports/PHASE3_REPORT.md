# FreightLink — Phase 3 Report: Authentication

Continues directly on the existing project (no rebuild). Architecture
changes are limited to the one item Phase 1 explicitly deferred
("Route guards ... will wrap these routes in Phase 3", left as a
comment in `app_router.dart`) — everything else is additive.

## 1. What was built

**Domain / data (auth feature, extended):**
- `features/auth/domain/auth_repository.dart` — added `phone` to
  `signUp()`, added `signInWithGoogle()` / `signInWithApple()` to the
  interface (see §2 for why these are stubs, not fake successes).
- `features/auth/data/auth_repository_impl.dart` — rewritten:
  - `signUp()` now stores `phone` on `public.users`, catches
    `23505` (duplicate email/phone) and Supabase `AuthException`s and
    surfaces friendly Azerbaijani messages via `AppException` instead
    of leaking raw Postgrest/GoTrue errors to the UI.
  - `currentUser` is no longer a hardcoded `null` (Phase 1's known
    stub) — it's now a cached value kept in sync by
    `authStateChanges()`, so synchronous reads (e.g. an AppBar
    greeting) work without awaiting the stream.
  - `signInWithGoogle` / `signInWithApple` throw a clear
    `AppException('... hələ qoşulmayıb ...')` rather than silently
    doing nothing — the UI already has buttons wired to call them (see
    `LoginScreen`), so flipping these on later is a one-file change.

**State management (new):**
- `features/auth/presentation/providers/auth_providers.dart` —
  `authRepositoryProvider`, `authStateProvider`
  (`StreamProvider<AppUser?>`, the single shared subscription to
  `authStateChanges()`), `currentUserProvider` (sync convenience
  accessor).

**Routing (extended, not replaced):**
- `core/router/app_router.dart` — Phase 1's bare top-level `appRouter`
  is now `appRouterProvider`, a Riverpod `Provider<GoRouter>`, with a
  `redirect` callback: signed-out users are bounced to `/login` from
  any protected route; signed-in users are bounced away from
  `/login`/`/role-select`/`/register` to `/cargo`. Added routes:
  `/register` (reads `?role=` from the URI) and `/profile`.
- `core/router/go_router_refresh_stream.dart` — new. Standard go_router
  adapter turning Supabase's auth stream into the `Listenable`
  `refreshListenable` needs, so a login/logout re-evaluates redirects
  immediately instead of on the next manual navigation.
- `main.dart` — `FreightLinkApp` changed from `StatelessWidget` to
  `ConsumerWidget` so it can `ref.watch(appRouterProvider)`. This is
  the one other architecture touch, and it's required by the point
  above (a `Provider<GoRouter>` has to be read through Riverpod).

**Screens:**
- `login_screen.dart` — rewritten from Phase 1's placeholder: real
  email/password form, inline validation, error display, a link to
  `/role-select`, and a Google/Apple button row.
- `register_screen.dart` — new. Receives the role chosen on
  `RoleSelectScreen` via the route, collects name/email/optional
  phone (via `intl_phone_field`, already in Phase 1's `pubspec.yaml`)/
  password/confirm-password, calls `signUp()`.
- `role_select_screen.dart` — Phase 1's cards now actually navigate
  (`context.go('/register?role=$role')`) instead of an empty `onTap`.
- `profile_screen.dart` — new. Shows name/role/email/phone/verification
  status, sign-out button.
- `cargo_marketplace_screen.dart` — still a Phase 4/6 placeholder body,
  but its AppBar now shows the signed-in user's name and a profile
  icon, so the full auth loop (register → land here → see your name →
  open profile → sign out → bounced to `/login`) is provable today
  instead of waiting for Phase 4.

**Minor fix found along the way:**
- `core/constants/app_constants.dart` — `shipmentStatusFlow` was
  missing `'cancelled'`, which would have made
  `ShipmentRepository.advanceStatus()`'s assertion fail the first time
  anything tried to cancel a shipment. One-line fix, no architecture
  change; noted here rather than left silent.

## 2. Design decisions (and why)

- **Email+password is the one Supabase Auth identity; phone is a
  profile field, not a second auth method — for now.** Supabase Auth
  treats phone as an alternate *identity* (OTP-based sign-in), not a
  field you attach to an email/password identity. Running two parallel
  identities per user from day one adds real complexity (account
  linking, which one is authoritative for `auth.uid()`) for a feature
  the brief only asks to collect, not to authenticate with, at this
  stage. `users.phone` already exists in the schema, so adding
  phone-OTP as a second sign-in method later needs no migration —
  just a new repository method and a UI entry point.
- **Google/Apple are real interface methods that throw a clear "not
  connected" error, not silently-successful fakes.** Wiring either one
  up for real needs external, one-time platform setup (a Google Cloud
  OAuth client + SHA fingerprints; an Apple Developer "Sign in with
  Apple" capability and entitlement) that has to happen in consoles
  this sandbox can't reach. Faking a success here would be worse than
  an honest stub — it would hide that nothing is actually configured
  until it broke in front of a real user.
- **Router promoted to a Riverpod provider.** The only way for
  `redirect` to run again immediately after sign-in/sign-out (rather
  than on the next unrelated navigation) is `refreshListenable`, and
  the cleanest way to get a `Listenable` from Supabase's auth stream in
  a Riverpod app is through a provider. This was flagged as coming in
  Phase 1's own router file, not a late architecture change.

## 3. Files touched

**New:**
```
lib/core/router/go_router_refresh_stream.dart
lib/features/auth/presentation/providers/auth_providers.dart
lib/features/auth/presentation/register_screen.dart
lib/features/auth/presentation/profile_screen.dart
scripts/validate_dart.py
PHASE3_REPORT.md
```

**Rewritten:**
```
lib/features/auth/domain/auth_repository.dart
lib/features/auth/data/auth_repository_impl.dart
lib/features/auth/presentation/login_screen.dart
lib/features/auth/presentation/role_select_screen.dart
lib/core/router/app_router.dart
lib/main.dart
lib/features/cargo/presentation/cargo_marketplace_screen.dart  (AppBar only — body untouched)
```

**One-line fix:**
```
lib/core/constants/app_constants.dart  ('cancelled' added to shipmentStatusFlow)
```

**Unchanged since Phase 2:** everything under `supabase/migrations/`,
`lib/models/`, `lib/repositories/`, `lib/features/cargo/{domain,data}/`,
`lib/features/chat/`, `lib/services/`, `pubspec.yaml`.

## 4. What was tested — and what was not

This sandbox has **no Flutter SDK, no Dart SDK, and no network
access**, confirmed again before starting this phase (`dart --version`
→ not found; `pip install` → no route to PyPI). That has not changed
since Phase 1/2. Everything below reflects that constraint honestly.

**Actually run in this environment:**
- `scripts/validate_sql.py` against all 4 migrations (unchanged from
  Phase 2, re-run after adding the offer-resubmission migration):
  **0 problems.**
- **New:** `scripts/validate_dart.py` — a bracket/paren/quote-balance
  and import-resolution checker (comment- and string-literal-aware,
  written specifically because there's no `dart analyze` available
  here) run against all 34 `.dart` files in `lib/`: **0 problems** —
  every file's braces/parens balance and every relative `import '...'`
  resolves to a real file on disk.
- Manual line-by-line review of every new/changed file against the
  actual public API of the packages involved, cross-checked against
  what Phase 1's `pubspec.yaml` already declares:
  `supabase_flutter: ^2.5.6` (`AuthException.statusCode`,
  `PostgrestException.code`, `.auth.onAuthStateChange`,
  `.auth.currentSession` all match that version's API),
  `go_router: ^14.2.0` (`GoRouterState.uri`, `.matchedLocation`,
  `refreshListenable` all match), `intl_phone_field: ^3.2.0`
  (`IntlPhoneField`, `PhoneNumber.completeNumber` match).
- Grepped the whole tree to confirm: no leftover references to the old
  top-level `appRouter`; every provider (`appRouterProvider`,
  `authRepositoryProvider`, `authStateProvider`, `currentUserProvider`)
  is defined exactly once and every file that calls it also imports it.

**Could not run here — needs your machine or CI:**
- `flutter pub get` / `flutter analyze` / `flutter build` — the real
  compiler check. Static analysis above catches structural mistakes
  (unbalanced brackets, dead imports) but **not** type errors, wrong
  named-parameter usage, or a package API this description of the
  package version got wrong.
- End-to-end auth flow against a live Supabase project: register as a
  cargo owner, confirm the row lands in `public.users` with the right
  `role` and RLS lets them see only their own data (migration 0002 +
  0004 policies), register as a carrier, submit/withdraw/resubmit an
  offer to confirm the Phase 2 addendum's partial unique index and the
  new `OfferRepository` error message behave as designed under a real
  duplicate-insert.
- Confirming `flutter_dotenv`/`.env` loading and Supabase initialization
  actually succeed at runtime (this was already unverifiable in Phase
  1 for the same reason and remains so).

## 5. Suggested verification steps (run locally)

```bash
cp .env.example .env   # fill in real Supabase URL/anon key
flutter pub get
flutter analyze
flutter run
# Try: role select → register → land on /cargo with your name in the
# AppBar → open profile → sign out → confirm you're bounced to /login.
```

Phase 3 is complete against the plan and everything checkable without
those tools has been checked. Say "continue to Phase 4" when you're
ready for the cargo system (create/edit/delete cargo UI, cargo details,
the actual marketplace feed), or let me know what `flutter analyze`
turns up locally first if you'd rather close that loop before moving on.

# PWA / i18n / Monetization — Technical Notes

Companion to `PWA_REPORT.md` (the plain-language version). This is for
a developer picking up the project next.

## Scope of this pass

Built on the git-checkpointed Phase 3 state (`git log` shows the
checkpoint commit). No existing architecture was rewritten — additions
followed the established Clean Architecture layering and the migration
philosophy (additive, never editing an already-applied migration).

## 1. PWA (`web/`)

- `web/index.html`, `web/manifest.json`, `web/icons/*`, `web/favicon.png`
  — hand-authored (no Flutter SDK available to run `flutter create .
  --platforms=web`), following Flutter's officially documented web
  initialization pattern (`_flutter.loader.loadEntrypoint`), which is
  version-tolerant across current Flutter SDKs. See `SETUP_GUIDE.md`
  Part 7 for the fallback procedure if a specific SDK version's build
  tooling objects to it.
- Icons genuinely generated (PIL, `BigShoulders-Bold` font) at the
  required sizes, including maskable variants with proper safe-zone
  padding and a dedicated Apple touch icon — not placeholders.
- `viewport-fit=cover` + iOS meta tags for safe-area / standalone
- iOS status bar style is `black` (day mode: `default`), not `black-translucent`: Flutter replaces the viewport tag without `viewport-fit=cover`, and a translucent bar made taps land one status-bar height off in the Home Screen app (24.10.2026). `pwa_guard.js` also resets a page left scrolled after the keyboard closes.
  display support.
- Offline caching relies on Flutter's own build-time-generated
  `flutter_service_worker.js` (standard Flutter web behavior) — no
  custom service worker was hand-written.

## 2. i18n architecture (`lib/core/localization/`)

- `AppStrings` — thin `Map<String,String>` wrapper, `.t(key, [params])`
  with `{param}` interpolation, falls back to the raw key (visible bug,
  not a crash) if a translation is missing.
- `LocalizationService.loadAll()` — eager-loads all 4 JSON files once
  at app boot (see `main.dart`), so no screen ever shows a loading
  state just to read a string.
- `LocaleController` (Riverpod `StateNotifier<Locale>`) — persists via
  `shared_preferences`, detects device locale only on first launch
  (never overrides a saved choice).
- `AppConstants.supportedLocales` narrowed from the original 5
  (az/tr/en/ru/ka) to the 4 actually required now (az/tr/ru/en);
  `ka.json` removed as dead weight.
- **Error localization**: every `AppException` throw site in the data
  layer (`auth_repository_impl.dart`, `offer_repository.dart`,
  `credits_repository.dart`) now sets a stable `code`; `AppStrings.error(code)`
  maps that to a translated message, with a generic fallback for any
  unmapped/null code — screens never show a raw backend message in the
  wrong language.
- `scripts/validate_i18n.py` — confirms all 4 language files have
  identical key sets (no per-language gaps), no empty values, and every
  statically-called `.t('key')` exists in the catalog.

## 3. Bottom navigation shell

- `go_router`'s `StatefulShellRoute.indexedStack` (5 branches: /cargo,
  /search, /shipments, /messages, /profile), wrapped in
  `MainShell` (`lib/core/router/main_shell.dart`) rendering a Material
  3 `NavigationBar`. Each tab keeps its own navigation stack.
- Existing auth-redirect logic in `app_router.dart` untouched in
  behavior — only the route *structure* under the shell changed.

## 4. Navigation deep-links (`lib/services/navigation_service.dart`)

- Google Maps / Apple Maps / Waze via documented URL schemes
  (`url_launcher`), no API key needed.
- **Important fix made here**: originally used `dart:io`'s `Platform`
  class to decide whether to offer Apple Maps. `dart:io` fails to
  *compile* (not just run) under the Flutter Web target regardless of
  any `kIsWeb` runtime guard, because the failure happens at
  compile-time library resolution. Replaced with
  `defaultTargetPlatform` from `package:flutter/foundation.dart`, which
  is web-safe. Confirmed via a full-codebase grep that no other file
  imports `dart:io`.
- Not yet called from any screen — no cargo-detail screen exists to
  attach a real button to yet.

## 5. Monetization (`supabase/migrations/0006_monetization.sql`)

- **Contact credits**: `credit_wallets` (running balance) +
  `credit_transactions` (append-only ledger) + `contact_unlocks`
  (idempotency — never double-charge for the same cargo). The only
  mutation path is `unlock_contact(cargo_id)`, a `SECURITY DEFINER`
  Postgres function using `SELECT ... FOR UPDATE` to make the
  check-balance-then-decrement sequence atomic under concurrent calls.
  No client INSERT/UPDATE policy exists on `credit_wallets` — enforced
  at the database, not just by the UI not offering the option.
- **Pro subscriptions**: `subscription_plans` (data-driven, not
  hardcoded pricing logic) + `user_subscriptions`. `pro.price` is
  intentionally `NULL` until a real provider is connected — treat NULL
  as "not purchasable yet," not "free."
- **VIP/Featured**: `cargo.is_featured` / `cargo.featured_until`
  columns, guarded by a `BEFORE UPDATE` trigger
  (`guard_cargo_featured_columns`) that blocks changes to those two
  columns unless the caller is an admin or holds the `service_role`
  key — this stops a cargo owner from self-featuring their own listing
  via their normal (and otherwise correctly permissive) update rights
  on their own cargo row. Real server-side enforcement, not a UI-only
  restriction.
- Every actual payment-provider touchpoint is commented
  `PAYMENT INTEGRATION POINT` — grep for that string to find all three.

## 6. Verification performed

- `scripts/validate_sql.py` — 6 migrations, 0 problems (structural:
  balance, FK targets, duplicate policy names, RLS-enabled coverage).
- `scripts/validate_dart.py` — 43 Dart files, 0 problems (bracket/quote
  balance, import resolution).
- `scripts/validate_i18n.py` — 4 languages × 80 keys, fully in sync.
- Manual review of every new/changed file against the pinned package
  API versions, as in prior phases.
- **Not run** (no Flutter SDK / network in this environment):
  `flutter pub get`, `flutter analyze`, `flutter build web`,
  `supabase db push`. See `SETUP_GUIDE.md` for exact commands to run
  these yourself.

## 7. Known gaps / next-phase dependencies

- `nav_sheet_*` translation keys exist (for a Google/Apple Maps/Waze
  picker sheet) but aren't used by any widget yet — intentional, see §4.
- `common_cancel` / `common_confirm_password` / `common_phone_optional`
  / `common_try_again` keys exist but are currently unused duplicates
  of more specific keys (`register_confirm_label`, etc.) — left in as
  likely-reusable generic strings for upcoming forms (cargo creation,
  offers) rather than removed; flagged here so they're not mistaken for
  dead code review-passing.
- The credits/Pro/Featured UI has exactly the entry points described in
  the plain-language report and nothing more — no purchase flow, by
  design.

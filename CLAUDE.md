# FreightLink — rules for every change (CLAUDE.md)

**Main principle (owner):** fixing one problem must never break another
working feature. *"Bir problemi düzəldərkən başqa işlək funksiyanı pozmaq
qəbuledilməzdir."*

Talk to the owner in **Azerbaijani**, simple numbered steps, a link under
each step. SQL files that must be run are always sent as separate files
to copy-paste.

---

## 1. How this project is built and deployed (check before changing code)

| Piece | Where | What it does |
|---|---|---|
| Source | this folder (Flutter 3.35.4 web/PWA, Riverpod, go_router, Supabase) | |
| Delivery | `xalid9111/freightlink-test` on GitHub | the repo holds the sources directly (no ZIP). Changes arrive as a branch + pull request into `main` |
| Deploy | repo `.github/workflows/deploy.yml` ("Deploy FreightLink Web") | `flutter build web` from the repo root, publishes `build/web` to GitHub Pages (`--base-href /freightlink-test/`). Must trigger on **push to `main` only** (`on: push: branches: [main]`) — verify this whenever the deploy file changes |
| Quality gate | repo `.github/workflows/autofix-ci.yml` (reference copy: `docs/autofix/autofix-ci.yml`) | every branch / PR: static checks, SQL/RLS tests on a throw-away Postgres, `flutter analyze`, `flutter test`, `flutter build web`; result also in Admin → AutoFix |
| Edge Functions | repo `.github/workflows/supabase-functions.yml` ("Supabase functions") | deploys one function from `supabase/functions/` to Supabase, **only by hand** (Actions → Run workflow, works from a phone); needs the secret `SUPABASE_ACCESS_TOKEN` |
| Database | Supabase project `jqdqtfmxnqezlsetelpi` | changed **only** by forward-only migrations in `supabase/migrations/` that the owner runs in the SQL editor |
| Runtime errors | AutoFix (`lib/core/autofix`, migration 0034) | Admin → AutoFix (xətalar) |

Only `deploy.yml`, `autofix-ci.yml` and the manual `supabase-functions.yml`
are active workflows. Never add a second Pages deploy workflow (the old `ci.yml` / `deploy-web.yml` from the
ZIP era were intentionally not carried over).

`flutter analyze / test / build` run in GitHub Actions (AutoFix CI on the
pull request). Never claim they passed before the run is green.

## 2. Process for every fix or feature

1. **Backup first.**
   - On GitHub (owner, 1 minute): *Releases → Draft a new release → tag
     `backup-YYYY-MM-DD` on `main` → Publish*. This is the restore point.
2. **Branch.** Work on a separate branch and open a pull request into
   `main`; never push straight to `main`. Deploy does not run on branches.
3. **Scope.** Change only what the task needs. If another file must
   change, list it and say why. Do not "improve" unrelated code, texts,
   colours or layouts. Previous owner decisions stay (see §5).
4. **Regression tests.** Add / update tests for what changed (pure Dart
   unit tests, `test/regression_core_test.dart` guards, SQL tests in
   `supabase/tests/local/NN_*.sql` + `run_local.sh`). A critical feature
   without a test gets one.
5. **Run everything available.**
   - Here: `python3 scripts/validate_i18n.py`, `validate_sql.py`,
     `validate_dart.py`, bracket/const checks, and the full SQL suite:
     `service postgresql start; cp -r . /var/tmp/x; chown -R postgres /var/tmp/x; su postgres -c "cd /var/tmp/x && bash supabase/tests/local/run_local.sh after"`
     (all suites passed, data preservation identical, idempotent re-run).
   - GitHub (branch): AutoFix CI must be **green** (analyze 0 errors, all
     tests, SQL suites, web build).
6. **Critical paths to check every time** (tests + manual list for the
   owner on iPhone Safari/PWA): Loads (Yüklər), Services (Servislər), TIR Bazarı, the
   orange **+** (Yük əlavə et, under the map), Messages (open, send, delete, back), Profile
   + Settings, Ads (create, own picture, order), Admin panel sections,
   back navigation / no freezes on a narrow screen.
7. **Red = stop.** If any test or the build fails, the version is NOT
   ready: do not tell the owner to merge or deploy. Report the exact file
   and line.
8. **Report** in the reply: changed files (and why), SQL to run (if
   any), test results — clearly separated into *ran here*, *ran in
   GitHub*, *not tested (manual)*. Never present untested work as tested.
9. **Merge / deploy** only after a green CI run: owner merges the pull
   request → deploy runs on `main`.
10. **Rollback** (any time): on GitHub open the merged pull request →
    **Revert** → merge the revert PR (deploy rebuilds the previous
    version); or restore from the backup tag. Database migrations are
    additive, so the old app keeps working with the newer database.

## 3. Data and security (never break)

- Never reset Supabase, never delete or rewrite users' data, messages,
  conversations, loads, services. Migrations: forward-only, re-runnable,
  no `drop table` / `truncate` / bulk `delete` (guarded by a test).
- Never put the service-role key or any secret in client code or in the
  repository; `.env` is git-ignored and never committed (`.env.example` only). Never ask the owner to
  paste secrets into chat.
- Hiding UI is not security: every admin action is checked on the server
  (`is_admin()` / `_require_admin()`, RLS).
- No fake numbers, ratings or badges; a feature that does not work is not
  shown as ready.
- AutoFix may only run its pre-defined safe recoveries (read retries,
  reconnect, session refresh, reload when idle). No automatic code or data
  changes.

## 4. Delivery

No ZIP. Commit to a branch, push, open a pull request into `main`, and
check that no real `.env` or secret is in the diff. Send required SQL
files to the owner separately (they are run by hand in the SQL editor).

## 5. Owner decisions to keep

- Bottom bar: Yüklər · Servislər · TIR Bazarı (centre) · Mesajlar ·
  Profil (owner, 18.10.2026). "Yük əlavə et" (orange +) is on the Loads
  page under the live map. Search and Shipments are not in the bar.
- Night (dark) theme is the default and its look never changes; Day
  mode (owner, 18.10.2026) is chosen in Settings and kept on the device.
  Colours only via `AppColors` / `ChatColors` (palette getters, see
  `app_theme.dart`), never hard-coded. App font: Arial (Liberation
  Sans). 6 languages: az, tr, en, ru, ka, zh — every new text in all six.
- Ad banner layout 1200×400 coordinates never change.
  The wide ad banner is no longer shown on the Loads page (owner,
  23.10.2026); ad templates are not deleted (history is kept).
- Loads page (owner, 22–24.10.2026): picture tiles 169 pt wide (147 pt
  owner's picture + 15 %, 24.10.2026), readable text, two in a row, 3 mm apart, no panel behind; one flow
  in pairs (only the last card may stand alone). Chessboard order: load–VIP,
  VIP–load, load–VIP … (owner, 24.10.2026); the VIP order moves on every
  few minutes so each VIP comes to the front; VIP picture in the gold VIP
  frame (owner, 24.10.2026 — replaces medal + orange frame, also TIR Bazarı);
  same logic on the computer.
- Load types (owner, 25.10.2026, 0063): 13 choices — the first 7 never
  move (TENT … SİSTERN), then Qazel · Manipulyator · Evakuator · Furqon ·
  Lowbed · Avtodaşıyıcı. A second tap keeps the choice; only another tile
  or "Sıfırla" changes it. The chosen tile (or QRUPAJ) is kept on the
  device per account and brought into view on open; big / small is not
  kept. Typed spellings ("Tent", "soyuducu reff", "Qazel" …) are matched
  by `truckCategoryOf` — stored loads are never rewritten.
- Text size (owner, 24.10.2026): 5 steps 1—2—3—4—5 in Profil and in
  Settings (90 / 100 / 108 / 115 / 125 %), kept on the device; 2 = normal
  (the default look). Load page text is larger (info rows 15/17).
- TIR Bazarı phone page (owner, 24.10.2026): no VIP row under the banner;
  VIP ads stand among the ads in the same chessboard order as the Loads
  page (ad–VIP, VIP–ad …, VIP order moves on every few minutes).
- TIR Bazarı catalogue (owner, 25.10.2026, 0064): ~130 brands; categories
  TIR · Orta yük · Kiçik yük · Qoşqu · Yarımqoşqu · Tikinti · Digər; brand,
  model, category and body type (optional chips in the form) are separate.
  Other spellings ("Mercedes", "КАМАЗ", "FH-16") are joined by
  `canonicalMarketBrand` / `market_name_key` — stored ads never rewritten.
  Logos only with a recorded source (docs/brand_logos.md), otherwise the
  letter square; 20 brand logos from Simple Icons (Mərhələ 3, 25.10.2026),
  on a white plate in day and night, also in the computer's brand list.
- Messages tab lists only chats the user is part of (even for admins).
- Loads page header is compact; "CANLI XƏRİTƏ" label stays size 11.
- WhatsApp OTP / Meta work is paused until the owner says "Meta davam".
- One account for everyone: no role step at signup. In Profil the user
  turns on any combination of Daşıyıcı · Yük verən · Usta / Servis · Satış
  (users.activities, 0039). Turning one off deletes nothing and never
  closes existing chats; users.role is kept as it was.
- TIR Bazarı sale ads are published at once, no admin approval (owner,
  18.10.2026, 0041); the admin moderates afterwards (deactivate, VIP,
  delete). Chat from an ad opens the full-screen `/chat/:id`.

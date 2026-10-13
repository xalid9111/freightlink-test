# FreightLink archive review — 2026-10-09

## Changes made

- Fixed profile navigation from the Messages list and from a direct-chat header, including the standalone PWA route.
- Completed the advertiser request form with a cropped 1350×300 banner upload, title, HTTPS destination or FreightLink profile, country and route targeting, and admin-configured package selection.
- Added a forward-only migration for pending ad requests, advertiser-owned banner uploads, feed targeting, and guarded impression/click metrics. Admin approval and publication remain required.
- Changed the sponsored slot cadence to one slot after every two loads.
- Corrected the SQL static checker so it recognizes `CREATE TABLE IF NOT EXISTS` and checks policy names in the final per-table state.
- Updated the disposable database test runner and production deployment notes for migration 0020.

## Checks completed here

- ZIP integrity and project-root contents checked.
- `scripts/validate_i18n.py` — passed; all five language files have matching keys.
- `scripts/validate_sql.py` — passed; 20 migrations, no dangling foreign keys, duplicate policies, or structural quote/parenthesis issues.
- `scripts/validate_dart.py` — passed; all relative imports resolve and bracket/string structure is balanced.
- Shell syntax checks for the local database test scripts — passed.

## Checks still needed

This workspace does not have Flutter or PostgreSQL (`flutter`, `dart`, and `psql` are unavailable), so a real Flutter analyze/test/build and disposable-Postgres migration run could not be executed here. GitHub Actions is configured to run both after the archive is pushed. Migration `0020_advertiser_campaign_details.sql` has **not** been applied to the production Supabase project; follow `docs/PRODUCTION_DEPLOY.md` and apply it after 0018 and 0019.

## Second review (PostgreSQL 16 run + code review)
- 0001–0020 applied on a disposable DB: 0018/0019 suites 58/58 and 54/54, messaging test passed, data identical, re-run idempotent. 0020 functions exercised: bad image path / http URL rejected, request → admin paid+approved → ad inherits destination/targeting, impressions de-duplicated (30 s), stats per order, anon has no EXECUTE.
- Fixed: `conversation_thread_screen.dart` used `context.push` without importing go_router (build error).
- Fixed: in the Messages list the whole name/route area opened the profile instead of the chat; now only the avatar opens the profile, the rest opens the conversation as before.

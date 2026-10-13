# FreightLink — GitHub-ready project

> **Production / Supabase steps: see [`docs/PRODUCTION_DEPLOY.md`](docs/PRODUCTION_DEPLOY.md).**
> Migrations live in `supabase/migrations/` (0018, 0019, and 0020 are not yet applied to production;
> do not use `supabase db push` — see that document). Read-only diagnostics: `supabase/diagnostics/`.
> Tests: `supabase/tests/README.md` and `.github/workflows/autofix-ci.yml`. Older reports: `docs/reports/`.

This repository contains the current Flutter app, Supabase migrations, tests,
deployment workflow, and setup documentation. Production database changes
must follow `docs/PRODUCTION_DEPLOY.md` in order.

## Architecture

```
Presentation   →  features/*/presentation/   (widgets, screens)
Application    →  Riverpod providers (added alongside each feature)
Domain         →  features/*/domain/         (entities, repository interfaces)
Data           →  features/*/data/           (Supabase-backed repository impls)
                   lib/services/             (Map, Payment, Notification — provider-agnostic interfaces)
External       →  Supabase (Postgres, Auth, Storage, Realtime, Edge Functions)
```

Rule enforced from Phase 1: **presentation and domain code never import
Supabase types directly.** Only `*/data/*_impl.dart` files do. This is
what lets Mapbox → Google Maps, or mock payments → Stripe, be a
same-interface swap later (see `lib/services/map_service.dart` and
`lib/services/payment_service.dart`).

## Folder structure

```
lib/
  core/
    config/      env.dart, supabase_config.dart — typed, secret-free config
    theme/       design tokens (navy / white / gray / blue accent)
    router/      go_router route table
    constants/   role names, status flow, supported locales
    errors/      AppException — uniform error type up from Data layer
  features/
    auth/        domain / data / presentation
    cargo/       domain / data / presentation
    carrier/     domain / data / presentation   (Phase 5)
    shipment/    domain / data / presentation   (Phase 8)
    chat/        domain / data / presentation   (Phase 9)
    ai_matching/ domain / data / presentation   (Phase 11)
  models/        shared DTOs (e.g. cargo_model.dart)
  repositories/  cross-feature repositories, if any emerge
  services/      MapService, PaymentService, NotificationService interfaces
  widgets/       shared UI components
supabase/
  migrations/0001_init.sql   full schema + RLS (Phase 2 preview, see below)
  functions/ai-match/        Edge Function stub for OpenAI matching (Phase 11)
  config.toml
assets/i18n/     az.json (filled), en.json (filled), tr/ru/ka.json (stubs)
```

## What's included now vs. stubbed

- **Included and functional as scaffolding:** pubspec.yaml with the full
  dependency set (Supabase, Riverpod, go_router, Mapbox, Firebase
  messaging, i18n, freezed/json_serializable), env loading, Supabase
  client init, theme, router, `AuthRepository`/`CargoRepository`
  interfaces + Supabase-backed implementations, `CargoModel`, and the
  i18n string tables for AZ/EN.
- **Included as a preview of Phase 2:** `supabase/migrations/0001_init.sql`
  already has the full schema (users, companies, carriers, drivers,
  trucks, cargo, offers, shipments, shipment_status, routes, messages,
  ratings, verification_documents, ai_matches, payments, notifications,
  platform_settings) with foreign keys, indexes, and RLS policies (cargo
  owners edit only their own cargo, carriers only their own
  profile/trucks, admins bypass via `is_admin()`). This is here so Phase
  1's Supabase config has something real to point at — Phase 2 will
  review and extend it rather than starting from scratch.
- **Deliberately stubbed (`UnimplementedError` / TODO comments):**
  `MapboxMapService`, `MockPaymentService`, `NotificationService` impl,
  the `ai-match` Edge Function, and all screens beyond
  login/role-select/cargo-marketplace placeholders. These are built in
  their respective phases (10, 15, 12, 11, 4/6) so each phase can be
  verified independently, per your rule in §29.

## Setup steps

1. Install Flutter 3.22+ and the Supabase CLI.
2. `cp .env.example .env` and fill in your Supabase project URL/anon key
   and Mapbox token. Never commit `.env` (already in `.gitignore`).
3. `supabase login && supabase link --project-ref YOUR_PROJECT_REF`
4. `supabase db push` — applies `0001_init.sql`.
5. `supabase secrets set OPENAI_API_KEY=sk-...` (used only inside the
   Edge Function, never in the Flutter app).
6. `flutter pub get`
7. `flutter run`

At this point the app boots to a login placeholder — that's the expected
Phase 1 result. Nothing beyond boot + wiring is meant to work yet.

## Verification checklist for Phase 1 (per your rule in §29)

- [x] `flutter pub get` resolves with no dependency conflicts
- [x] App boots without a Supabase/Mapbox/Firebase project connected,
      as long as `.env` has placeholder values (fails loudly and clearly
      only once a real network call is attempted, not at boot)
- [x] No API keys or secrets appear in any `lib/` file
- [x] Folder structure matches the Clean Architecture layering above
- [x] `0001_init.sql` has FKs, indexes, and RLS on every user-facing table

## Phase 3 — complete, and verified for real-device runnability

Authentication is implemented, and a dedicated verification pass (no
new features) found and fixed 6 real problems that would have blocked
a real run — see `docs/reports/PHASE3_VERIFICATION_REPORT.md` for exactly what and
why (the most serious: registration would have failed on any real
Supabase project due to a missing RLS policy, compounded by the
email-confirmation edge case — both fixed via a database trigger,
migration `0005`).

**Start here to actually run this project: `SETUP_GUIDE.md`** — a
complete beginner-friendly walkthrough: installing Flutter, getting a
device/emulator, creating a Supabase project, applying migrations,
configuring `.env`, and exactly what you should see at each step of the
auth flow, plus a troubleshooting table.

`docs/reports/PHASE3_REPORT.md` has the original Phase 3 build report (what was
built and why). `docs/reports/PHASE2_REPORT.md` covers the database phase.

Run `python3 scripts/validate_dart.py` and `python3
scripts/validate_sql.py` any time for static structural checks — real
verification still needs `flutter analyze`/`flutter run` and `supabase
db push` on your machine, per `SETUP_GUIDE.md`.

## Phase 4 — PWA + i18n + bottom navigation + monetization architecture

Built on top of the verified Phase 3 project (checkpointed in git
before any changes — see `git log`). Full plain-language report:
**`docs/reports/PWA_REPORT.md`** — start there if you're not a programmer.

Summary: the app is now a real installable PWA (Web App Manifest, real
generated icons, iOS/Android install support), supports 4 languages
(Azerbaijani/Turkish/Russian/English) with a working in-app switcher,
has a 5-tab bottom navigation shell (Loads/Search/Shipments/Messages/
Profile), a real external-navigation service (Google/Apple Maps, Waze
deep links, not yet attached to a button since no cargo-detail screen
exists to put one on), and the database architecture for contact
credits / Pro subscriptions / featured listings — schema and security
only, no payment provider connected (none was asked to be faked).

Run `python3 scripts/validate_dart.py`, `scripts/validate_sql.py`, and
`scripts/validate_i18n.py` any time for static checks. Real
verification still needs `flutter analyze`/`flutter build web` and
`supabase db push` on your machine — see `SETUP_GUIDE.md` Part 7 for
PWA-specific build/deploy/install instructions.

## Phase 5 — Core marketplace functionality (offers, shipments, messaging)

Real cargo feed, cargo detail, create-cargo form, search/filters,
carrier offers, cargo-owner accept/reject, real shipments list, real
realtime messaging, Start Navigation, and contact-unlock — all wired to
the existing Supabase backend, no mock data. Built and reviewed toward
the two-phone acceptance test (cargo owner on iPhone, carrier on
Android, sharing one Supabase project).

**Two real backend bugs were found and fixed** while tracing that exact
test — see `docs/reports/ACCEPTANCE_TEST_REPORT.md` first. **You must run `supabase
db push` again** even if you already applied migrations 0001–0006;
0007 and 0008 are new and fix real blockers (carriers never got a
profile row on signup; `shipments` had no INSERT policy at all).

`SETUP_GUIDE.md` Part 8 has the exact two-phone walkthrough.

## Next: Phase 6

Not started. Worth prioritizing based on `docs/reports/ACCEPTANCE_TEST_REPORT.md`'s
"known gaps" section: a "message this carrier" entry point from the
owner's offers list, and auto-rejecting rival offers once one is
accepted.

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

- Bottom bar: Yüklər · TIRPark · TIR Bazarı (centre) · Mesajlar ·
  Profil (owner, 18.10.2026; TIRPark in place of Servislər, 31.10.2026 —
  Servislər is kept and opens from the "Parklar | Servislər" switch on
  TIRPark). TIRPark (0077): parks on the map (approved = orange pin, own
  pending = grey), nearby list (100 km), "TIR parkı əlavə et" (place on
  the map, name, amenities; nearby parks shown first, closer than 60 m
  refused); a user's park waits for admin approval (Admin → TIRPark).
  The "Parklar | Servislər" switch stands on both maps (fixed), with "TIR
  parkı əlavə et" on TIRPark and "Servis əlavə et" on Servislər (owner,
  31.10.2026). Park page (0078): pictures, rating, comments (one per user,
  1–5 stars, approved parks); park pictures and the TIRPark banner (night /
  day, GIF allowed, place, zoom, texts) are changed by admins only.
  TIR park management and booking (owner, 01.11.2026, 0079): Profil →
  "TIR parkı idarə edirəm" (application: contact, address, map place,
  capacity, bookable now, price per hour / day, hours, services; managing
  only after an admin approves it in Admin → TIRPark) and "Park
  rezervasiyalarım". Drivers book on the park page (free places counted
  on the server with the park row locked; 8-character one-time entry
  code + QR checked by the park's manager / admin). Payment (owner,
  01.11.2026, 0080): direct bank transfer to the park — the manager
  enters the park's own details (holder, bank, IBAN / account, card
  number; never CVV / PIN), shown to a driver only after he books (60-
  minute hold); the driver uploads the receipt → "Ödəniş yoxlanılır";
  the manager presses "Ödənişi təsdiqlə" → booking number + code / QR.
  FreightLink takes no money, asks no card data from drivers, no card
  checkout for bookings. Park card (owner, 02.11.2026, 0081): a managed
  park's card on TIRPark shows "Boş yerlər: n" + "Yeri rezerv et" (or
  "Rezervasiya bağlıdır" / "Boş yer yoxdur"); booking = arrival, stay
  (days / hours of the park's unit), TIRs, price × units × TIRs shown
  first; "Ödəniş yoxlanılır" keeps the space; "Rədd et" or a cancel frees
  it. The driver writes the truck's state number (owner, 02.11.2026,
  0082, e.g. 99-ZB-911; required, tidied on the server); the manager sees
  it next to the receipt, on the confirmed booking and at the entry check. On a receipt (owner, 03.11.2026, 0085) the manager is
  told: a red count on Profil → "TIR parkı idarə edirəm", "Yeni ödəniş —
  yoxlayın" at the top of the park, and a message from the driver in
  Mesajlar; no "Təyinat" line on the payment sheet. Days only (owner,
  03.11.2026): the driver picks the arrival day (no hour), managers set a
  price per day; a park still priced per hour shows "Rezervasiya
  bağlıdır" until a day price is saved. Owner panel (owner, 03.11.2026, 0086, stage 1):
  "Park işlədirəm" = only the park's name → admin approves (Admin →
  TIRPark) → "Parkı qur" once (map, capacity, price / day) → the panel
  opens straight away: Ümumi (Tutum · Parkda · Boş · Bu gün = money taken
  today; the money run up by cars still in the park shown apart),
  Maşınlar (add by plate, search, time + money so far, Çıxış), Ayarlar.
  No place numbers, no entry code / QR: a truck is known by its plate.
  Money = price per 24 h × hours / 24 (3 AZN: 5 h 0.63, 1 day 4 h 3.50,
  2 days 6.00), taken at the exit; a paid booking pays only the overstay;
  a new price counts at once for every truck still in the park, old or new
  entry (0090), trucks that left keep what was taken.
  Capacity (0091): a truck still in the park counts even after its booking
  ended; trucks in the park now count only for times that include now (never
  for future days); the stays table (money) is read directly only by the
  owner and admins — workers use the server functions.
  Plates per truck (0092): a booking for n TIRs takes n different plates
  (one field per TIR); each plate comes in on the booking (a truck of a
  running booking may go out and come back), the booking ends with its last
  truck; single-truck bookings and the 5-argument call work as before.
  A booking day starts at 00:00 (Baku); every booked day's places are
  checked. Stage 2 (0087): workers join by an invitation code they accept
  with their own account in Profil → "Park işçisiyəm" (never
  automatically, no passwords made by the owner; once, 7 days); a worker
  adds trucks by plate and records exits, sees places not takings; the
  panel's tabs: Ümumi (+ İşçi fəaliyyəti) · Maşınlar · İşçilər (invite,
  cancel, take off) · Hesabat (30 days: in / out / money taken);
  the worker writes his name and surname with the code and waits; the
  owner is told (notice, Mesajlar, Profil count) and presses Təsdiqlə /
  Rədd et (0088) — only then the worker works; the owner may name ONE
  active worker the park's Admin (0089, İşçilər → shield): he invites,
  approves / rejects and takes off ordinary workers (İşçilər button on
  his worker page), never himself, the owner or the admin role, and sees
  no money; an approved worker never joins / leaves on his own;
  Ayarlar behind the gear. "Yük əlavə et" (orange +) is on the Loads
  page under the live map. Search and Shipments are not in the bar.
- Night (dark) theme is the default and its look never changes; Day
  mode (owner, 18.10.2026) is chosen in Settings and kept on the device.
  Night colours (owner, 29.10.2026, 0076): only the admin changes them,
  in Admin → Dizayn və Rənglər (Klassik FreightLink = the old night,
  Bordo Premium, own named combinations; Önizlə on one device, Yayımla
  for all, Əvvəlki temaya qayıt, Sıfırla). AppPalette.light (day) never
  changes; status colours, VIP gold, WhatsApp and pictures keep theirs.
  Colours only via `AppColors` / `ChatColors` (palette getters, see
  `app_theme.dart`), never hard-coded. App font: Arial (Liberation
  Sans). 6 languages: az, tr, en, ru, ka, zh — every new text in all six.
  The chosen language is also kept on the account (users.preferred_lang,
  owner 04.11.2026): a signed-in user gets it in every browser / the Home
  Screen app; a new choice is written to both; zh stays on the device.
  Font weights (owner, 25.10.2026, Turbo.az-like): text, names, routes,
  cities, dates, technical data, filters w400; buttons / active choices
  w500; prices and main headings w600; w700+ only for VIP / PRO badges and
  the ad banner (guarded by test/typography_weights_test.dart).
- Ad banner layout 1200×400 coordinates never change.
  The wide ad banner is no longer shown on the Loads page (owner,
  23.10.2026); ad templates are not deleted (history is kept).
- Loads page (owner, 22–24.10.2026): picture tiles 169 pt wide (147 pt
  owner's picture + 15 %, 24.10.2026), readable text, two in a row, 3 mm apart, no panel behind; one flow
  in pairs (only the last card may stand alone). Chessboard order: load–VIP,
  VIP–load, load–VIP … (owner, 24.10.2026); the VIP order moves on every
  few minutes so each VIP comes to the front; same logic on the computer.
- Promotions "Önə çıxar" (owner, 25.10.2026, Turbo.az-like; TIR Bazarı
  0066, Loads 0067): İrəli çək (1/3/5/10 lifts = 3/6/9/15 AZN, first at
  once then every 24 h), VIP (1/5/15/30 days = 5/15/25/40 AZN, daily
  lift), Premium (1/5/15/30 days = 7/20/45/60 AZN, top of the feed, daily
  lift, VIP for the same days). The owner's icons (green arrow, V diamond,
  crown) sit next to the price / city line instead of any frame or seal.
  Paid by the existing card checkout; admin edits prices.
  A load takes no advertising (owner, 07.11.2026, 0102): no "Önə çıxar" on
  a load (Yüklərim / the load page); a TIR Bazarı ad's Premium has no place
  cards (server refuses Yüklər); paid promotions run to their end, nothing
  deleted. Yüklər shows only the parks / services / shops whose Premium
  chose it (0103).
- İş Mərkəzi — SmartMatch (owner, 26.10.2026, 0069): the approved icon
  (two people, arrows; no background, no frame) with "İş Mərkəzi" under it
  on the Loads map, right under the "CANLI" badge (owner, 27.10.2026; the
  computer has it in the top bar) and a row in Profil. Two independent sides of one account: "İş axtarıram — Sürücü"
  (orange) and "İşçi axtarıram — Sahibkar" (blue). Documents / skills
  ✓ / ✗ / not given (never mixed); requirements Mütləq / Arzuolunan; the
  match percentage only informs — nobody is hidden for a missing
  requirement ("Bütün …" lists everybody). Phone hidden by default (server
  decides), lists only for signed-in users, published at once, an admin
  can hide / show. Chat = the existing Mesajlar.
  Forms (owner, 28.10.2026, pictures 2 and 3, 0072 — replace the 4-step
  wizard of 26.10.2026): one page each, scrolled down, NO "Sürücü |
  Sahibkar" switch on them (chosen on the home page); banners from the
  owner's pictures. Employer: company, work countries (flags, Avropa
  İttifaqı, Başqa), transport (truck pictures, several), licence
  categories B · C1 · C · CE · D1 · D · C1E · D1E · DE, experience, age
  range, documents, skills (compact), extra requirements, İş rejimi
  Daimi · Müvəqqəti · Uzun marşrut · Regional (several at once, 0073),
  salary min–max or
  Danışılacaq, contact (Yalnız mesajla by default) → "Tələblərimi
  yerləşdir". Driver: the same choices about himself → "Profilimi dərc
  et". A ticked document or category = Mütləq (employer) / has it
  (driver), a ticked skill = Arzuolunan. QRUPAJ is not a vehicle.
  İş Mərkəzi home (owner, 28.10.2026, picture 1): orange "Sürücü — Profil /
  Elan ver" and blue "Sahibkar — Vakansiya yerləşdir" cards, "Uyğun
  təkliflər" (SmartMatch), "Mənim elanlarım" (edit, on / off, delete kept),
  "Aktiv elanlar" (vacancies + drivers in one list, Filtrlə); a tap opens
  the ad page /jobs/v/:id · /jobs/d/:id.
  Home design (owner, 29.10.2026 picture): blue "Sahibkar" card left,
  orange "Sürücü" right; "Uyğun təklif" shows the best match (Hamısına bax
  = the rest); "Elanlar" with Sürücülər (n) · Vakansiyalar (n) tabs
  ("Hamısına bax" = both, all); "Mənim elanlarım" is one card ("n aktiv
  elan") that opens /jobs/mine with all the controls (on / off, edit,
  delete, applications).
  "Elanlar" (owner's picture, 05.11.2026): under the heading two side-by-side
  choices — left "Sürücü axtarılır" (employers' vacancies), right "İş
  axtarıram" (drivers looking for work; only truck work: TIR / fura / lorry,
  no bus- or machine-only profiles) — with counts, then two-column
  square-ish cards (4 on the home page; Hamısına bax / Daha 20 = all of the
  chosen side — drivers and employers are never mixed, owner 05.11.2026).
  By role (client view): a driver (profile, no vacancy) sees only
  vacancies, an employer (vacancy, no profile) only drivers; both or none:
  both. The role cards and Uyğun təklif stay as they were.
  PR 2 (owner, 28.10.2026): "Müraciət et" on a vacancy, "İş təklif et" on a
  driver, "Müraciətlər və təkliflər" (/jobs/applications: Göndərildi ·
  Baxıldı · Danışıq gedir · İşə qəbul edildi only when BOTH confirm ·
  Rədd edildi · Bağlandı) and the bell with job notices
  (/jobs/notifications) — the server rules of 0069, no extra SQL.
- Age (owner, 28.10.2026, 0074): picked at registration (required, 16–90)
  and set / changed in Profil; stored as users.birth_date (1 January of
  the year), private (not in user_profiles); the İş Mərkəzi driver form
  starts with it.
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
  page (ad–VIP, VIP–ad …, VIP order moves on every few minutes). No gold
  frame or seal on the picture (Premium / VIP marks instead, 0066); rows
  grow with the text size so cards never overlap.
- TIR Bazarı catalogue (owner, 25.10.2026, 0064): ~130 brands; categories
  TIR · Orta yük · Kiçik yük · Qoşqu · Yarımqoşqu · Tikinti · Digər; brand,
  model, category and body type (optional chips in the form) are separate.
  Other spellings ("Mercedes", "КАМАЗ", "FH-16") are joined by
  `canonicalMarketBrand` / `market_name_key` — stored ads never rewritten.
  Logos only with a recorded source (docs/brand_logos.md), otherwise the
  letter square; 48 brand logos (Simple Icons, car-logos-dataset, 3 from the
  owner — Mərhələ 3, 25.10.2026),
  on a white plate in day and night, also in the computer's brand list.
- TIR Bazarı filter (owner, 25.10.2026, 0065): 12 popular brands with logos
  on top (Mercedes-Benz · DAF · Scania · Volvo · MAN · Renault · Iveco ·
  KAMAZ · Schmitz Cargobull · Krone · Kögel · MAZ). Optional per ad:
  Satışdadır / Sifarişlə (empty = in stock), wheel formula (not for
  trailers), equipment (Retarder · ADR · Kondisioner · Yataq), Vuruğu
  yoxdur / var — in the form, the filter, the ad page and on the computer.
- Admin → "Test məlumatlarını sil" (owner, 02.11.2026, 0083): admins
  only (server `_require_admin`, typed SİL) delete fake test profiles,
  loads, services, TIR Bazarı sale ads, job ads and TIR parks (0084) for good. A user goes
  with everything ("Hamısını sil": account + sign-in, loads, services,
  parks he added, ads, chats and messages also with real people,
  comments, bookings, test payments); never oneself, the founder or
  another admin; every deletion in the Audit Log.
- Profil (owner's two-screen design, 04.11.2026): the card on the Profil tab
  itself has the cover on top (the existing profile_details.cover_url and its
  editor) with the photo half over its edge, name, roles, country, badges; then one
  entry each — "Şəxsi məlumatlarım" (/profile/personal: name, e-mail,
  phone, birth date), "Mənim fəaliyyətim" (/profile/activity: roles 2 × 2 +
  Yüklərim · Servisim · Səhifəm və kataloqum · İş Mərkəzi · Reklam
  sifarişi), "TIR Parkı" (/profile/tirpark: manage, work, bookings, with the
  red count); "Baş admin idarəetməsi" (Maliyyə, Admin Panel) for the
  Baş admin = an admin who is the finance owner (is_finance_admin) or the
  Founder (founder_ids); every other platform admin (users.role = admin,
  appointed by the owner) gets "Admin idarəetməsi" with Admin Panel and
  opens /admin (owner, 04.11.2026, later the same day); Maliyyə only for the
  finance owner; then
  "Hesab və görünüş" (text size, Ayarlar, Hesabdan çıxış).
- Servis / TIRPark "Önə çıxar" (owner, 04.11.2026, 0093): the TIR Bazarı
  sheets (İrəli çək · VIP · Premium), packs, currency and card checkout; own
  prices per section (Admin → Servislər → "Önə çıxar qiymətləri", Admin →
  TIRPark), started from the Loads prices. The area is the service's / park's
  own place on the map (no country choice): promoted first in the Servislər
  list + map / the TIRPark map + list (100 km), with the "Reklam" mark; a tap
  opens the service / park page. Never shown among Loads. Only the service's
  owner (approved, active, real map place) or the park's approved manager
  (approved park) orders; applied only after a verified payment. The park
  owner's panel has "Parkı önə çıxar — reklam ver" on Ümumi (owner,
  05.11.2026); 0095 adds any missing pack with the standard Loads prices
  (never changes an admin's price) and reloads the API.
  Premium places (owner, 07.11.2026, 0103 — replaces 0102's map cards): a
  park's / service's / shop's Premium is always on its own map (as 0093)
  and its sheet has two cards side by side — TIR Bazarı · Yüklər bölməsi
  (one or both; nothing chosen = no order); price: one place = its own
  Premium price, both = + the Yüklər Premium price for the same days (no
  such pack = blocked, no made-up price); after a verified payment TIR
  Bazarı / Yüklər show it as the ad card (owner's picture, 07.11.2026):
  one low card across the page (the owner's size, then 20 % smaller overall: 90 pt tall at normal text, smaller texts / icons / button; was about a quarter of its
  width tall; grows only with the text size) with an orange glow — picture left (its
  photo / background / logo, else the default picture), "REKLAM", the
  kind's icon + name, one line about it (description / specialty, a park's
  amenities; nothing made up), 📍 city · km (km only when the user's place
  is already known; no GPS asked) and an orange "Profilə bax ›"; several =
  swiped with dots; on TIR Bazarı under the search box, on Yüklər above the
  tiles and exactly as wide as the two load cards (never past their edges); a tap opens its page.
  TIR Bazarı ads never pick Yüklər; İrəli çək / VIP unchanged.
- Profile backgrounds (owner, 05.11.2026, 0096): Park, Servis and Mağaza
  (the seller's page, profile_details.cover_url) share one flow — "Fon
  şəklini dəyiş" on the background for the owner only (park: its approved
  manager; service: its owner) → a bottom sheet "Fon şəklini seç":
  "Şablonlardan seç" (active admin templates of that section) or "Öz şəklini
  yüklə" (+ "Yerini düzəlt") → the frame preview (move / zoom) → saved. The
  park page (owner's design): background, round park picture half over its
  edge (tir_parks.logo_url, the manager's own picture, separate), name,
  "Şəkillər · n/10" (gallery stays admin-only), amenities, Yer
  rezervasiyası (unchanged), phone card (Zəng et), route card (Marşrut).
  Admin → "Fon şablonları": add (picture, name, Park / Servis / Mağaza),
  edit, Aktiv / Passiv, delete (profiles keep a deleted template); server
  checks + Audit Log. On TIRPark a tap on a park's name or picture opens its
  page (owner, 05.11.2026); the rest of the card selects it.
- Premium map markers (owner, 05.11.2026): promoted (0093) parks, services
  and shops get the owner's gold icons (assets/images/premium: park, service,
  shop = a service selling spare parts, category spare_parts), 20 % bigger
  than ordinary markers (which stay as they were), never clustered, "Premium"
  label for the Premium tier. 1 s after the map is ready they drop once onto
  their own coordinates (short fall, squash, one small bounce), one after
  another; moving the map never replays it. The switch on both maps is
  Parklar | Servislər | Mağazalar (Mağazalar = the services map filtered to
  spare_parts, /services?shops=1). TIR Bazarı has no map. On Mağazalar no
  service parts show (owner, 05.11.2026): no category chips, no Usta /
  Servis / Evakuator legend or filter, shop words ("n mağaza", "Mağazam"),
  the + reads "Mağaza əlavə et"; the filter keeps the shops.
- Map "+" buttons (owner, 06.11.2026): each section its own form — Servislər
  "+" → /service-join (Usta / Servis mərkəzi registration), Mağazalar "+" →
  /service-edit?kind=center&shop=1 (the same one-per-owner service form with
  spare_parts ticked; an existing service gets the category added).
  "Park rezervasiyalarım" (Rezervasiyalar və statuslar) stands on Profil
  right under "TIR Parkı"; its screen unchanged.
  Users add NO parking spots (owner, 07.11.2026, 0100): no "Dayanacaq
  əlavə et" in Profil → TIR Parkı, no /tirpark?add= mode; the map's
  "TIR parkı əlavə et +" stays and opens Profil → TIR Parkı (Park
  işlədirəm · Park işçisiyəm); tir_park_add refuses every call
  ('not_available'); users never had a direct INSERT on tir_parks. Parks
  come only from "Park işlədirəm" (admin approval), manager applications
  and the admins; spots added before stay (nothing deleted).
- "Təsdiqlənmiş hesab" (owner's picture, 07.11.2026, 0104): on the Profil
  card under the account owner's details — not verified yet: a pale blue
  badge, the slogan "Etibarını göstər, daha çox müştəri qazan" and "Ayda 20
  AZN · Aktiv et" (price from verified_plans); verified: the clear blue
  badge. Two ways, kept apart: the paid subscription (20 AZN / month,
  verified_subscriptions; ONLY a verified LIVE payment activates it, the
  server refuses a test checkout — no made-up activation; without a live
  shop "Aktiv et" only explains it) and the Baş admin's own grant
  (users.is_verified): only the Baş admin (admin + finance owner or Founder,
  is_chief_admin()) gives / takes it — a trigger refuses every other
  signed-in path ('chief_admin_only'), Admin → İstifadəçilər shows "Mavi tık
  ver" only to him; the SQL editor stays trusted.
  Everywhere (0105): user_profiles.is_verified = the grant OR a running
  paid subscription, so load cards, the load page, Mesajlar, TIR Bazarı and
  the ad banner show the badge for both; the own profile asks the view too.
  Another person's profile page (owner, 07.11.2026): the blue badge sits on
  the photo's corner (where the online dot was); the old pill's place shows
  the presence — a round green dot + "Online" (grey + "Offline").
- Bəyəndiklərim (owner, 07.11.2026, 0106): one page /favorites with the tabs
  Yüklər · TIR Bazarı · Mesajlar · Profillər (counts); the hearts in the
  Yüklər, TIR Bazarı, Mesajlar and Profil headers open it on their own tab.
  Hearts on a chat (the other person), on another person's profile, on a
  service / shop page and on an approved park page (user_favorites, read only
  by its owner, written only through favorite_set, checked on the server);
  load and ad hearts stay as they were (cargo_favorites / market_favorites).
  Liked chats stand first in Mesajlar with a small heart.
- After publishing (owner, 07.11.2026): a new load → Yüklər, a new TIR
  Bazarı ad → TIR Bazarı, a new service → Servislər, a new shop → Mağazalar,
  a "Park işlədirəm" request → TIRPark, each at once with a clear green
  notice ("… dərc olundu ✓", showPublishedNotice); an error keeps the form
  and what was typed; editing a saved one goes back where it came from;
  "Parkı qur" still opens the owner panel. Prostoy (free waiting 24 / 36 /
  48 h) is optional: nothing chosen on a new load, a second tap takes the
  choice off; a load without it shows no Prostoy row.
- Browsing without an account (owner, 07.11.2026, 0107): the link opens
  Yüklər straight away (no login page first). A visitor looks at Yüklər,
  TIR Bazarı, TIRPark, Servislər / Mağazalar, a load / ad / park / service
  page and public profiles (isGuestPath in core/router/guest_access.dart);
  anything else — "+" forms, Mesajlar, Profil, Bəyəndiklərim, a message, a
  call, a heart, an offer, a booking, a review, a complaint — opens the
  login page (askSignIn) and brings him back to the same page after signing
  in; the login page has an ✕ back to browsing. A visitor sees no phone
  number (a "Əlaqə üçün daxil olun" button instead). Server (0107): anon
  reads only an allow-list of public catalogue tables, with exactly the
  columns and rows a signed-in stranger reads (twin "<rule>_guest"
  policies), plus the read-only search functions; no users, messages,
  bookings, payments, favourites or job centre; no writes.
  Google sign-in is on (owner, 07.11.2026: Google Cloud project
  "FreightLink", OAuth client "FreightLink Web", published; Supabase
  provider enabled); Apple stays off for now.
- Service / shop pages (owner, 07.11.2026): the list card opens the profile
  (its buttons keep their own work); no mini map on the profile (address +
  "Marşrut" stay); a shop shows "Mağaza" as title and kind. "Mesaj yaz" on a
  page opens a page chat (0100: conversations.service_id / service_name /
  service_kind set only by get_or_create_service_conversation; the receiver
  is the owner; the person-to-person chat stays separate) — the thread shows
  "Mağaza: … / Servis: …" with a link to the page, the Mesajlar list names it.
- Google / Apple sign-in (owner, 07.11.2026): Supabase OAuth back to the
  app's address; a button is active only when its provider is on in
  Supabase (/auth/v1/settings), otherwise greyed out with a note. Panel
  steps in docs/OAUTH_GOOGLE_APPLE.md; no keys in the repository.
- Usta / Servis and Mağaza profile forms (owner's pictures, 06.11.2026,
  0097): one long scrolled page each, the same order — logo (left) +
  background (right), name (empty; faint placeholder "Servis adı" / "Mağaza
  adı" only), kinds, about, Ünvan (city, address, map + "Xəritədə yeri
  seç", GPS), phone + WhatsApp, iş saatları + 24/7, photos (up to 10), the
  save button at the end. The shop form shows only shop fields: product
  kinds shop_* (Yeni and İşlənmiş ehtiyat hissələri can both be chosen,
  Mühərrik, Elektrik, Təkər və disk, Yağlar, Aksesuarlar, Digər), no
  Usta / Servis choice, ixtisas or mobile service; the shop_* kinds never
  show on the service form or the Servislər chips. The service form keeps
  every service kind and field. Choice chips keep the existing look (no
  extra frames). Logo = service_providers.logo_url (service_set_logo,
  owner only, own picture); shown round on the service / shop page. No
  ready names, logos, texts or watermarks on backgrounds.
  Look (owner's picture 2, 06.11.2026): small labels over the fields
  ("Mağazanın adı *", "Məhsul kateqoriyaları *", "Təsvir", "Şəhər", "Tam
  ünvan"), fields with icons, dashed "add" boxes, "Xəritədə yeri seç" on
  the map, Telefon | WhatsApp and İş saatları | 24/7 side by side, the
  open-now row and the orange save button. The web build reads the texts
  (assets/i18n) fresh ("no-cache"), so a new version never shows raw keys.
  Logo + background as on the Profil card (owner, 06.11.2026): the
  background on top with a camera button, the round logo half over its
  lower edge with a small camera, the name beside it. Never empty: until
  the owner puts his own, the default pictures (assets/images/profile —
  abstract waves, orange for Servis, blue for Mağaza; no text / logo /
  watermark) show on the form and on the service / shop page.
- Service / shop advertising (owner, 06.11.2026): only "Önə çıxar"
  (İrəli çək · VIP · Premium, 0093) on the service page — the old banner
  ad ("Servis reklamı", /ad-create?service=) is no longer offered there,
  and Profil → Mənim fəaliyyətim shows "Reklam sifarişi" only to a user who
  already has ad orders (to pay / follow); /ads itself stays. The admins'
  old banner templates (ad_templates, audience service / all, active) are
  offered in "Fon şəklini seç" → Şablonlardan seç for Servis and Mağaza; a
  picked one is copied into the owner's own folder (no SQL needed).
- No admin approval for services, shops and parking spots (owner,
  06.11.2026, 0098 + 0099): a last trigger (zz_service_publish) publishes
  every service / shop its owner makes or saves (a re-run of an old guard
  cannot bring the waiting back); the waiting ones were published once;
  (0100: users add no parking spots any more); rejected /
  suspended / hidden stay; the admin can still take any of them down. The
  admin approves ONLY "Park işlədirəm" (park owner requests / manager
  applications — a park with a manager application keeps waiting). Each map its own places: a
  shop (spare_parts + shop_* only, ServiceProvider.isShop) only on
  Mağazalar, a service (also one that sells parts) only on Servislər,
  parks only on Parklar.
- Messages tab lists only chats the user is part of (even for admins).
- Loads page header is compact (owner, 27.10.2026): the logo with the
  slogan "Yüklər dünya üzrə hərəkətdədir" in one small line under it; no
  big headline / "CANLI XƏRİTƏ" label over the map on the phone (the
  computer keeps its hero text). The "CANLI" badge stays on the map.
- WhatsApp OTP / Meta work is paused until the owner says "Meta davam".
- One account for everyone: no role step at signup. In Profil the user
  turns on any combination of Daşıyıcı · Yük verən · Usta / Servis · Satış
  (users.activities, 0039). Turning one off deletes nothing and never
  closes existing chats; users.role is kept as it was.
- TIR Bazarı sale ads are published at once, no admin approval (owner,
  18.10.2026, 0041); the admin moderates afterwards (deactivate, VIP,
  delete). Chat from an ad opens the full-screen `/chat/:id`.

## 6. Daimi inkişaf və kod təhlükəsizliyi qaydaları (owner, 25.10.2026)

These rules apply to every future change, together with §1–§5 (they do
not replace them). Main principle: *tapşırıqdan kənar işlək sistemi
qoruyaraq, tapşırığın tamamlanması üçün zəruri bütün əlaqəli
dəyişiklikləri sərbəst həyata keçir.*

1. **Mövcud sistemi qoru.** Tapşırığa aid olmayan funksiyaları,
   dizaynları, məlumatları və faylları dəyişmə; işlək funksiyaları
   səbəbsiz yenidən yazma və silmə. GitHub, Supabase və tətbiq
   arxitekturasını qoru (§1). İstifadəçi məlumatlarına və mövcud
   elanlara zərər vurma (§3).
2. **Zəruri əlaqəli dəyişikliklərə icazə var.** Tapşırığın düzgün
   işləməsi üçün başqa funksiya da dəyişməlidirsə, onu da et — yalnız
   zəruri hissəni, səbəbini yekun hesabatda yaz. Əlaqəli funksiyaları da
   test et. Yalnız simptomu yox, əsas səbəbi düzəlt.
3. **İşi tam yekunlaşdır.** Hər xırda addım üçün təsdiq istəmə.
   Razılaşdırılmış tapşırığı analiz, kod və testlə birlikdə bitir; test
   xətalarını imkan daxilində özün düzəlt. Eyni problemin təkrar
   qayıtmasına yol vermə (regression test əlavə et, §2.4).
4. **Dəyişikliklərin təhlükəsizliyi.**
   - Hər tapşırıq ayrıca branch və PR-da (§2.2).
   - Mövcud funksiyaların pozulmadığını uyğun testlərlə yoxla (§2.5–2.7).
   - SQL miqrasiyası və verilənlər bazasında riskli dəyişiklik üçün
     **əvvəlcədən** sahibin təsdiqini al.
   - `main`-ə birləşdirmə və canlı yayım yalnız sahibin təsdiqi ilə.
   - Təsdiqsiz məlumat silmə, cədvəl dəyişmə və ya təhlükəli əməliyyat yox.
   - Sahibdən təsdiq yalnız həqiqətən vacib və riskli qərarlarda istənir.
5. **Resurslara qənaət.** Lazımsız araşdırma və təkrar əməliyyatdan
   yayın; mövcud kodu və komponentləri təkrar istifadə et; tapşırığı
   mümkün qədər bir iş dövründə bitir. Məhdudiyyət varsa, konkret
   səbəbini və ən praktik həllini bildir.
6. **Yekun hesabat** (qısa, hər tapşırıqdan sonra, §2.8 ilə birlikdə):
   - Nə dəyişdi?
   - Hansı əlaqəli funksiyalar düzəldildi?
   - Hansı testlər keçdi (burada / GitHub / yoxlanmayıb)?
   - Hansı problemlər qaldı?
   - PR linki.

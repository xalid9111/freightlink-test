# Package 2 — approved "night map" design (includes Package 1)

No database migrations, schema, RLS or Supabase settings were changed.

- Dark-only theme in the approved palette (core/theme/app_theme.dart):
  navy ground, orange accent, teal route color; fonts Big Shoulders
  Display / Inter / JetBrains Mono via google_fonts (new dependency).
- Home: dark hero with brand, credits/PRO, "Loads are moving worldwide"
  title, animated live world map (assets/images/world_map.jpg + overlay
  painter in widgets/live_map.dart), REAL stats computed from the open
  marketplace (active loads, countries, routes) and the most common
  routes. No invented numbers.
- Cargo card redesigned (route block with flags, spec grid, big price).
- Cargo detail: route/price card + delivery-stage stepper.
- Shipments: stepper on every shipment (core/widgets/status_stepper.dart).
- Chat: orange own bubbles, dark card bubbles for the other side.
- Bottom navigation, inputs, buttons, dialogs restyled via the theme.

Known limitation: the map illustration has Azerbaijani region labels
baked into the image; they do not change with the UI language.

## Map revision — global, decentralized network
- New world illustration (Americas → Australia) and a mesh overlay:
  18 flows between 21 countries in all directions (e.g. TR→AZ, AZ→CN,
  CN→TR, RU→IR, IR→CN, DE→TR, PL→GE, GE→RU, CN→DE, TR→GE, US→GB,
  BR→ZA, IN→AE, KR→RU, SG→AU, KZ→PL, ES→EG, ID→IN). No hub: every node
  is drawn with the same size and effect.

## Credits / payments switched off for the launch period (app only)
- Removed the credit balance chip and the PRO badge from the home screen.
- Cargo detail shows the owner's contact (name, tappable phone/email)
  free to every signed-in viewer — no "unlock (1 credit)" step. The data
  comes from public.users, which RLS already allows (users_select_all).
- Database untouched: credit tables, unlock_contact() and subscription
  plans from migration 0006 stay in place, unused, for a later release.

## Chat: online status, read ticks, unread badge (no migration)
- Online/offline in the chat header via Supabase Realtime Presence
  (core/presence/online_users.dart) — in-memory on the Realtime server,
  no table. Active while the user has the app open.
- Read receipts: opening a thread marks incoming messages read
  (messages.read_at + existing RLS policy messages_mark_read);
  own messages show ✓ sent / ✓✓ read.
- Unread count badge on the Messages tab (live stream of messages
  addressed to the user where read_at is null).

## Package 3 — profiles, last seen, badges, PWA polish
- NEW MIGRATION supabase/migrations/0009_profiles_presence_verification.sql
  (safe forward, idempotent): users.avatar_url / last_seen_at /
  is_early_member; trigger guarding role/is_verified/is_early_member
  from self-edit (security fix); users_select_all limited to signed-in
  users (privacy fix); "avatars" storage bucket + own-folder policies.
- Profile photo upload (Profile → tap photo), shown in chat header and
  on the cargo owner contact card.
- "Last seen" in the chat header when the other person is offline
  (heartbeat every 60 s while the app is open).
- Blue verified tick (users.is_verified, set by an admin in the
  dashboard) and "Early member" badge.
- PWA: new route-line app icon (home screen / splash / favicon), theme
  colour #0A1120.
- The app tolerates the migration not being run yet (features simply
  stay hidden), but run it before testing these features.

## Package 4 — chat: call, photos/files, voice messages
- NEW MIGRATION supabase/migrations/0010_chat_attachments.sql (safe
  forward): attachment columns on messages, private "chat-files"
  bucket (20 MB/file) readable/writable only by the conversation's two
  participants, served through 1-hour signed links.
- Chat header: phone button (tel: link to the other user's number).
- Composer (WhatsApp-style): 📎 photo / camera / file; mic button next to
  the text field turns into send when you type; tap mic to record, then
  send or delete. Voice notes play inside the bubble.
- New dependencies: record, audioplayers, http.
- Voice recording targets the web/PWA build (MediaRecorder); native
  builds show a "web only for now" message.
- Call button (chat header and the cargo owner's phone line) now asks:
  "Phone call" (tel:) or "Via WhatsApp" (opens wa.me chat with that
  number — WhatsApp has no public link that starts a call directly).
- Locations in chat (no migration): 📎 → "My location" sends the device
  position as a Google Maps link; any map link pasted into the chat
  (e.g. a location forwarded/copied from WhatsApp, Google Maps, Waze,
  Apple Maps) is shown as a location card. Tapping it offers Google
  Maps, Waze, Sygic and (on iPhone) Apple Maps, or "open link" for short
  links without coordinates. New dependency: geolocator.
- Cargo-detail navigation sheet also offers Sygic, and Apple Maps on
  iPhone Safari/PWA.
- Conversation list shows the other party's registered name (company or
  person), photo, online dot, verified tick, the route underneath, and
  an unread counter per conversation. Cargo cards show the poster's
  name/photo above the route.
- Profile: add/change phone number (country-code picker, validated;
  "already used" message for duplicates). Shown in orange with a hint
  when missing. Registration now requires a phone number. No migration.
- Home: "Find loads by route" panel — From / To country pickers (with
  "any country"), ⇄ swap, instant filtering of the list, ⭐ save route
  → "My routes" one-tap chips (stored on the device). Popular-route
  chips in the hero now filter too. Country picker extracted to
  core/widgets/country_picker.dart (also used by cargo create).
- Fix: the startup-error overlay no longer appears after the app has
  started (iOS Safari's share sheet triggered a harmless cross-origin
  "Script error." that covered the running app).
- Cargo detail: the delivery-stage stepper is replaced by a ROUTE MAP
  (OpenStreetMap via flutter_map, no API key): A = loading (teal),
  B = unloading (orange), road route + road distance & driving time
  (public OSRM router; straight-line fallback). Without saved exact
  points the city centres are geocoded (Nominatim) and marked
  "approximate". The cargo owner can open "Set exact points", tap the
  map to place A/B and save — coordinates + distance_km are stored on
  the cargo (existing columns; no migration). Stepper stays on
  Shipments. New dependencies: flutter_map, latlong2.

## Messaging audit (see MESSAGING_AUDIT_REPORT.md)
- NEW MIGRATION 0011_messaging_hardening.sql + rolled-back test script
  supabase/tests/messaging_audit_test.sql.

## Quick posting, edit/close, no Orders tab, smoother map
- "Add load" is a quick tap form: popular-country flag chips (+ "Other
  country" picker), city, weight chips 1/3/5/10/15/20/22/25/30 t (+
  custom), date chips Today / Tomorrow / Pick, price, short note;
  truck type / cargo type / volume folded under "More details".
- Owners can EDIT an open load (same form; moving a route end clears
  its stale exact point/distance) and CLOSE a listing (status
  "cancelled" — nothing deleted). Profile → "My loads" lists all own
  loads with Edit.
- Orders (Sifarişlər) tab removed from the bottom bar (screen/branch
  kept internally, no data change).
- Live map overlay repaints at ~24 fps and without blur filters
  (less jank / freezing on iPhone Safari & PWA).
- Edit is now offered for open AND agreed loads (new / carrier_found /
  agreed), and the Edit / Close buttons sit at the TOP of the owner's
  cargo detail. Close listing only while "new".
- Profile: ✏️ next to the name → change name / company name.
- Home & search feed use compact cargo rows (route with flags, weight ·
  date · distance, poster, price); full details on tap.

## Admin Panel (migration 0012)
- New area /#/admin (sections: dashboard, cargo, users, carriers,
  drivers, shipments, offers, reports, audit, system). See
  ADMIN_PANEL_REPORT.md.
- Profile shows an "Admin Panel" card for admin accounts.
- Login now returns you to the page you opened (e.g. /admin).
- Blocked / deactivated accounts see a red banner; the database refuses
  their new loads, offers, chats and messages.
- Cargo detail: "Report" link (non-owners) → public.reports.
- Loads hidden by an admin disappear from the marketplace (RLS + app).
- Bottom bar: Search tab removed (route search is on the Loads page);
  the 2nd slot (every role: owners, carriers, drivers, admins) is now an orange "+ Add load"
  button that opens the new-load form. The floating button on the Loads
  page was removed. "My loads" in Profile is shown for every role too.

## Open messaging (migration 0013)
- Any signed-in user (cargo owner, carrier, driver, admin) can start a
  chat with whoever posted a load; the "only carriers can contact" rule
  is gone. Self-chat still refused; one chat per (load, person); admin
  blocks (0012) still apply.
- Anti-freeze: chat open/send/attachment calls time out (20 s; file
  upload 2 min) and show "couldn't send" instead of spinning forever;
  location lookup times out after 20 s.
- supabase/tests/messaging_audit_test.sql T6 updated to the new rule.
- Voice notes: recorded mono with browser auto-gain, noise suppression
  and echo cancellation (louder, clearer on iPhone). Playback at full
  volume; web/index.html switches iOS Safari's audio session to
  "playback" before playing (loud speaker instead of ear speaker after
  the mic was used) and back to "play-and-record" before recording.

## Messages: search, direct chats, groups; USD (migration 0014)
- Messages tab: search box on top filters chats/groups by name or route
  and also lists matching people from the whole platform → tap to open
  a direct (person-to-person) chat (conversation with cargo_id = null,
  RPC get_or_create_direct_conversation, one per pair).
- Groups: "New group" (top-right icon) → name + people picked by name.
  Creator is group admin: add / remove members, rename. Anyone can
  leave; if the last admin leaves, the oldest member becomes admin.
  Text, photo, file, voice and location work in groups. Unread counts
  per group + included in the tab badge. Tables chat_groups,
  chat_group_members, group_messages (RLS: members only; writes through
  SECURITY DEFINER functions); group files in chat-files under g/<id>/.
- Prices: new loads/offers are in USD (form + DB column defaults).
  Existing rows keep their saved currency.

## New load form: compact route card + city picker
- "Haradan ⇄ Haraya" card replaces the country chips and city inputs.
  Tapping an end opens a bottom sheet: 🔍 city search (any language),
  popular cities as quick chips, a built-in list of ~170 freight cities
  with their country, and worldwide results from OpenStreetMap while
  typing (3+ letters). The country (and flag) comes with the city.
- ⇄ swaps the two ends instantly.
- Saved values: city's English name + country's English name (same
  columns as before, no migration). Cards/detail show catalogue cities
  in the reader's language (lib/core/constants/cities.dart); older
  hand-typed cities display unchanged. Editing a load keeps untouched
  ends exactly as stored (and their exact map point / distance).

## Advertising — phase 1 (migration 0015)
- Home feed: after every 2 loads one "SPONSORLU" banner (3:1,
  1200×400 px) with clear spacing; banner / "Şirkəti görüntülə" opens the
  advertiser's public profile (/user/:id: name, photo, tick, role,
  message + call, open loads). No live ads → feed is loads only.
- Profile → "Reklam ver" (every role): pick package → order
  (pending_payment) → payment instructions (set by admin) → "Ödəniş
  etdim" + reference → awaiting_approval. Never goes live by itself.
- Admin → Reklamlar: orders (payment received + approve, reject with
  note, notes, refund), "Banner əlavə et və yayımla" (image validated to
  3:1 / ≥900 px, ≤5 MB, uploaded to public bucket "ads"; title,
  start/end, active), ads list (edit, on/off), packages (name, days,
  price, visible) and payment instructions. Bell + sidebar badge count
  orders waiting. Everything audit-logged.
- Tables ad_packages (seeded inactive, price 0 — admin sets prices),
  ad_orders, ads; RLS: customers read own orders, everyone reads only
  live ads; all writes via SECURITY DEFINER functions.
- No real online payment yet: payment is confirmed manually by the admin.
- Admin banner upload: any photo ≥600×200 is centre-cropped to 3:1 and
  resized to exactly 1200×400 px in the browser before upload (no
  external editor needed); 5 MB limit applies to the final image.
- Blue tick: Admin → Reklamlar (ad card + order) and Admin → user detail
  have a one-tap "Mavi tık ver / götür" button (admin_update_user,
  is_verified, audit-logged). Verified advertisers get a blue ✓ badge in
  the banner's top-right corner and next to their name.

## Open Loads feed: 3D wheel (UI only)
- lib/features/cargo/presentation/widgets/wheel_feed.dart (new):
  WheelScope (scroll listener, detent detection, gentle snap, adaptive
  quality) + WheelItem (per-item scale / page-colour veil / small
  perspective tilt computed from distance to the viewport centre;
  child cached in a RepaintBoundary, only the transform repaints).
- cargo_marketplace_screen.dart: feed items wrapped in WheelItem, scroll
  view wrapped in WheelScope. Feed order (2 loads → ad) unchanged.
- lib/core/feedback/: tick + haptic (web: Web Audio-synthesised tick,
  no audio file; navigator.vibrate / iOS switch-haptic best effort;
  native: SystemSound + HapticFeedback). web/index.html functions
  flWheelEnable / flWheelTick / flWheelHaptic.
- Profile: "Lent səsi" and "Titrəmə" switches (SharedPreferences).
- No data, Supabase, RLS, ads or navigation logic changed.
- Feedback: tick sound removed (haptic only; Profile shows only the
  haptic switch). Wheel tuned for smoother motion: smoothstep curves,
  scale ≤7 %, veil ≤50 %, tilt ≤0.16 rad, softer/longer settle
  (easeOutQuart 260–560 ms).
- Ads: banner format 1350×300 (4.5:1) — slot no taller than a cargo card;
  only the image + tiny "SPONSORLU" tag + blue tick. Slot after every 6
  loads; each live ad shown once (no repeats); remaining slots show only
  "Reklam əlavə et" (opens the advertise screen).

## My loads fix + delete listing (migration 0016)
- Fix: tapping a load in "Yüklərim" did nothing (a tab route was pushed
  under the full-screen page). New full-screen routes /load/:id,
  /chat/:id, /chat-group/:gid are used from pages above the tab shell
  (My loads, public profile, new group, cargo detail → chat).
- Cargo detail (owner): "Elanı bağla" replaced by "Elanı sil" (any
  status). RPC delete_my_cargo: owner/admin only, refused once a
  shipment exists; chats about the load are detached and kept.

## Smoothness pass
- Page transitions: one short fade + 2 % rise on all platforms (theme
  pageTransitionsTheme). The previous iOS transition moved both pages
  and, in Safari, stacked with the browser animation ("double" change).
- Feed wheel: no auto-snap (no "catching"); iOS-style bouncing momentum;
  stable widget tree per item (Transform → foreground veil → cached
  card), no Stack; animated map pauses while the feed scrolls and when
  scrolled out of view; iPhone haptic hack removed (no DOM work during
  scroll). Haptic remains on Android (navigator.vibrate) / native apps.

## Live world map v2
- New background (user-supplied night-lights world map), 1400×700 JPEG
  (150 KB) with edge fades baked into the image → no frame, full width,
  blends into the hero colour; nothing runtime-costly.
- Trucks/icons removed. Separate transparent layer: orange/blue light
  beams between ~30 hubs on all continents (no single centre); quadratic
  "hop" arcs, bright head, fading tail, faint dashed path, origin pulse,
  arrival flash; up to 7 at once (4 on slow devices), random spawn times.
- One Ticker → ValueNotifier → CustomPainter(repaint:) (no rebuilds),
  pooled beams, no blur; pauses while the feed scrolls / map off-screen /
  tab hidden; drops to ~30 fps when frames are slow.
- Map v2.1: oval "globe" look (bulge warp + elliptical fade baked into
  the image, darker deep-navy tone; 113 KB); 15 soft red/green status
  lights fading in/out at random land points; "CANLI" badge with a
  breathing green light in the map's top-right corner. Beams unchanged.
- Home counters redesigned (reference image): 3 cards — Aktiv yük
  (open loads), Aktiv daşıyıcı (active carrier accounts, DB count), Son
  24 saat yeni yük (DB count) — round tinted icon, big number, label,
  chevron (loads cards scroll to the feed). Stacked layout on phones.
- Darker palette: background #050A14, hero #070C18, card #0C1322,
  cardAlt #131B2B, lines #1C2638 / #161F30; map re-baked to the new hero.

## Stat counters — tiny pills
- Home counters are now ~24 pt tall (~4 mm), ~60 pt wide (~1 cm) pills: icon + number only; label shown as tooltip / screen-reader text. Real counts unchanged.

## Voice messages — reliability (no DB change)
- Playback on web uses a plain HTML <audio> element and starts play() synchronously in the tap (iPhone Safari/PWA requirement); only one voice note plays at a time; if a note can't be played, a "tap to open" link appears.
- Recording: stop() / blob read have timeouts, empty/too-short recordings show a message instead of vanishing, mic is always released, real container is detected from the bytes (m4a/webm/ogg/wav) so the file is stored with the right type.
- Sending: one automatic retry, then a "Retry" snackbar that keeps the recording (not lost on weak internet).
- pubspec: `web: ^1.1.0` declared (was already a transitive dependency).

## Services module (phase 1) + Georgian
- See SERVICES_MODULE_REPORT.md. New SQL: supabase/migrations/0017_services.sql.
- Bottom bar: Yüklər · Yük əlavə et · Servislər · Mesajlar · Profil (labels 10.5 px so 5 tabs fit on phones).

## Review of the Package 1 / 1B build
- Texts `svc_status_pending` and `svc_create_intro` (5 languages) now say a new service appears on the map only after admin approval — matching 0018 (pending profiles are no longer public).

# Running FreightLink on a real device — step by step

This assumes you have never set up Flutter or Supabase before. Follow
the sections in order. Every value you need to copy is called out
explicitly.

---

## Part 1 — Install Flutter

1. Go to https://docs.flutter.dev/get-started/install and pick your OS
   (Windows / macOS / Linux). Follow that page's steps to download and
   unzip/install the Flutter SDK, and add it to your system `PATH`
   (the page shows exactly how per OS).
2. Install an editor: **VS Code** (https://code.visualstudio.com) is the
   simplest for beginners. Open it, go to the Extensions panel (left
   sidebar), search "Flutter", install the official **Flutter**
   extension (it pulls in the Dart extension automatically).
3. Open a terminal and run:
   ```
   flutter doctor
   ```
   This checks your setup and tells you what's missing. Fix anything it
   flags with a `[✗]` before continuing — it gives OS-specific
   instructions (e.g. "Android toolchain — Android SDK not found" tells
   you to install Android Studio). It's normal to see `[!]` warnings;
   only `[✗]` errors need to be fixed.

## Part 2 — Get a device to run on

Pick ONE:

**Option A — Android emulator (easiest, no physical phone needed)**
1. Install Android Studio: https://developer.android.com/studio
2. Open it → More Actions → Virtual Device Manager → Create Device →
   pick any phone → pick a system image (e.g. the latest one shown) →
   Finish.
3. Launch the emulator from the Virtual Device Manager (▶ button).

**Option B — A real Android phone**
1. On the phone: Settings → About phone → tap "Build number" 7 times
   (enables Developer Options).
2. Settings → Developer Options → enable "USB debugging".
3. Connect the phone to your computer with a USB cable. Accept the
   "Allow USB debugging?" prompt on the phone.

**Option C — iOS Simulator (Mac only)**
1. Install Xcode from the Mac App Store.
2. Open Xcode once, accept its license, let it finish installing
   components.
3. Run `open -a Simulator` in a terminal.

Once your device/emulator is ready, run:
```
flutter devices
```
You should see it listed. If not, don't proceed until it shows up —
run `flutter doctor` again to see why.

---

## Part 3 — Create your Supabase project

1. Go to https://supabase.com → Sign up (free) → **New project**.
2. Pick an organization (or create one), name the project (e.g.
   `freightlink`), set a database password (**save this somewhere** —
   you won't need it for the app, but you'll want it if you ever need
   to connect a database tool directly), pick the region closest to
   you, click **Create new project**. Wait 1–2 minutes for it to
   finish provisioning.
3. Once it's ready, go to **Project Settings → API** (gear icon in the
   left sidebar → API). You'll need two values from this page in Part 5:
   - **Project URL** (looks like `https://xxxxxxxx.supabase.co`)
   - **anon public** key (a long string starting with `eyJ...`) — NOT
     the `service_role` key; never put the service_role key in the
     Flutter app.
4. **Decide on email confirmation** (this affects what you'll see when
   you test registration — see Part 6, item 3):
   - Go to **Authentication → Providers → Email**.
   - **Confirm email** toggle:
     - **ON (the default)** — after registering, a real confirmation
       email is sent and the account isn't fully active until it's
       clicked. This is closer to production behavior.
     - **OFF** — registering signs the user in immediately, no email
       needed. **Much easier for quick testing on your own device.**
   - Either is fine to test with; just know which one you picked,
     since the app behaves differently in each case (explained below).

## Part 4 — Apply the database migrations

1. Install the Supabase CLI:
   - **macOS**: `brew install supabase/tap/supabase`
   - **Windows**: `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git` then `scoop install supabase`
   - **Linux / no Homebrew**: see https://supabase.com/docs/guides/cli/getting-started for your package manager, or download the binary directly from that page.
2. Confirm it installed: `supabase --version`
3. In a terminal, `cd` into the unzipped project folder (the folder
   containing `pubspec.yaml`).
4. Log in: `supabase login` (opens your browser to authorize).
5. Find your project's **Project Reference**: it's the subdomain part
   of your Project URL from Part 3 step 3 — e.g. if your URL is
   `https://abcdefghijk.supabase.co`, your project ref is
   `abcdefghijk`.
6. Link the CLI to your project:
   ```
   supabase link --project-ref YOUR_PROJECT_REF
   ```
   It will ask for the database password you set in Part 3 step 2.
7. Apply every migration in order:
   ```
   supabase db push
   ```
   This runs all 8 files in `supabase/migrations/` in order
   (`0001_schema.sql` → `0002_rls.sql` → `0003_seed.sql` →
   `0004_offer_resubmission_rule.sql` →
   `0005_fix_user_registration_trigger.sql` →
   `0006_monetization.sql` →
   `0007_auto_create_carrier_profile.sql` →
   `0008_fix_shipments_insert_policy.sql`). **If you already applied
   migrations 0001–0006 in an earlier session, run `supabase db push`
   again anyway** — it only applies new files, and 0007/0008 fix two
   real bugs found while building the marketplace (see
   `docs/reports/ACCEPTANCE_TEST_REPORT.md`): without them, carriers can't submit
   offers and accepted offers don't create shipments.

   **If this fails on the `insert into auth.users` line inside
   `0003_seed.sql`:** that specific statement writes directly into
   Supabase's internal auth table using a pattern that isn't an
   officially guaranteed-stable API (explained in that file's own
   comment) — delete that one `insert into auth.users (...) ... on
   conflict (id) do nothing;` statement and the matching `insert into
   public.users (...)` block right after it, then run `supabase db
   push` again. The four demo cargo listings will simply have no
   `owner_id` to attach to in that case — comment those out too, or
   just register your own accounts through the app instead (Part 6) and
   ignore the seed data entirely. Everything else in the 5 migrations
   is standard schema/RLS/trigger SQL with no such risk.

## Part 5 — Configure the app's environment file

1. In the project folder, copy the example env file:
   ```
   cp .env.example .env
   ```
   (On Windows without a Unix shell: just duplicate `.env.example` and
   rename the copy to `.env`.)
2. Open `.env` in your editor and fill in the two values from Part 3
   step 3:
   ```
   SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   SUPABASE_ANON_KEY=your-actual-anon-key-here
   ```
3. Leave `MAPBOX_ACCESS_TOKEN` and `FIREBASE_PROJECT_ID` as placeholder
   text — they aren't used by any code yet (those packages are
   deliberately commented out in `pubspec.yaml` until Phases 10/12; see
   that file's comment for why). `APP_ENV=development` is fine as-is.
4. **`.env` is already in `.gitignore`** — it will not get committed if
   you put this project in git. Never share this file or paste its
   contents somewhere public.

## Part 6 — Install packages and run the app

1. In the project folder:
   ```
   flutter pub get
   ```
   This downloads all the Dart packages listed in `pubspec.yaml`. If it
   fails, the error message will name the problem package — this is
   the point where a real dependency issue (version conflict, etc.)
   would surface; nothing found in this review should cause one, but
   this step has not been run in the environment that prepared this
   project (see this phase's report for exactly why).
2. Run:
   ```
   flutter analyze
   ```
   This is the real compiler check. It should report **no errors**
   (warnings/info are fine). If it reports errors, copy the exact
   message — it will point at a file and line number — that's the
   fastest way to get it fixed.
3. Run the app:
   ```
   flutter run
   ```
   Pick your device if it asks (matches what `flutter devices` showed
   in Part 2). First launch takes a while (compiling); subsequent runs
   are much faster.

### What you should see, step by step

1. **App opens to the Login screen.** The language shown matches your
   device/browser language if it's one of the 4 supported (Azerbaijani,
   Turkish, Russian, English), otherwise defaults to Azerbaijani.
2. Tap **"Qeydiyyatdan keçin"** (Sign up — label shown in whichever
   language is active) → lands on **Role select** with two cards: cargo
   owner and carrier.
3. Tap either card → **Register screen**, pre-labeled with your chosen
   role. Fill in name, email, an 8+ character password (confirm it
   matches), phone is optional. Tap **"Hesab yarat"** (Create account).
4. **What happens next depends on your Part 3 step 4 choice:**
   - **If "Confirm email" is OFF:** you're signed in immediately and
     land on the **Home tab**, with a greeting in the top bar. You'll
     now see a **bottom navigation bar with 5 tabs**: Loads (home),
     Search, Shipments, Messages, Profile.
   - **If "Confirm email" is ON:** a dialog appears telling you to
     check your email. Tap the button to dismiss it, you land back on
     **Login**. Check the inbox for the address you registered with
     (check spam too), click the confirmation link, **then** come back
     to the app and log in with that email/password on the Login
     screen.
5. If you registered as a **carrier**, the Home tab's top bar also
   shows a small **credit balance chip** (starts at 3 — a free signup
   bonus, see the report for why) and a **PRO** chip that shows a
   "coming soon" message when tapped — this is intentionally not a
   working purchase flow yet (see the report's monetization section).
6. Tap the **Profile tab** (bottom right): your name, role, email,
   phone if given, a verification status, and a **language switcher**
   — tap any of the 4 language chips and the whole app's text changes
   immediately, including the bottom nav labels.
7. Tap **"Çıxış"**-equivalent (Sign out, in whichever language is
   active) → you're bounced straight back to **Login** automatically
   (no manual navigation needed — the router's redirect logic reacts to
   the sign-out).
8. Search / Shipments / Messages tabs currently show an honest "coming
   soon" empty state, not fake content — that's expected; those screens
   are a later development phase.
9. While signed out, the app never lets you reach the tab bar at all —
   only `/login`, `/role-select`, and `/register` are reachable.

If every step above works, **the app is genuinely running, including
the PWA shell and language switching.**

---

## Verifying the one-active-pending-offer rule (Phase 2 addendum)

There's no UI for offers yet (that's Phase 7), so this is verified
directly in the Supabase dashboard's **SQL Editor** (left sidebar):

```sql
-- Use one of your demo/registered carrier + cargo IDs. If you kept the
-- seed data, this carrier_id and a cargo id both exist already:
-- carrier: 44444444-4444-4444-4444-444444444444

insert into public.offers (cargo_id, carrier_id, offered_price)
values ('<a real cargo id from select id from public.cargo limit 1;>',
        '44444444-4444-4444-4444-444444444444', 1700);
-- run once: succeeds.

insert into public.offers (cargo_id, carrier_id, offered_price)
values ('<the SAME cargo id>',
        '44444444-4444-4444-4444-444444444444', 1650);
-- run again with the same cargo+carrier: should FAIL with
-- "duplicate key value violates unique constraint
-- idx_offers_one_pending_per_carrier_cargo" — this is the rule working.

update public.offers set status = 'rejected'
  where cargo_id = '<that cargo id>' and carrier_id = '...' and status = 'pending';
-- now re-run the second insert above: it succeeds, because the
-- previous offer is no longer 'pending'.
```

---

## Verifying the contact-credit system (monetization architecture)

Also no UI yet (see the report — this is deliberately architecture
only, no payment provider connected). Verify the credit wallet and
atomic unlock function directly in the SQL Editor:

```sql
-- If you kept the seed data, the demo carrier already got a signup
-- bonus (3 credits) from the trigger in migration 0006:
select * from public.credit_wallets where carrier_id = '44444444-4444-4444-4444-444444444444';
-- balance should be 3

-- Simulate that carrier unlocking a cargo's contact details. This must
-- be run AS that user for auth.uid() to resolve — easiest way from the
-- SQL Editor is to temporarily test via the app itself once Phase 7
-- (offers UI) exists, but you can inspect the function's logic now:
select prosrc from pg_proc where proname = 'unlock_contact';

-- After a real unlock call (from the app, later), confirm it's atomic
-- and didn't double-charge:
select * from public.credit_transactions where carrier_id = '44444444-4444-4444-4444-444444444444' order by created_at desc;
select * from public.contact_unlocks where carrier_id = '44444444-4444-4444-4444-444444444444';
```

---

## Quick troubleshooting

| Problem | Likely cause |
|---|---|
| `flutter doctor` shows a red `[✗]` | Follow its own suggested fix — it's specific to what's missing |
| `flutter pub get` fails naming a package | Note the exact package + error, that's the next thing to fix |
| App shows a blank/white screen at launch | Check the terminal running `flutter run` for a red error — usually a `.env` value is missing/wrong |
| Login/Register does nothing and shows a red error banner | Almost always `SUPABASE_URL` or `SUPABASE_ANON_KEY` in `.env` is wrong — recheck Part 3 step 3 / Part 5 |
| `supabase db push` fails | See the specific note under Part 4 step 7 about the seed migration |
| Registered but never see the bottom navigation bar | You likely have "Confirm email" ON — check your inbox, see Part 6 step 4 |
| Language switch doesn't change some text | That text is likely hardcoded in a screen not yet wired to localization — see the report for exactly which screens are done |
| PWA install option doesn't appear on Android/iPhone | Must be served over **https://**, not `http://` — see Part 7 |

---

## Part 7 — Running it as a Progressive Web App (PWA)

This project already has everything needed for a PWA in the `web/`
folder: `manifest.json`, icons, and an `index.html` written to follow
Flutter's own documented web-initialization pattern. You don't need to
write or configure any of this — just build and serve it.

### Run it in a browser (development)

```
flutter run -d chrome
```

This opens the app in Chrome with hot-reload, same as running on a
phone. Good for quick iteration, but the PWA install prompt/behavior is
best tested from a **production build** (next section) — Chrome
doesn't treat a dev server the same way as a real deployed site.

### Build the production version

```
flutter build web --release
```

This creates a `build/web/` folder containing the complete, deployable
website — `index.html`, compiled Dart-to-JS, the manifest, icons, and
an auto-generated service worker (`flutter_service_worker.js`) that
caches the app for offline reloads. Everything in `build/web/` is what
you upload to hosting.

### Test it locally first

From inside `build/web/`, serve it with any static file server, for example:
```
cd build/web
python3 -m http.server 8000
```
Then open `http://localhost:8000` in a phone's browser on the same
Wi-Fi network (or use your computer's local IP instead of `localhost`
from the phone), or in your desktop browser.

**Note:** "Add to Home Screen" install behavior on iOS specifically
requires the page to be served over **https://**, not plain `http://`
— a local test server is fine for checking the app itself works, but
to actually test the install flow you'll need it deployed somewhere
with HTTPS (see below).

### Deploying it somewhere with HTTPS (so install actually works)

Any static-site host works — a few free/simple options:
- **Firebase Hosting** (`firebase deploy`, needs a free Firebase project)
- **Netlify** or **Vercel** (drag-and-drop the `build/web/` folder in their dashboard, or connect a git repo)
- **GitHub Pages**

Whichever you pick, the deployed folder is `build/web/` — nothing else
in this project needs to be uploaded for the web version.

### How to install it on iPhone (Safari)

1. Open the deployed https:// link in **Safari** (must be Safari, not
   Chrome — iOS only allows Safari to install PWAs to the home screen).
2. Tap the **Share** icon (square with an arrow, bottom of the screen).
3. Scroll down, tap **"Add to Home Screen."**
4. Confirm the name (defaults to "FreightLink"), tap **Add**.
5. The app icon now appears on the home screen; opening it launches
   full-screen, no Safari address bar — the `apple-mobile-web-app-*`
   meta tags in `web/index.html` are what make this work.

### How to install it on Android (Chrome)

1. Open the deployed https:// link in **Chrome**.
2. Chrome usually shows an **"Install app"** banner/prompt automatically
   after a few seconds — tap it.
3. If it doesn't appear: tap the **⋮** menu (top right) → **"Install app"**
   (or **"Add to Home screen"** depending on Chrome version).
4. Confirm — the icon appears on the home screen and/or app drawer,
   opening full-screen like a native app.

### If `flutter build web` complains about `web/index.html`

The `index.html`/`manifest.json`/icons in this project were hand-written
to match Flutter's own documented customization pattern (not generated
by running a Flutter command, since no Flutter SDK was available while
preparing this project — see this phase's report for exactly what
wasn't testable here). If the build tool ever complains specifically
about `web/index.html` not matching what it expects for your installed
Flutter version:
1. Rename the current file somewhere safe first: `mv web/index.html web/index.html.bak`
2. Run `flutter create . --platforms=web` — this regenerates a fresh,
   version-correct `web/index.html` for your exact Flutter SDK, and
   won't touch any of your `lib/` code.
3. Re-apply the PWA-specific pieces from `web/index.html.bak` into the
   new file: the `<meta name="theme-color">`, `apple-mobile-web-app-*`
   meta tags, `<link rel="apple-touch-icon">`, `<link rel="manifest">`,
   and the `#app-loading` splash `<div>`/`<style>` block — everything
   between `<head>` and the Flutter-generated loader script at the
   bottom is safe to copy across as-is.


---

## Part 8 — The two-phone acceptance test

Once both devices have the app running (Part 6) and pointed at the
same Supabase project:

1. **On iPhone**: register as a cargo owner (User A). Land on the Home
   tab. Tap the **+ "Yeni yük yerləşdir"** button, fill in the form
   (pickup/destination country+city are required; everything else,
   including the coordinate fields, is optional), tap **Publish
   cargo**.
2. **On Android**: register as a different account, as a carrier (User
   B). Land on the Home tab — pull down to refresh if the new cargo
   doesn't appear immediately. Tap it to open the detail screen.
3. **On Android**: scroll to **"Sizin təklifiniz"**, enter a price, tap
   **Submit offer**. Then tap **"Mesaj göndər"** and send a message.
4. **On iPhone**: open the same cargo's detail screen (from the Home
   tab or by pulling to refresh). Scroll to **"Daxil olan təkliflər"**
   — B's offer should be there. Tap the checkmark to accept it. Open
   the **Messages tab** — B's conversation should be there; open it and
   reply.
5. **On Android**: the **Shipments tab** should now show the new
   shipment (pull to refresh if needed).

If every step above works, the core marketplace loop is genuinely
functional end-to-end across two real accounts on two real devices —
see `docs/reports/ACCEPTANCE_TEST_REPORT.md` for exactly what was fixed to make this
possible and what rough edges remain.

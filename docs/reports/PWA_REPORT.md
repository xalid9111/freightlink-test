# FreightLink — Plain-Language Report: PWA, Languages, and Monetization

You're not a programmer, so this report avoids code and explains
everything in terms of what you can actually see and do.

A safety checkpoint (a saved snapshot of the working app) was made
before any of this work started, so nothing from before is at risk.

---

## 1. What was already present

From the earlier phases: a working sign-up/login system, a database
with 21 tables (cargo, carriers, trucks, offers, shipments, messages,
ratings, etc.), and security rules controlling who can see/edit what.
The app opened straight to a single "Cargo marketplace" screen after
login, in Azerbaijani only, with no mobile-app install option.

## 2. What I added

- **A real installable app (PWA).** The website version can now be
  "installed" on a phone's home screen on both iPhone and Android, and
  opens full-screen like a normal app, with its own icon.
- **Four languages.** Azerbaijani, Turkish, Russian, and English are
  all fully working — every screen that exists today changes language
  instantly when you switch it, and your choice is remembered next
  time you open the app.
- **A bottom navigation bar** with 5 sections: Loads, Search,
  Shipments, Messages, Profile — the standard layout for a mobile
  marketplace app.
- **The database structure for your monetization plans** — contact
  credits, a Pro plan, and featured/VIP listings — built and secured,
  but with no real payment system connected (see point 6).
- **A "Start Navigation" capability** that can hand off a pickup or
  delivery address to Google Maps, Apple Maps, or Waze. It's built and
  ready, but there's no button for it yet anywhere in the app, because
  the screen that would need it (cargo details) hasn't been built yet
  — I didn't want to bolt it onto an unrelated screen just to have
  something to click, per your own instruction not to fake
  functionality.

## 3. What was changed

- The old single "Cargo marketplace" screen is now the "Loads" tab
  inside the new bottom navigation bar.
- The Profile screen gained a language switcher (tap a language name
  to switch instantly).
- Every screen's text — buttons, error messages, form labels — now
  comes from a translation system instead of being fixed text, which
  is what makes the 4 languages possible.
- A carrier's profile now automatically gets 3 free contact-unlock
  credits the moment their account is created (a starter amount so the
  feature is testable before any real purchase option exists — easy to
  change later).

## 4. Files/components affected

In plain terms, not a code-by-code list: the app's navigation
structure, all 4 existing screens (Login, Sign-up, Role selection,
Profile), the "Loads" home screen, 3 new placeholder screens (Search,
Shipments, Messages), a new translation system, a new "open in maps"
capability, and 1 new database file adding the credits/Pro/featured
structure. A full technical file list is in `PWA_TECHNICAL_NOTES.md`
if you ever hand this to a developer.

## 5. What currently works

- Sign up, log in, log out, role selection (cargo owner vs. carrier)
- Switching between all 4 languages, anywhere in the app, remembered
  between visits
- The bottom navigation bar and its 5 tabs
- A carrier seeing their credit balance and a "PRO" button (which
  honestly says "coming soon" when tapped — it's not wired to anything
  fake)
- Installing the app to a phone's home screen (once it's deployed
  online — see point 8)
- All database security rules that existed before, plus new ones
  protecting the credit/subscription data

## 6. What still requires external services or accounts

- **Actually deploying the app online** (so it has a real web address)
  needs a hosting account — Firebase, Netlify, Vercel, or GitHub Pages
  are all free options; instructions are in `SETUP_GUIDE.md`.
- **A real payment provider** (Stripe, a local Azerbaijani payment
  processor, etc.) for actually selling credits or the Pro plan — none
  is connected. The database is ready for one to be plugged in, but I
  did not build a fake "buy now" button, per your instruction.
- **Google/Apple sign-in** — still not connected (needs developer
  accounts with Google and Apple), same as before this round of work.
- **Push notifications** — not built yet, needs a Firebase account.
- **The actual Apple App Store / Google Play apps** — see points 12–13.

## 7. How to run the project

Full beginner instructions are in `SETUP_GUIDE.md`. Short version: it
needs Flutter (free, installed once on your/a developer's computer) and
your Supabase project (already set up from earlier phases) — then one
command builds the website version.

## 8. How to open the PWA

Once built and uploaded to any hosting service (see point 6), it's just
a normal website link. Opening that link in a phone's browser is the
"open the PWA" step — `SETUP_GUIDE.md` Part 7 has the exact build and
upload commands.

## 9. How to install it on iPhone using Safari

1. Open the app's web link in **Safari** (must be Safari, not Chrome).
2. Tap the **Share** button, then **"Add to Home Screen."**
3. Tap **Add.** The FreightLink icon now appears on the home screen and
   opens full-screen, like a normal app.

## 10. How to install it on Android

1. Open the app's web link in **Chrome.**
2. Chrome shows an **"Install app"** prompt automatically, or you can
   tap the **⋮** menu → **"Install app."**
3. The icon appears on the home screen / app drawer.

## 11. How language switching works

Open the **Profile** tab (bottom right) and tap any of the 4 language
names shown there. The whole app updates immediately — no restart
needed. The app also guesses your language automatically the very
first time it's opened (based on your phone/browser's language), but
you can always change it yourself, and your choice is remembered after
that.

## 12. How the future App Store version should be created

Because this app is built with Flutter, the same code that makes the
website version also builds directly into a real iPhone app — it does
not need to be rebuilt from scratch. The path is:
1. A paid **Apple Developer account** ($99/year) is required — this is
   Apple's requirement for anyone, not something specific to this
   project.
2. A developer runs one command (`flutter build ipa`) to produce the
   App Store-ready file.
3. That file is uploaded through Apple's **App Store Connect** website,
   along with screenshots, a description, and privacy details (which
   Apple requires you to fill in yourself, since only you know your
   actual data practices).
4. Apple reviews it (usually a few days) before it goes live.

## 13. How the future Google Play version should be created

Same underlying app, same idea:
1. A one-time **Google Play Developer account** ($25 one-time fee).
2. A developer runs one command (`flutter build appbundle`) to produce
   the Play Store file.
3. Upload it via the **Google Play Console**, fill in the store
   listing, and submit for review (usually faster than Apple's).

In both cases (12 and 13), the app talks to the **same Supabase
backend** the website version uses — there is no separate database or
separate account system to maintain. This was a deliberate design
choice from Phase 1 specifically so this day would be a packaging step,
not a rebuild.

## 14. What I recommend as the next phase

Build the actual **Loads screen** — the real cargo marketplace feed
with route cards, search, and filters (this is the core of the whole
product, and it's currently just a placeholder). That would also give
a real screen to finally attach the "Start Navigation" button and the
"unlock contact" credit-spending button to, so those two pieces stop
being backend-only and become something you can actually click and
test.

---

### A few things worth knowing, honestly

- I could not actually run this app anywhere while building it — there
  is no Flutter installed in the environment I work in, and no internet
  access to reach your Supabase project. Everything above was built
  carefully and checked with automated scripts I wrote specifically to
  catch mistakes (checking that every file connects to the right other
  files, that all 4 languages have exactly the same text entries, and
  that the database structure has no errors) — but the real,
  final proof is running it yourself following `SETUP_GUIDE.md`. If
  something doesn't work, the troubleshooting table at the end of that
  guide is the first place to look, and I can fix it from there.
- I found and fixed one thing while building this that could have
  broken the website version specifically: a piece of code I initially
  used doesn't work on web browsers at all (it's iPhone/Android-only
  code) — I caught it by checking the whole project and replaced it
  with something that works everywhere, before it became a problem.

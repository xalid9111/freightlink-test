# Deploying the FreightLink Web/PWA build for iPhone Safari testing

> Historical note. The active Pages workflow is now
> `.github/workflows/deploy.yml` ("Deploy FreightLink Web"); `deploy-web.yml`
> is no longer used.

## What changed in this pass (3 files, no Dart / DB changes)
- `web/index.html` — replaced the direct `_flutter.loader.load()` call
  (which only loaded `flutter.js`, so `_flutter.buildConfig` was never
  set and boot would fail) with the standard Flutter 3.22+
  `<script src="flutter_bootstrap.js" async>`. Splash, PWA meta tags and
  the on-screen boot-error diagnostics are unchanged.
- `web/flutter_bootstrap.js` — NEW. Standard documented template
  (`{{flutter_js}}`, `{{flutter_build_config}}`, `_flutter.loader.load`)
  carrying the same splash-removal + error-display callback.
- `.github/workflows/deploy-web.yml` — NEW. Builds with Flutter 3.35.4
  and publishes `build/web` to GitHub Pages.

## Path A — no Flutter install needed (GitHub Pages)
1. Create a GitHub repo (free plan: Pages requires it to be **public**).
   Upload the contents of `freightlink_work/` (including the hidden
   `.github` folder). `.env` is git-ignored; it is not needed.
2. Repo **Settings → Secrets and variables → Actions** → add secrets
   `SUPABASE_URL` and `SUPABASE_ANON_KEY` (values from your local `.env`).
3. Repo **Settings → Pages → Source: GitHub Actions**.
4. **Actions** tab → "Deploy Web (GitHub Pages)" → **Run workflow**
   (also runs on every push to `main`). ~5–8 min.
5. URL: `https://<github-user>.github.io/<repo-name>/`

## Path B — you have Flutter 3.35.x locally (Netlify Drop)
```
# pubspec.yaml lists .env as an asset: a fresh copy / ZIP has none, so make
# one as the GitHub workflows do (keys still come from --dart-define).
[ -f .env ] || printf 'APP_ENV=production\n' > .env
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key from .env> \
  --dart-define=APP_ENV=production
```
Drag the `build/web` folder onto https://app.netlify.com/drop → HTTPS URL.
(No `--base-href` needed; the site is served at the domain root.)

## Supabase (dashboard settings only — no migrations)
Authentication → URL Configuration:
- **Site URL**: your new HTTPS URL
- **Redirect URLs**: add the same URL

Otherwise the "Confirm email" link redirects to `localhost`. The email
is confirmed either way — after tapping the link, open the app URL and
log in. For faster testing you may temporarily turn off
Authentication → Providers → Email → "Confirm email".

## Routing note
The app uses Flutter's default hash URLs (`/#/login`), so no server
rewrite rules are needed on any static host.

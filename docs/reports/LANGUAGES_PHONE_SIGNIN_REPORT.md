# Languages, phone country picker, sign-in safety — report

## Changes
1. **Phone country picker** (register screen): new `PhoneCountryField` widget
   (`lib/core/widgets/phone_country_field.dart`) + `lib/core/constants/phone_countries.dart`
   (219 countries). Searchable bottom sheet (name in any app language, ISO, calling code);
   the calling code is added automatically. Sign-in method unchanged — no phone login / OTP.
2. **All languages for everyone**: az, tr, en, ru, ka, zh (Simplified Chinese, zh-CN).
   New `assets/i18n/zh.json`. Country choice never limits the language.
3. **Profile language button**: one button showing the current language; tap opens all
   languages as buttons; choice applies immediately and is saved (SharedPreferences `fl_locale`).
4. **signIn safety** (`auth_repository_impl.dart`): if the `public.users` row is missing or
   cannot be read after Supabase sign-in, the session is signed out (no half-signed-in state)
   and a clear error is shown (`error_profile_missing` / `error_profile_load_failed`).
   Normal login/registration flow unchanged.

## Checks
- `flutter analyze` / `flutter test`: **NOT run here** — no Flutter SDK in this environment and
  downloads are blocked. They run in the GitHub Actions build; only a green build confirms it.
- `scripts/validate_i18n.py`: OK — 6 files, identical key sets, matching placeholders.
- `scripts/validate_dart.py`: OK — no bracket/paren/quote balance issues.
- Const-with-runtime-value scan: no new issues.
- Tests added/updated: `test/phone_countries_test.dart`, `test/i18n_catalog_test.dart`.

## Limits (honest)
- Chinese country names cover the 44 main countries; other countries show English names.
- City names and service category names (from DB) fall back to English in Chinese.
- First Chinese render on web may take a moment while the CJK font loads.
- No SQL / migration changes.

## Font: Arial only (follow-up)
- Every screen, heading, label, ad banner and the web loading screen use one font family: **Arial**.
- Arial itself is a licensed Monotype font and cannot be shipped inside the app. Flutter web
  cannot use the device's own fonts, so the family "Arial" is served by bundled
  **Liberation Sans 2.1.5** (SIL OFL 1.1, `assets/fonts/OFL.txt`) — the free font with exactly
  Arial's letter widths and the same look.
- `google_fonts` removed (no more Inter / Big Shoulders / JetBrains Mono / Montserrat downloads).
- Ads: font choice hidden (only Arial). Older ads that saved another font name are drawn in Arial.
  The 1200×400 layout coordinates are unchanged.
- Georgian and Chinese letters are not in Arial; Flutter web shows them with its automatic
  Noto fallback.
- Headings were a narrow font before; Arial is wider, so some long headings may wrap or be cut
  with "…" sooner. Check on the site after deploy.
- New test: `test/app_font_test.dart`. flutter analyze / test still NOT run here (no SDK).

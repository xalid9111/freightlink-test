# AutoFix diagnostics — what a report contains

Everything fits the existing `app_errors` columns (migration 0034); no SQL
change is needed.

| Field (Admin → AutoFix → Loglar) | What it holds |
|---|---|
| Addımlar (`breadcrumbs`) | Last **10** steps before the problem: screens (`→ /profile`, ids shown as `:id`), taps and swipes as a screen zone + percent only (`tap ↗ 92%,4%`), dialogs opened/closed, app to background/foreground, earlier errors (`✖ …`). A step repeated right away is shown once with `×N`. |
| Səhifə (`route`) | Active screen, ids masked, no query string. |
| Versiya (`app_version`) | `0.1.0+<commit>` — the exact build (set by `deploy.yml`). |
| Stack (`stack`) | `context:` what Flutter was doing (e.g. `during performLayout() · rendering library`), then the trace. |
| Brauzer (`user_agent`) | `390×844 @3.0 · pwa · az | <browser user agent>`. |
| Grouping (`fingerprint`) | Same kind + code + screen area + message; object hashes (`#78ac7`), numbers and ids are ignored, so one bug is one row with a counter. |

**Never collected:** what was typed, what was tapped (texts, names), message
content, passwords. E-mail addresses, phone numbers, access tokens and URL
query strings are removed from every field (`scrubPii` in
`lib/core/autofix/autofix_logic.dart`, unit-tested).

## Minified stack → Dart file:line

Release web builds have minified stacks. `deploy.yml` keeps the source map of
every build as the artifact `sourcemap-<commit>` for 90 days (it is not
published on the site).

1. Admin → AutoFix → the problem → **Kopyala**; save the text as `report.txt`.
2. Note the commit in "Versiya" (`0.1.0+abc1234`); in GitHub Actions open the
   "Deploy FreightLink Web" run for that commit → Artifacts → download
   `sourcemap-…` and unzip it.
3. `python3 scripts/symbolize_stack.py <unzipped folder> < report.txt`

Frames `main.dart.js:LINE:COL` get `[file.dart:line function]`, and
`minified:Xyz` class names get the real class name.

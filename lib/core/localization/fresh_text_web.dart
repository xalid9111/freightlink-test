import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The web build: right after a new version is published the browser can
/// still hold the OLD texts (cached up to 10 minutes) while the new app
/// asks for new ones — the screen then shows raw keys such as
/// "shop_edit_title" (owner, 06.11.2026). Ask the server each time
/// ("no-cache": an unchanged file comes back as a short 304), so the texts
/// always match the app. Null = could not fetch: the bundle is used.
Future<String?> fetchFreshText(String assetPath) async {
  try {
    final url = Uri.parse(web.document.baseURI).resolve('assets/$assetPath').toString();
    // A hanging network never keeps the logo on screen for long: after 10 s
    // the app's own bundled texts are used (null below).
    final res = await web.window.fetch(url.toJS, web.RequestInit(cache: 'no-cache')).toDart.timeout(const Duration(seconds: 10));
    if (!res.ok) return null;
    return (await res.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}

/// Faster start (owner, 08.11.2026): the texts fetched fresh once for this
/// published version ([build]) are kept on the device, so the next starts
/// of the SAME version need no network for them. A new version has another
/// [build], so its texts are fetched fresh again — an app never uses the
/// texts of another version. Storage full / private mode: just not kept.
const _prefix = 'fl_i18n:';

String? readCachedText(String key, String build) {
  try {
    final v = web.window.localStorage.getItem('$_prefix$key');
    if (v == null) return null;
    final nl = v.indexOf('\n');
    if (nl <= 0 || v.substring(0, nl) != build) return null;
    return v.substring(nl + 1);
  } catch (_) {
    return null;
  }
}

void storeCachedText(String key, String build, String text) {
  try {
    web.window.localStorage.setItem('$_prefix$key', '$build\n$text');
  } catch (_) {}
}

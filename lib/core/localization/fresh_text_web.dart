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
    final res = await web.window.fetch(url.toJS, web.RequestInit(cache: 'no-cache')).toDart;
    if (!res.ok) return null;
    return (await res.text().toDart).toDart;
  } catch (_) {
    return null;
  }
}

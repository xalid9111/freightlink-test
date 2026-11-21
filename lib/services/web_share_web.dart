import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The phone's own share sheet (WhatsApp, Telegram, Mesajlar …) through the
/// browser's Web Share API. True when it opened (also when the user then
/// closed it); false when the browser has none (a computer) — the caller
/// copies the link instead.
Future<bool> shareViaSystem({required String title, required String text, required String url}) async {
  try {
    final nav = web.window.navigator;
    if (!(nav as JSObject).has('share')) return false;
    final data = web.ShareData(title: title, text: text, url: url);
    await nav.share(data).toDart;
    return true;
  } catch (e) {
    // AbortError = the user closed the sheet: it did open.
    return '$e'.contains('AbortError');
  }
}

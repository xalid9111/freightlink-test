import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens a navigation app's own link (waze://, com.sygic.aura://) in THIS
/// tab, the way Safari hands it to the app (owner, 01.11.2026: Waze and
/// Sygic did not open — the old way opened a new, empty window). True when
/// the page lost focus or was hidden, i.e. the app (or iPhone's "Open in
/// …?" question) took over; false when nothing happened (app missing).
Future<bool> openAppLink(String link) async {
  try {
    var left = false;
    final onLeave = ((web.Event _) => left = true).toJS;
    final onVisibility = ((web.Event _) {
      if (web.document.hidden) left = true;
    }).toJS;
    web.window.addEventListener('blur', onLeave);
    web.window.addEventListener('pagehide', onLeave);
    web.document.addEventListener('visibilitychange', onVisibility);
    web.window.location.href = link;
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    web.window.removeEventListener('blur', onLeave);
    web.window.removeEventListener('pagehide', onLeave);
    web.document.removeEventListener('visibilitychange', onVisibility);
    return left || web.document.hidden;
  } catch (_) {
    return false;
  }
}

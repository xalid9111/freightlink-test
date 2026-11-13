import 'package:web/web.dart' as web;

/// The app's own address (base href), e.g.
/// https://tirlink.app/ (owner's domain since 13.11.2026) — where Google / Apple
/// send the user back after signing in.
String? appBaseUrl() {
  try {
    final base = Uri.parse(web.document.baseURI);
    return base.replace(query: '', fragment: '').toString().replaceAll(RegExp(r'[?#]+$'), '');
  } catch (_) {
    return null;
  }
}

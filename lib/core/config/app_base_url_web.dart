import 'package:web/web.dart' as web;

/// The app's own address (base href), e.g.
/// https://xalid9111.github.io/freightlink-test/ — where Google / Apple
/// send the user back after signing in.
String? appBaseUrl() {
  try {
    final base = Uri.parse(web.document.baseURI);
    return base.replace(query: '', fragment: '').toString().replaceAll(RegExp(r'[?#]+$'), '');
  } catch (_) {
    return null;
  }
}

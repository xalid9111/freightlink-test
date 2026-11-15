import 'dart:js_interop';

@JS('flLogos.apply')
external void _apply(JSString json);

/// Keeps the logos on the device and updates the page's icon links and the
/// start-up logo at once (web/site_logos.js). Never throws.
void applyLogosToPage(String json) {
  try {
    _apply(json.toJS);
  } catch (_) {}
}

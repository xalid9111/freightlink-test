import 'splash_stub.dart' if (dart.library.js_interop) 'splash_web.dart' as impl;

/// The logo + spinner of web/index.html stays until the app's first frame
/// is on screen (owner, 08.11.2026): no empty dark page between the logo
/// and the Yüklər page any more. The page has its own safety timer too.
void hideStartupSplash() => impl.hideStartupSplash();

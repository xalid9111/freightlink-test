import 'browser_nav_stub.dart' if (dart.library.js_interop) 'browser_nav_web.dart' as impl;

/// True right after a browser-driven navigation (Safari back/forward swipe
/// or the browser's back button). Safari animates those itself, so the
/// app's page transition must not run a second time.
bool recentBrowserNavigation() => impl.recentBrowserNavigation();

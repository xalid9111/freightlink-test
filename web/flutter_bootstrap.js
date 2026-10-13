// Flutter web bootstrap template (Flutter >= 3.22).
// `flutter build web` replaces the two {{...}} tokens below with the
// flutter.js loader and this build's _flutter.buildConfig, then writes
// the result to build/web/flutter_bootstrap.js (loaded by index.html).
// See https://docs.flutter.dev/platform-integration/web/initialization
//
// No serviceWorkerSettings: current Flutter no longer generates a
// service worker by default, and not caching the app shell also means
// every reload on iPhone gets the latest deployed build during testing.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      const loadingEl = document.getElementById('app-loading');
      if (loadingEl) loadingEl.remove();
      window.flStarted = true;
      await appRunner.runApp();
    } catch (err) {
      if (window.flShowBootError) window.flShowBootError(String(err));
    }
  },
});

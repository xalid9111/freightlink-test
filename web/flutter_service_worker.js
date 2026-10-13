// Kill switch for service workers registered by OLD FreightLink builds.
// The app does not use a service worker any more. If an old one asks for
// an update, it gets this file: it removes the old Flutter caches,
// unregisters itself and reloads open windows. User data (localStorage /
// the Supabase session) is not touched.
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    try {
      var keys = await caches.keys();
      await Promise.all(keys.filter(function (k) { return /^flutter-/.test(k); }).map(function (k) { return caches.delete(k); }));
      await self.registration.unregister();
      var clients = await self.clients.matchAll({ type: 'window' });
      clients.forEach(function (c) { try { c.navigate(c.url); } catch (e) {} });
    } catch (e) {}
  })());
});

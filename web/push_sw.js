// TırLink Web Push service worker (SQL 0121, owner 14.11.2026).
// It handles ONLY: push (show the notification) and notificationclick (open
// the right page). No fetch handler and no cache: the site's files always
// come straight from the network, as before (pwa_guard.js keeps removing
// every other, old service worker).
self.addEventListener('install', function () { self.skipWaiting(); });

self.addEventListener('push', function (event) {
  var d = {};
  try { d = event.data ? event.data.json() : {}; } catch (e) { d = { body: event.data ? event.data.text() : '' }; }
  var title = d.title || 'TırLink';
  var tag = d.tag || 'tirlink';
  var url = (typeof d.url === 'string' && d.url.indexOf('/#/') === 0) ? d.url : '/';
  event.waitUntil((async function () {
    // The same chat again: one notification with a count instead of many.
    var count = 1;
    try {
      var old = await self.registration.getNotifications({ tag: tag });
      if (old && old.length && old[0].data && old[0].data.count) count = old[0].data.count + 1;
    } catch (e) {}
    var body = d.body || '';
    if (count > 1) body = body + ' (+' + (count - 1) + ')';
    await self.registration.showNotification(title, {
      body: body,
      tag: tag,
      renotify: true,
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      data: { url: url, count: count }
    });
  })());
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil((async function () {
    var list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      try {
        c.postMessage({ type: 'fl-open', url: url });
        if ('focus' in c) return c.focus();
      } catch (e) {}
    }
    if (self.clients.openWindow) return self.clients.openWindow(url);
  })());
});

// iPhone Safari / Home Screen PWA guards (see CLAUDE.md, task 2026-10-13).
// Loaded before Flutter. Never touches localStorage (the Supabase session)
// or any user data.
(function () {
  // 1) Browser-driven navigation (Safari back/forward swipe, back button):
  //    Safari already animates it, so Flutter must not animate it again.
  var lastPop = 0;
  window.addEventListener('popstate', function () { lastPop = Date.now(); }, true);
  window.flNav = {
    recentBrowserNav: function () { return Date.now() - lastPop < 700; }
  };

  function onceIn(key, ms) {
    try {
      var now = Date.now();
      var prev = Number(sessionStorage.getItem(key) || 0);
      if (now - prev < ms) return false;
      sessionStorage.setItem(key, String(now));
      return true;
    } catch (e) { return false; }
  }

  // 2) Service workers / caches left by OLD builds. The app no longer uses
  //    a service worker; an old one can keep serving stale files to a Home
  //    Screen app (mixed versions → freezes). Remove them once, keep data.
  try {
    if ('serviceWorker' in navigator && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(function (regs) {
        if (!regs || !regs.length) return;
        var controlled = !!navigator.serviceWorker.controller;
        Promise.all(regs.map(function (r) { return r.unregister(); })).then(function () {
          var clean = window.caches && caches.keys ? caches.keys().then(function (keys) {
            return Promise.all(keys.filter(function (k) { return /^flutter-/.test(k); })
              .map(function (k) { return caches.delete(k); }));
          }) : Promise.resolve();
          clean.then(function () {
            if (controlled && onceIn('fl_sw_cleanup', 10 * 60 * 1000)) window.location.reload();
          });
        });
      }).catch(function () {});
    }
  } catch (e) {}

  // 3) iOS can drop the WebGL context of a Home Screen app while it is in
  //    the background; the screen then stays frozen. If the context is not
  //    restored shortly after the app is visible again, reload once
  //    (max once a minute). The session is kept (localStorage).
  var glLost = false;
  window.addEventListener('webglcontextlost', function (e) {
    glLost = true;
    try { e.preventDefault(); } catch (x) {}
    check();
  }, true);
  window.addEventListener('webglcontextrestored', function () { glLost = false; }, true);
  function check() {
    if (!glLost || document.hidden) return;
    setTimeout(function () {
      if (glLost && !document.hidden && onceIn('fl_gl_reload', 60 * 1000)) window.location.reload();
    }, 2500);
  }
  document.addEventListener('visibilitychange', check);
  window.addEventListener('pageshow', check);

  // 4) Right after a new version is published the browser can still hold
  //    the old main.dart.js (cached up to 10 minutes) while a separately
  //    loaded part (e.g. TIR Bazarı) is already new: the part then fails to
  //    load. Fetch the app files fresh into the cache and reload once
  //    (max once in 2 minutes). The session and user data are kept.
  window.flFreshReload = function () {
    if (!onceIn('fl_fresh_reload', 2 * 60 * 1000)) return false;
    var files = ['index.html', 'flutter_bootstrap.js', 'main.dart.js'];
    for (var i = 1; i <= 8; i++) files.push('main.dart.js_' + i + '.part.js');
    var base = document.baseURI || './';
    Promise.all(files.map(function (f) {
      try { return fetch(new URL(f, base).toString(), { cache: 'reload' }).catch(function () {}); } catch (e) { return null; }
    })).then(function () { window.location.reload(); }, function () { window.location.reload(); });
    return true;
  };
})();

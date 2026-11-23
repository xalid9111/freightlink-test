// iPhone Safari / Home Screen PWA guards (see CLAUDE.md, task 2026-10-13).
// Loaded before Flutter. Never touches localStorage (the Supabase session)
// or any user data.
(function () {
  // 1) Browser-driven navigation (Safari back/forward swipe, back button):
  //    Safari already animates it, so Flutter must not animate it again.
  var lastPop = 0;
  window.addEventListener('popstate', function () { lastPop = Date.now(); }, true);

  // 1b) A swipe always goes ONE STEP BACK, never forward (owner, 15.11.2026:
  //     "geri sürüşdürəndə arxadakı səhifəyə keçməlidir … ardıcıllıq bütün
  //     səhifələrdə"). iPhone's Home Screen app treats a swipe the other way
  //     as "forward" and reopened the page just left (Şifrəni dəyiş after
  //     going back to Şəxsi məlumatlarım). Flutter numbers its history entries
  //     (state.serialCount); a move to a HIGHER number than the page on screen
  //     is a forward step: it is stopped before Flutter sees it and turned
  //     into one step back from where the user was. Taps that open pages
  //     (pushState) are untouched. Registered before Flutter's own listener,
  //     so stopImmediatePropagation keeps Flutter on the current page.
  function serialOf(st) {
    return st && typeof st.serialCount === 'number' ? st.serialCount : null;
  }
  var current = serialOf(history.state);
  var redirecting = false;
  try {
    ['pushState', 'replaceState'].forEach(function (name) {
      var orig = history[name];
      history[name] = function (state) {
        var r = orig.apply(this, arguments);
        var n = serialOf(state);
        if (n !== null) current = n;
        return r;
      };
    });
  } catch (e) {}
  window.addEventListener('popstate', function (ev) {
    var next = serialOf(ev.state);
    if (redirecting) {
      redirecting = false;
      if (next !== null) current = next;
      return;
    }
    if (next !== null && current !== null && next > current) {
      ev.stopImmediatePropagation();
      var steps = next - current; // how far forward the browser went
      redirecting = true;
      // Back to where the user was, plus one more step back if there is one.
      history.go(-(steps + (current > 0 ? 1 : 0)));
      return;
    }
    if (next !== null) current = next;
  }, true);
  window.flNav_never_forward = true;
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
      navigator.serviceWorker.getRegistrations().then(function (all) {
        // The Web Push worker (push_sw.js, 0121: no fetch, no cache) stays.
        var isPush = function (url) { return /\/push_sw\.js(\?|$)/.test(url || ''); };
        var regs = (all || []).filter(function (r) {
          var w = r.active || r.waiting || r.installing;
          return !(w && isPush(w.scriptURL));
        });
        if (!regs.length) return;
        var ctl = navigator.serviceWorker.controller;
        var controlled = !!ctl && !isPush(ctl.scriptURL);
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

  // 5) iPhone Home Screen app: after the on-screen keyboard closes iOS can
  //    leave the page scrolled by a few pixels; the picture then no longer
  //    matches where taps land (a button reacts only above it). Put the
  //    page back to 0 — Flutter itself never scrolls the document.
  //    Only when no text field is focused (keyboard closed): while typing
  //    iOS may scroll on purpose to keep the field above the keyboard.
  function typing() {
    var a = document.activeElement;
    return !!a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable);
  }
  function unshift() {
    try {
      if (typing()) return;
      if (window.scrollX || window.scrollY) window.scrollTo(0, 0);
    } catch (e) {}
  }
  document.addEventListener('focusout', function () { setTimeout(unshift, 120); setTimeout(unshift, 500); }, true);
  window.addEventListener('orientationchange', function () { setTimeout(unshift, 400); });
  window.addEventListener('pageshow', unshift);
  try {
    if (window.visualViewport) window.visualViewport.addEventListener('resize', function () { setTimeout(unshift, 150); });
  } catch (e) {}

  // 6) The iPhone home bar (owner, 23.11.2026: "uygulama dəyişdirmək
  //    istədiyimdə səhifə öz özünə hərəkət edir"; later: "aşağıdan yuxarı
  //    sürüşdürüb səhifəni qaldıranda yük kartları ... hərəkətə başlayır"):
  //    the swipe up from the very bottom edge that switches apps reached
  //    Flutter too, so the list under it scrolled. The first version read
  //    the home-bar height from env(safe-area-inset-bottom), but Flutter
  //    replaces the viewport tag without viewport-fit=cover, so it was 0 on
  //    the iPhone and the guard never ran. Now a fixed strip of the bottom
  //    edge (HOME_STRIP px, on touch screens): a touch that STARTS there is
  //    held back from Flutter; if it moves (the app-switch swipe) nothing of
  //    it ever reaches the page; if it ends as a tap it is handed to Flutter
  //    then (down + up), so a button that reaches the edge still works.
  //    Nothing is prevented: iOS / Android still switch apps; every touch
  //    that starts above the strip is untouched.
  var HOME_STRIP = 28;
  var TAP_SLOP = 8;
  function inHomeBar(y) {
    return y >= window.innerHeight - HOME_STRIP;
  }
  var held = {}; // pointerId -> { down: PointerEvent, moved: bool }
  var replaying = false;
  window.addEventListener('pointerdown', function (e) {
    if (replaying || e.pointerType !== 'touch' || !inHomeBar(e.clientY)) return;
    held[e.pointerId] = { down: e, moved: false };
    e.stopImmediatePropagation();
  }, true);
  window.addEventListener('pointermove', function (e) {
    var h = held[e.pointerId];
    if (replaying || !h) return;
    if (Math.abs(e.clientY - h.down.clientY) > TAP_SLOP || Math.abs(e.clientX - h.down.clientX) > TAP_SLOP) h.moved = true;
    e.stopImmediatePropagation();
  }, true);
  ['pointerup', 'pointercancel'].forEach(function (type) {
    window.addEventListener(type, function (e) {
      var h = held[e.pointerId];
      if (replaying || !h) return;
      delete held[e.pointerId];
      e.stopImmediatePropagation();
      if (type !== 'pointerup' || h.moved) return;
      // A plain tap in the strip: hand it to Flutter now.
      try {
        replaying = true;
        var t = h.down.target || document.elementFromPoint(h.down.clientX, h.down.clientY);
        t.dispatchEvent(new PointerEvent('pointerdown', h.down));
        t.dispatchEvent(new PointerEvent('pointerup', e));
      } catch (x) {
      } finally {
        replaying = false;
      }
    }, true);
  });
  window.flHomeBarGuard = true;
})();

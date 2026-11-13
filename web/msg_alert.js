// New-message / new-load sound + browser notification (see lib/core/notify).
// Browsers only allow sound after the user has touched the page once, so
// the first tap/click "unlocks" audio and asks for notification permission.
//
// Owner, 13.11.2026 ("bildiriş anında səs çıxmır"): the sound is played
// through Web Audio (one AudioContext, the two short sounds decoded once).
// A context resumed by a tap keeps working on iPhone Safari / the Home
// Screen app, where a plain <audio> element often stays silent after the
// first time. The old <audio> path is the fallback.
(function () {
  var files = { message: 'sounds/message.wav', cargo: 'sounds/cargo.wav' };
  var ctx = null, buffers = {}, loading = {}, audios = {}, unlocked = false, asked = false;

  function context() {
    if (ctx) return ctx;
    try {
      var C = window.AudioContext || window.webkitAudioContext;
      if (C) ctx = new C();
    } catch (e) { ctx = null; }
    return ctx;
  }

  function load(kind) {
    var c = context();
    if (!c || buffers[kind] || loading[kind]) return loading[kind] || Promise.resolve(buffers[kind]);
    loading[kind] = fetch(files[kind], { cache: 'force-cache' })
      .then(function (r) { return r.arrayBuffer(); })
      .then(function (data) {
        return new Promise(function (ok, bad) { c.decodeAudioData(data, ok, bad); });
      })
      .then(function (b) { buffers[kind] = b; loading[kind] = null; return b; })
      .catch(function () { loading[kind] = null; return null; });
    return loading[kind];
  }

  function element(kind) {
    if (!audios[kind]) {
      audios[kind] = new Audio(files[kind]);
      audios[kind].preload = 'auto';
    }
    return audios[kind];
  }

  function playElement(kind) {
    try {
      var a = element(kind);
      a.currentTime = 0;
      var p = a.play();
      if (p && p.catch) p.catch(function () {});
    } catch (e) {}
  }

  function playBuffer(kind) {
    var c = context(), b = buffers[kind];
    if (!c || !b) return false;
    try {
      if (c.state === 'suspended' && c.resume) c.resume();
      var src = c.createBufferSource();
      src.buffer = b;
      src.connect(c.destination);
      src.start(0);
      return true;
    } catch (e) { return false; }
  }

  function unlock() {
    var c = context();
    if (c) {
      try { if (c.state !== 'running' && c.resume) c.resume(); } catch (e) {}
      load('message');
      load('cargo');
      if (!unlocked) {
        unlocked = true;
        // A silent one-sample sound inside the tap opens the output on iOS.
        try {
          var s = c.createBufferSource();
          s.buffer = c.createBuffer(1, 1, 22050);
          s.connect(c.destination);
          s.start(0);
        } catch (e) { unlocked = false; }
      }
    } else if (!unlocked) {
      unlocked = true;
      ['message', 'cargo'].forEach(function (k) {
        var a = element(k);
        a.muted = true;
        var p = a.play();
        var done = function () { try { a.pause(); a.currentTime = 0; } catch (e) {} a.muted = false; };
        if (p && p.then) { p.then(done).catch(function () { a.muted = false; unlocked = false; }); } else { done(); }
      });
    }
    if (!asked) {
      asked = true;
      askPermission();
    }
  }

  function askPermission() {
    try {
      if ('Notification' in window && Notification.permission === 'default') {
        var r = Notification.requestPermission();
        if (r && r.catch) r.catch(function () {});
      }
    } catch (e) {}
  }

  ['touchend', 'click', 'keydown', 'pointerdown'].forEach(function (ev) {
    window.addEventListener(ev, unlock, { capture: true, passive: true });
  });
  // Back from the background (another app / tab): the context may have been
  // suspended — it is resumed on the next tap, and tried at once here.
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden && ctx && ctx.state === 'suspended') { try { ctx.resume(); } catch (e) {} }
  });

  function show(title, body, tag) {
    var opts = { body: body, icon: 'icons/Icon-192.png', badge: 'icons/Icon-192.png', tag: tag || 'fl-msg', renotify: true };
    try {
      if (navigator.serviceWorker && navigator.serviceWorker.getRegistration) {
        navigator.serviceWorker.getRegistration().then(function (reg) {
          if (reg && reg.showNotification) { reg.showNotification(title, opts); } else { new Notification(title, opts); }
        }).catch(function () { try { new Notification(title, opts); } catch (e) {} });
      } else {
        new Notification(title, opts);
      }
    } catch (e) {}
  }

  window.flMsgAlert = {
    play: function (kind) {
      var k = files[kind] ? kind : 'message';
      if (playBuffer(k)) return;
      // Not decoded yet: decode and play when ready, the <audio> way meanwhile.
      var p = load(k);
      if (p && p.then && context()) {
        p.then(function (b) { if (!b || !playBuffer(k)) playElement(k); });
      } else {
        playElement(k);
      }
    },
    // Only when the app is in the background (another tab / app on top).
    notify: function (title, body, tag) {
      try {
        if (!document.hidden) return;
        if (!('Notification' in window) || Notification.permission !== 'granted') return;
        show(title, body, tag);
      } catch (e) {}
    },
    // "Səsi yoxla" in Settings (a tap, so audio is allowed): plays the
    // message sound, asks for notifications, and says what the browser
    // allows: 'granted' | 'denied' | 'default' | 'unsupported'.
    test: function () {
      unlock();
      askPermission();
      window.flMsgAlert.play('message');
      try { return ('Notification' in window) ? String(Notification.permission) : 'unsupported'; } catch (e) { return 'unsupported'; }
    }
  };
})();

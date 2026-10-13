// New-message / new-load sound + browser notification (see lib/core/notify).
// Browsers only allow sound after the user has touched the page once, so
// the first tap/click "unlocks" audio and asks for notification permission.
(function () {
  var audios = {}, unlocked = false, asked = false;
  var files = { message: 'sounds/message.wav', cargo: 'sounds/cargo.wav' };

  function ensure(kind) {
    var k = files[kind] ? kind : 'message';
    if (!audios[k]) {
      audios[k] = new Audio(files[k]);
      audios[k].preload = 'auto';
    }
    return audios[k];
  }

  function unlockOne(a) {
    a.muted = true;
    var p = a.play();
    var done = function () { try { a.pause(); a.currentTime = 0; } catch (e) {} a.muted = false; };
    if (p && p.then) { p.then(done).catch(function () { a.muted = false; unlocked = false; }); } else { done(); }
  }

  function unlock() {
    if (!unlocked) {
      unlocked = true;
      try {
        unlockOne(ensure('message'));
        unlockOne(ensure('cargo'));
      } catch (e) { unlocked = false; }
    }
    if (!asked) {
      asked = true;
      try {
        if ('Notification' in window && Notification.permission === 'default') {
          var r = Notification.requestPermission();
          if (r && r.catch) r.catch(function () {});
        }
      } catch (e) {}
    }
  }

  ['touchend', 'click', 'keydown', 'pointerdown'].forEach(function (ev) {
    window.addEventListener(ev, unlock, { capture: true, passive: true });
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
      try {
        var a = ensure(kind);
        a.currentTime = 0;
        var p = a.play();
        if (p && p.catch) p.catch(function () {});
      } catch (e) {}
    },
    // Only when the app is in the background (another tab / app on top).
    notify: function (title, body, tag) {
      try {
        if (!document.hidden) return;
        if (!('Notification' in window) || Notification.permission !== 'granted') return;
        show(title, body, tag);
      } catch (e) {}
    }
  };
})();

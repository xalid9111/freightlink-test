// TırLink Web Push in the page (SQL 0121). Nothing runs on its own: the
// service worker is registered only when the user taps "Aktiv et" (or when
// this device already allowed it), so start-up stays as fast as before.
(function () {
  var SW = '/push_sw.js';
  function supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }
  function isIos() {
    var ua = navigator.userAgent || '';
    return /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }
  function standalone() {
    try { return window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true; } catch (e) { return false; }
  }
  // 'granted' | 'denied' | 'default' | 'ios_install' | 'unsupported'
  function state() {
    if (!supported()) return isIos() && !standalone() ? 'ios_install' : 'unsupported';
    try { return String(Notification.permission); } catch (e) { return 'unsupported'; }
  }
  function platform() {
    var ua = navigator.userAgent || '';
    if (isIos()) return 'ios';
    if (/Android/i.test(ua)) return 'android';
    return 'desktop';
  }
  function key(b64) {
    var t = String(b64).replace(/-/g, '+').replace(/_/g, '/');
    var s = t + '===='.slice(0, (4 - (t.length % 4)) % 4);
    var raw = atob(s), out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }
  function isPush(r) {
    var w = r && (r.active || r.waiting || r.installing);
    return !!(w && /\/push_sw\.js(\?|$)/.test(w.scriptURL));
  }
  async function registration() {
    var regs = await navigator.serviceWorker.getRegistrations();
    for (var i = 0; i < regs.length; i++) if (isPush(regs[i])) return regs[i];
    return null;
  }
  function activated(reg) {
    if (reg.active) return Promise.resolve(reg);
    return new Promise(function (resolve) {
      var w = reg.installing || reg.waiting;
      var done = function () { resolve(reg); };
      var t = setTimeout(done, 10000);
      if (!w) { clearTimeout(t); return resolve(reg); }
      w.addEventListener('statechange', function () { if (w.state === 'activated') { clearTimeout(t); done(); } });
    });
  }
  function result(o) { return JSON.stringify(o); }

  // iPhone asks for the permission only inside a REAL browser gesture
  // (touchend / click), not inside Flutter's own tap callback. So "Aktiv et"
  // arms a request and the same tap's touchend / click (or, elsewhere, the
  // pointerup right after Flutter's handler) asks — like the sound unlock in
  // msg_alert.js. Armed for 15 s: if the window did not open, a second tap
  // opens it.
  var pending = null;
  var readyReg = null; // the push worker, active (kept for a subscribe inside a later tap)
  var readyKey = null; // the VAPID public key as bytes
  function ask() {
    if (!pending) return;
    var p = pending;
    pending = null;
    clearTimeout(p.timer);
    p.run();
  }
  ['touchend', 'click'].forEach(function (ev) { window.addEventListener(ev, ask, { capture: true, passive: true }); });
  window.addEventListener('pointerup', function () { if (!isIos()) ask(); }, { passive: true });

  function errText(e) { return String((e && (e.name ? e.name + ': ' : '') + (e.message || '')) || e).slice(0, 160); }

  // The worker + the key, ready before anything is asked.
  async function prepare(publicKey, keyUrl) {
    if (!readyKey) {
      var k = publicKey;
      if (!k && keyUrl) {
        var r = await fetch(keyUrl, { cache: 'no-store' });
        k = (await r.json()).publicKey;
      }
      if (!k) return false;
      readyKey = key(k);
    }
    if (!readyReg) {
      var reg = (await registration()) || (await navigator.serviceWorker.register(SW, { scope: '/' }));
      readyReg = await activated(reg);
    }
    return true;
  }
  function done(sub) { return result({ status: 'granted', sub: sub.toJSON(), platform: platform() }); }

  // After the permission: subscribe; if iPhone wants that inside a tap too,
  // say "tap again" — the next tap subscribes right inside its touchend.
  async function subscribe(perm, publicKey, keyUrl) {
    if (perm !== 'granted') return result({ status: perm });
    if (!(await prepare(publicKey, keyUrl))) return result({ status: 'not_ready' });
    var sub = await readyReg.pushManager.getSubscription();
    if (sub) return done(sub);
    try {
      sub = await readyReg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: readyKey });
      return done(sub);
    } catch (e) {
      return result({ status: 'tap_again', error: errText(e) });
    }
  }

  function arm(run, resolve) {
    pending = {
      run: run,
      timer: setTimeout(function () {
        if (pending) { pending = null; resolve(result({ status: 'no_gesture' })); }
      }, 15000)
    };
  }

  function enable(publicKey, keyUrl) {
    if (!supported()) return Promise.resolve(result({ status: state() }));
    var safe = function (perm) {
      return subscribe(perm, publicKey, keyUrl).catch(function (e) { return result({ status: 'error', error: errText(e) }); });
    };
    var perm = Notification.permission;
    if (perm === 'denied') return Promise.resolve(result({ status: 'denied' }));
    if (perm === 'granted') {
      // Allowed already: with the worker ready, subscribe inside this tap.
      if (readyReg && readyKey) {
        return new Promise(function (resolve) {
          arm(function () {
            var s;
            try { s = readyReg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: readyKey }); } catch (e) { s = Promise.reject(e); }
            Promise.resolve(s).then(function (sub) { resolve(done(sub)); },
              function (e) { resolve(result({ status: 'error', error: errText(e) })); });
          }, resolve);
        });
      }
      return safe('granted');
    }
    // Not asked yet: the window opens inside this tap's touchend / click.
    return new Promise(function (resolve) {
      arm(function () {
        var asked;
        try { asked = Notification.requestPermission(); } catch (e) { asked = Promise.resolve(Notification.permission); }
        Promise.resolve(asked).then(function (p) { safe(p).then(resolve); }, function () { safe(Notification.permission).then(resolve); });
      }, resolve);
    });
  }

  // This device's subscription (no prompt, nothing registered).
  async function current() {
    try {
      if (!supported() || Notification.permission !== 'granted') return '';
      var reg = await registration();
      if (!reg) return '';
      var sub = await reg.pushManager.getSubscription();
      return sub ? result({ sub: sub.toJSON(), platform: platform() }) : '';
    } catch (e) { return ''; }
  }

  // Sign-out / "Söndür": this device stops; returns its endpoint.
  async function disable() {
    try {
      var reg = await registration();
      if (!reg) return '';
      var sub = await reg.pushManager.getSubscription();
      if (!sub) return '';
      var ep = sub.endpoint;
      try { await sub.unsubscribe(); } catch (e) {}
      return ep;
    } catch (e) { return ''; }
  }

  // A tap on a notification while the app is open: go to its page.
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.addEventListener('message', function (ev) {
        var d = ev.data || {};
        if (d.type === 'fl-open' && typeof d.url === 'string') {
          var h = d.url.split('#')[1];
          if (h) window.location.hash = h;
        }
      });
    }
  } catch (e) {}

  window.flPush = { supported: supported, state: state, enable: enable, current: current, disable: disable, isIos: isIos, standalone: standalone };
})();

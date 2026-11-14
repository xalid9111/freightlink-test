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
    var s = (b64 + '===='.slice((b64.length + 3) % 4)).replace(/-/g, '+').replace(/_/g, '/');
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
  function ask() {
    if (!pending) return;
    var p = pending;
    pending = null;
    clearTimeout(p.timer);
    var asked;
    try { asked = Notification.requestPermission(); } catch (e) { asked = Promise.resolve(Notification.permission); }
    Promise.resolve(asked).then(p.go, function () { p.go(Notification.permission); });
  }
  ['touchend', 'click'].forEach(function (ev) { window.addEventListener(ev, ask, { capture: true, passive: true }); });
  window.addEventListener('pointerup', function () { if (!isIos()) ask(); }, { passive: true });

  async function subscribe(perm, publicKey, keyUrl) {
    if (perm !== 'granted') return result({ status: perm });
    var k = publicKey;
    if (!k && keyUrl) {
      var r = await fetch(keyUrl, { cache: 'no-store' });
      k = (await r.json()).publicKey;
    }
    if (!k) return result({ status: 'not_ready' });
    var reg = (await registration()) || (await navigator.serviceWorker.register(SW, { scope: '/' }));
    reg = await activated(reg);
    var sub = await reg.pushManager.getSubscription();
    if (!sub) sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key(k) });
    return result({ status: 'granted', sub: sub.toJSON(), platform: platform() });
  }

  function enable(publicKey, keyUrl) {
    if (!supported()) return Promise.resolve(result({ status: state() }));
    var safe = function (perm) {
      return subscribe(perm, publicKey, keyUrl).catch(function (e) { return result({ status: 'error', error: String((e && e.message) || e) }); });
    };
    // Already answered before: no window needed.
    if (Notification.permission !== 'default') return safe(Notification.permission);
    return new Promise(function (resolve) {
      pending = {
        go: function (perm) { safe(perm).then(resolve); },
        timer: setTimeout(function () {
          if (pending) { pending = null; resolve(result({ status: 'no_gesture' })); }
        }, 15000)
      };
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

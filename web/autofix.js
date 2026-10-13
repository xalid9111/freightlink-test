// AutoFix helpers for the Dart side (see lib/core/autofix).
(function () {
  window.flAutoFix = {
    ua: function () { try { return String(navigator.userAgent || '').slice(0, 300); } catch (e) { return ''; } },
    reload: function () { try { window.location.reload(); } catch (e) {} },
    hidden: function () { try { return !!document.hidden; } catch (e) { return false; } },
    standalone: function () {
      try { return !!(navigator.standalone || (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)); } catch (e) { return false; }
    }
  };
})();

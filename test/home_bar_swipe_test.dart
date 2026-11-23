import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iPhone home bar (owner, 23.11.2026: "uygulama dəyişdirmək istədiyimdə
/// səhifə öz özünə hərəkət edir"): the app-switch swipe from the bottom edge
/// never reaches Flutter, so the page under it does not scroll.
void main() {
  final guard = File('web/pwa_guard.js').readAsStringSync();

  test('a touch that starts in the home-bar strip is kept from Flutter, start to end', () {
    expect(guard, contains('padding-bottom:env(safe-area-inset-bottom)'));
    expect(guard, contains('if (s <= 0) return false;'), reason: 'only on a phone with a home bar');
    expect(guard, contains('return y >= window.innerHeight - Math.max(12, s - 12);'),
        reason: 'below the floating bar (it stands safe-area − 12 above the edge)');
    for (final type in ['pointerdown', 'pointermove', 'pointerup', 'pointercancel', 'touchstart', 'touchmove', 'touchend', 'touchcancel']) {
      expect(guard, contains("'$type'"), reason: type);
    }
    expect(guard, contains("if (e.pointerType !== 'touch' || !inHomeBar(e.clientY)) return;"),
        reason: 'mouse / pen and every other touch untouched');
    final strip = guard.substring(guard.indexOf('// 6) The iPhone home bar'));
    expect(strip.contains('preventDefault'), isFalse, reason: 'iOS still switches apps');
    expect(strip, contains('}, true);'), reason: 'capture phase, before Flutter');
  });

  test('the guard runs before Flutter starts', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.indexOf('<script src="pwa_guard.js"></script>'), greaterThan(0));
    expect(html.indexOf('<script src="pwa_guard.js"></script>'), lessThan(html.indexOf('<script src="flutter_bootstrap.js"')));
  });
}

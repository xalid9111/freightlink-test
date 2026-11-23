import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The iPhone home bar (owner, 23.11.2026: "uygulama dəyişdirmək istədiyimdə
/// səhifə öz özünə hərəkət edir"; later "aşağıdan yuxarı sürüşdürüb səhifəni
/// qaldıranda yük kartları … hərəkətə başlayır"): the app-switch swipe from
/// the bottom edge never reaches Flutter, so the page under it does not
/// scroll; a plain tap there still works. Checked in Chromium (iPhone 13
/// emulation, real touch events): bottom-edge swipe = page still, swipes
/// higher up scroll, a tap on the bar's lower edge opens its tab.
void main() {
  final guard = File('web/pwa_guard.js').readAsStringSync();
  final strip = guard.substring(guard.indexOf('// 6) The iPhone home bar'));

  test('a fixed bottom strip (not the safe-area inset, which Flutter turns to 0)', () {
    expect(strip, contains('var HOME_STRIP = 28;'));
    expect(strip, contains('return y >= window.innerHeight - HOME_STRIP;'));
    expect(strip.contains('padding-bottom:env('), isFalse,
        reason: 'Flutter replaces the viewport tag without viewport-fit=cover → env() is 0');
  });

  test('a swipe that starts in the strip is kept from Flutter; a tap is handed over', () {
    expect(strip, contains("if (replaying || e.pointerType !== 'touch' || !inHomeBar(e.clientY)) return;"),
        reason: 'mouse / pen and every touch above the strip untouched');
    for (final type in ['pointerdown', 'pointermove', 'pointerup', 'pointercancel']) {
      expect(strip, contains("'$type'"), reason: type);
    }
    expect(strip, contains("if (type !== 'pointerup' || h.moved) return;"), reason: 'a moved touch is dropped');
    expect(strip, contains("t.dispatchEvent(new PointerEvent('pointerdown', h.down));"), reason: 'a tap still works');
    expect(strip.contains('preventDefault'), isFalse, reason: 'iOS / Android still switch apps');
    expect(strip, contains('}, true);'), reason: 'capture phase, before Flutter');
  });

  test('the guard runs before Flutter starts', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.indexOf('<script src="pwa_guard.js"></script>'), greaterThan(0));
    expect(html.indexOf('<script src="pwa_guard.js"></script>'), lessThan(html.indexOf('<script src="flutter_bootstrap.js"')));
  });
}

// A swipe always goes ONE STEP BACK, never forward (owner, 15.11.2026: "geri
// sürüşdürəndə arxadakı səhifəyə keçməlidir … ardıcıllıq bütün səhifələrdə").
// iPhone's Home Screen app took a swipe the other way as "forward" and
// reopened the page just left. web/pwa_guard.js stops such a forward step
// before Flutter sees it and goes one step back instead. (Checked in a real
// build: cargo → market → tirpark → cargo, back, back, forward = cargo.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final js = File('web/pwa_guard.js').readAsStringSync();

  test('a forward step is turned into one step back', () {
    expect(js, contains('if (next !== null && current !== null && next > current) {'));
    expect(js, contains('ev.stopImmediatePropagation();'));
    expect(js, contains('history.go(-(steps + (current > 0 ? 1 : 0)));'));
  });

  test('pages opened by a tap (pushState) are followed, not blocked', () {
    expect(js, contains("['pushState', 'replaceState'].forEach("));
    expect(js, contains('if (n !== null) current = n;'));
  });

  test('the guard runs before Flutter, so it is heard first', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html.indexOf('<script src="pwa_guard.js"></script>'), lessThan(html.indexOf('flutter_bootstrap.js" async')));
    expect(html.indexOf('<script src="pwa_guard.js"></script>'), greaterThan(0));
  });
}

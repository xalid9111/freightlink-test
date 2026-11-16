// Smart live map (owner, 16.11.2026, choice 1): a fast phone keeps the moving
// map as before; a slow one (measured on its first moving seconds) shows the
// movement for 5 s and then the map stands still (picture, routes, trucks and
// the lit "CANLI" stay), again a short show when the user comes back to the top.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('a fast phone (60 frames a second) keeps the moving map', () {
    final s = LiveMapSpeed();
    var made = false;
    for (var i = 0; i < 200 && !made; i++) {
      made = s.add(1 / 60);
    }
    expect(made, isTrue);
    expect(s.slow, isFalse);
  });

  test('a slow phone (5 frames a second) is told apart in 2 s', () {
    final s = LiveMapSpeed();
    var n = 0;
    while (!s.add(0.19)) {
      n++;
    }
    expect(s.slow, isTrue);
    expect(n * 0.19, lessThan(2.2));
    expect(s.add(0.01), isFalse, reason: 'measured once');
  });

  test('25 frames a second is the line', () {
    final fast = LiveMapSpeed();
    while (!fast.add(0.039)) {}
    expect(fast.slow, isFalse);
    final slow = LiveMapSpeed();
    while (!slow.add(0.045)) {}
    expect(slow.slow, isTrue);
  });

  test('a slow phone keeps a calm pace: about a third of its time, 1.25–8 moves a second', () {
    final slow = LiveMapSpeed();
    while (!slow.add(0.19)) {}
    expect(slow.calmEvery.inMilliseconds, inInclusiveRange(560, 580), reason: '3 × 0.19 s');
    final weak = LiveMapSpeed();
    while (!weak.add(0.045)) {}
    expect(weak.calmEvery.inMilliseconds, 135);
    final verySlow = LiveMapSpeed();
    while (!verySlow.add(0.5)) {}
    expect(verySlow.calmEvery.inMilliseconds, 800, reason: 'never slower than 1.25 a second');
  });

  test('wired: a slow phone moves calmly (never still while watched); out of view it rests', () {
    final m = src('lib/features/cargo/presentation/widgets/live_map.dart');
    expect(m, contains('if (_speed.slow == true) return _startCalm();'));
    expect(m, contains('_calm = Timer.periodic(every, (_) {'));
    expect(m, contains('_advance(step, trucks: _liteTrucks);'));
    expect(m, isNot(contains('_stillIn(')), reason: 'no more standing still after a show');
    expect(m, contains("duration: const Duration(milliseconds: 1100), value: 1);"), reason: 'lit until it moves');
    expect(m, contains('..value = 1;'), reason: 'resting = lit');
    expect(m, contains('if (StartupSteps.isFree(2)) _move();'));
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/marquee_text.dart';

/// The chat's "son görülmə …" line glides when it does not fit (owner,
/// 22.11.2026: "axıcı olsun və avtomatik sürüşərək geridə qalan qismi
/// görünsün").
Widget _box(String text, double width, {bool reduce = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, 200), disableAnimations: reduce),
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: MarqueeText(text, style: const TextStyle(fontSize: 12)))),
        ),
      ),
    );

void main() {
  const long = 'son görülmə: dünən 23:58 · çox uzun yazı';

  testWidgets('a text that fits stands still (no scroller)', (t) async {
    await t.pumpWidget(_box('online', 300));
    expect(find.byKey(const ValueKey('marquee-box')), findsNothing);
    expect(find.text('online'), findsOneWidget);
  });

  testWidgets('a long text glides to its end, rests and glides back', (t) async {
    await t.pumpWidget(_box(long, 80));
    expect(find.byKey(const ValueKey('marquee-box')), findsOneWidget);
    double dx() => t.widget<Transform>(find.byKey(const ValueKey('marquee-move'))).transform.getTranslation().x;
    final full = t.getSize(find.text(long)).width;
    expect(dx(), 0);
    await t.pump(kMarqueePause + const Duration(milliseconds: 50));
    await t.pump(const Duration(seconds: 30)); // the whole glide
    expect(dx(), closeTo(-(full - 80), 0.5), reason: 'at the end: the hidden part is shown');
    await t.pump(kMarqueePause + const Duration(milliseconds: 50));
    await t.pump(const Duration(seconds: 30));
    expect(dx(), closeTo(0, 0.5), reason: 'back at the start');
    await t.pumpWidget(const SizedBox()); // stops the loop
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('phones asking for less motion get the plain ellipsis', (t) async {
    await t.pumpWidget(_box(long, 80, reduce: true));
    expect(find.byKey(const ValueKey('marquee-box')), findsNothing);
    expect(t.widget<Text>(find.text(long)).overflow, TextOverflow.ellipsis);
  });

  test('glide time: pixels / speed, at least 0.6 s', () {
    expect(marqueeGlide(0, 28), Duration.zero);
    expect(marqueeGlide(5, 28), const Duration(milliseconds: 600));
    expect(marqueeGlide(56, 28), const Duration(seconds: 2));
  });

  test('the chat header uses it for the last-seen line', () {
    final src = File('lib/features/chat/presentation/conversation_thread_screen.dart').readAsStringSync();
    expect(src, contains("MarqueeText(\n                            key: const ValueKey('chat-last-seen'),"));
  });
}

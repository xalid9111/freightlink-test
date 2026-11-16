// Chats (owner, 16.11.2026): a link in a message opens with a tap; older
// messages stay in the archive and load by themselves while scrolling up; the
// ⌄ button brings the chat back to the newest message.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/chat/presentation/widgets/chat_scroll.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  group('links in a message', () {
    test('http(s) and www links are found, the rest stays text', () {
      final p = splitLinks('Bax https://pin.it/1Be6D47yD, və www.tirlink.app.');
      expect(p.map((e) => e.$1).toList(), ['Bax ', 'https://pin.it/1Be6D47yD', ', və ', 'www.tirlink.app', '.']);
      expect(p[1].$2.toString(), 'https://pin.it/1Be6D47yD');
      expect(p[3].$2.toString(), 'https://www.tirlink.app');
      expect(p[0].$2, isNull);
    });

    test('a bare link, a link in brackets and no link', () {
      expect(splitLinks('https://pin.it/1Be6D47yD').single.$2.toString(), 'https://pin.it/1Be6D47yD');
      expect(splitLinks('(http://x.az/a?b=1)').map((e) => e.$1).toList(), ['(', 'http://x.az/a?b=1', ')']);
      expect(splitLinks('salam necəsən').single.$2, isNull);
    });

    test('never anything but http / https', () {
      for (final t in ['javascript:alert(1)', 'data:text/html,x', 'file:///etc/passwd', 'tel:+994']) {
        expect(splitLinks(t).every((e) => e.$2 == null), isTrue, reason: t);
      }
    });

    testWidgets('the link part is tappable and underlined, plain text is a plain Text', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(children: [
            LinkifiedText('bax https://pin.it/x', key: ValueKey('a'), style: TextStyle(color: Colors.white)),
            LinkifiedText('salam', key: ValueKey('b'), style: TextStyle(color: Colors.white)),
          ]),
        ),
      ));
      final rich =
          t.widget<RichText>(find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byType(RichText)));
      final spans = <TextSpan>[];
      rich.text.visitChildren((s) {
        if (s is TextSpan && s.text != null) spans.add(s);
        return true;
      });
      final link = spans.firstWhere((s) => s.text == 'https://pin.it/x');
      expect(link.recognizer, isA<TapGestureRecognizer>());
      expect(link.style!.decoration, TextDecoration.underline);
      expect(spans.firstWhere((s) => s.text == 'bax ').recognizer, isNull);
      expect(find.text('salam'), findsOneWidget);
    });

    test('both chat screens show message text through LinkifiedText', () {
      expect(src('lib/features/chat/presentation/conversation_thread_screen.dart'),
          contains('LinkifiedText(\n                message.message!,'));
      expect(src('lib/features/chat/presentation/group_thread_screen.dart'), contains('LinkifiedText(text!,'));
      expect(src('lib/features/chat/presentation/widgets/chat_scroll.dart'),
          contains('mode: LaunchMode.externalApplication'));
    });
  });

  group('older messages and the ⌄ button', () {
    test('only messages after the newest seen one count as new', () {
      expect(unseenAfter(['a', 'b', 'c'], {'a', 'b', 'c'}), 0);
      expect(unseenAfter(['a', 'b', 'c', 'd', 'e'], {'a', 'b', 'c'}), 2);
      // Older messages loaded later never count.
      expect(unseenAfter(['o1', 'o2', 'a', 'b', 'c'], {'a', 'b', 'c'}), 0);
      expect(unseenAfter(const [], const {}), 0);
    });

    testWidgets('the older part is asked for as soon as the loader row is built', (t) async {
      var asked = 0;
      await t.pumpWidget(MaterialApp(home: Scaffold(body: ChatOlderLoader(onLoad: () => asked++))));
      await t.pump();
      expect(asked, 1);
    });

    Widget chat(ScrollController c, List<String> incoming) => MaterialApp(
          home: Scaffold(
            body: ChatJumpToLatest(
              controller: c,
              incoming: incoming,
              tooltip: 'Son mesaja qayıt',
              child: ListView.builder(
                controller: c,
                reverse: true,
                itemCount: 200,
                itemBuilder: (_, i) => SizedBox(height: 60, child: Text('m$i')),
              ),
            ),
          ),
        );

    testWidgets('scrolled up: ⌄ shows, counts new messages, a tap goes back to the newest', (t) async {
      final c = ScrollController();
      final ids = [for (var i = 0; i < 10; i++) 'x$i'];
      await t.pumpWidget(chat(c, ids));
      double opacity() => t
          .widget<AnimatedOpacity>(
              find.ancestor(of: find.byKey(const ValueKey('chat-jump-latest')), matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(), 0, reason: 'at the newest message: no button');

      c.jumpTo(4000);
      await t.pumpAndSettle();
      expect(opacity(), 1);
      expect(find.byKey(const ValueKey('chat-jump-count')), findsNothing);

      // Two new messages arrive while reading further up.
      await t.pumpWidget(chat(c, [...ids, 'n1', 'n2']));
      await t.pumpAndSettle();
      expect(
          find.descendant(of: find.byKey(const ValueKey('chat-jump-count')), matching: find.text('2')), findsOneWidget);
      expect(c.offset, 4000, reason: 'the view is not thrown down');

      await t.tap(find.byKey(const ValueKey('chat-jump-latest')));
      await t.pumpAndSettle();
      expect(c.offset, 0);
      expect(find.text('m0'), findsOneWidget);
      expect(opacity(), 0);
      expect(find.byKey(const ValueKey('chat-jump-count')), findsNothing);
    });

    test('both chat screens: paged, the loader row, the ⌄ button', () {
      final one = src('lib/features/chat/presentation/conversation_thread_screen.dart');
      expect(one, contains("ChatOlderLoader(key: const ValueKey('chat-load-older'), onLoad: _loadOlder)"));
      expect(one, contains('ChatJumpToLatest('));
      expect(one, contains('if (_loadingOlder || !mounted) return;'));
      final grp = src('lib/features/chat/presentation/group_thread_screen.dart');
      expect(grp, contains('groupMessagesProvider((widget.groupId, _pageLimit))'));
      expect(grp, contains("ChatOlderLoader(key: const ValueKey('chat-load-older'), onLoad: _loadOlder)"));
      expect(grp, contains('ChatJumpToLatest('));
      expect(src('lib/features/chat/data/group_repository.dart'),
          contains(".order('created_at', ascending: false)\n      .limit(limit)"));
    });
  });
}

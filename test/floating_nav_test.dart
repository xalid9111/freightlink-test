// Floating capsule bottom bar (owner's picture, 08.11.2026): rounded,
// see-through, ~0.5 cm above the bottom edge with side gaps; the five tabs
// in one row on any phone; the selected tab a bit bigger in the accent
// colour; pages never hidden under it; sheets / dialogs make it step aside.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/router/floating_nav.dart';
import 'package:freightlink/core/theme/app_theme.dart';

String src(String p) => File(p).readAsStringSync();

const _items = [
  FloatingNavItem(0, Icons.local_shipping_outlined, Icons.local_shipping, 'Yüklər'),
  FloatingNavItem(5, Icons.place_outlined, Icons.place, 'TIRPark'),
  FloatingNavItem(6, Icons.storefront_outlined, Icons.storefront, 'TIR Bazarı'),
  FloatingNavItem(3, Icons.chat_bubble_outline, Icons.chat_bubble, 'Mesajlar', badge: 3),
  FloatingNavItem(4, Icons.person_outline, Icons.person, 'Profil'),
];

Future<List<int>> _pumpBar(WidgetTester tester, double width, {bool hidden = false}) async {
  final taps = <int>[];
  tester.view.physicalSize = Size(width * 3, 700 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: const SizedBox.expand(),
      bottomNavigationBar: FloatingNavBar(items: _items, current: 0, onTap: taps.add, hidden: hidden),
    ),
  ));
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  for (final width in [320.0, 375.0, 430.0]) {
    testWidgets('capsule at ${width.toInt()} pt: floating, side gaps, five tabs in one row, no overflow', (tester) async {
      final taps = await _pumpBar(tester, width);
      expect(tester.takeException(), isNull);
      final cap = tester.getRect(find.byKey(const ValueKey('floating-nav')));
      expect(cap.height, FloatingNav.height);
      expect(cap.left, FloatingNav.sideGap);
      expect(width - cap.right, FloatingNav.sideGap);
      expect(700 - cap.bottom, greaterThanOrEqualTo(FloatingNav.edgeGap), reason: 'about 0.5 cm above the bottom edge');
      // One row, the same line, in order.
      final rects = [for (final b in [0, 5, 6, 3, 4]) tester.getRect(find.byKey(ValueKey('nav-$b')))];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, rects[0].top);
        expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right - 0.01), reason: 'no overlap');
      }
      for (final label in ['Yüklər', 'TIRPark', 'TIR Bazarı', 'Mesajlar', 'Profil']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('nav-6')));
      expect(taps, [6], reason: 'the tabs still switch');
    });
  }

  testWidgets('selected tab: bigger icon in the accent colour; rounded see-through glass', (tester) async {
    await _pumpBar(tester, 390);
    final on = tester.widget<Icon>(find.byIcon(Icons.local_shipping));
    final off = tester.widget<Icon>(find.byIcon(Icons.place_outlined));
    expect(on.size, greaterThan(off.size!));
    expect(on.color, AppColors.accent);
    expect(off.color, AppColors.textSoft);
    expect(find.text('3'), findsOneWidget, reason: 'the unread badge stays');
    expect(find.byType(BackdropFilter), findsOneWidget);
    final glass = tester.widget<Container>(find.descendant(of: find.byKey(const ValueKey('floating-nav')), matching: find.byType(Container)).first);
    final deco = glass.decoration! as BoxDecoration;
    expect(deco.color!.a, lessThan(1), reason: 'see-through');
    expect(deco.borderRadius, BorderRadius.circular(FloatingNav.height / 2));
  });

  testWidgets('a sheet / dialog open: the capsule steps aside and takes no taps', (tester) async {
    final taps = await _pumpBar(tester, 390, hidden: true);
    await tester.tap(find.byKey(const ValueKey('nav-6')), warnIfMissed: false);
    expect(taps, isEmpty);
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
  });

  testWidgets('pages: NavRoom ends above the capsule; NavRoom.behind runs under it with the room as safe area', (tester) async {
    late double plainHeight, behindPad, plainPad;
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 800), padding: EdgeInsets.only(bottom: 34), viewPadding: EdgeInsets.only(bottom: 34)),
        child: FloatingNavScope(
          space: FloatingNav.space(34),
          child: Row(children: [
            Expanded(child: NavRoom(child: LayoutBuilder(builder: (c, box) {
              plainHeight = box.maxHeight;
              plainPad = MediaQuery.paddingOf(c).bottom;
              return const SizedBox.expand();
            }))),
            Expanded(child: NavRoom.behind(child: Builder(builder: (c) {
              behindPad = MediaQuery.paddingOf(c).bottom;
              return const SizedBox.expand();
            }))),
          ]),
        ),
      ),
    ));
    final room = FloatingNav.space(34) + FloatingNav.contentGap;
    expect(plainHeight, 600 - room, reason: 'the test screen is 600 pt tall');
    expect(plainPad, 0, reason: 'the safe area is taken by the capsule');
    expect(behindPad, room);
  });

  testWidgets('no capsule (computer, keyboard open): pages unchanged', (tester) async {
    late double h;
    await tester.pumpWidget(MaterialApp(
      home: FloatingNavScope(space: 0, child: NavRoom(child: LayoutBuilder(builder: (c, box) {
        h = box.maxHeight;
        return const SizedBox.expand();
      }))),
    ));
    expect(h, 600);
  });

  testWidgets('overlay counter: sheets, dialogs and pushed editors count; router pages do not', (tester) async {
    ShellOverlayObserver.open.value = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [ShellOverlayObserver()],
      home: const SizedBox(),
    ));
    expect(ShellOverlayObserver.open.value, 1, reason: 'a route pushed without a Page (here: home)');
    ShellOverlayObserver.open.value = 0;
    showModalBottomSheet<void>(context: nav.currentContext!, builder: (_) => const SizedBox(height: 100));
    await tester.pumpAndSettle();
    expect(ShellOverlayObserver.open.value, 1);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ShellOverlayObserver.open.value, 0);
    showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('x')));
    await tester.pumpAndSettle();
    expect(ShellOverlayObserver.open.value, 1);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(ShellOverlayObserver.open.value, 0);
    expect(ShellOverlayObserver.counts(const MaterialPage<void>(child: SizedBox()).createRoute(nav.currentContext!)), isFalse);
  });

  test('wired: the shell, every tab page and the lists that run under the capsule', () {
    final shell = src('lib/core/router/main_shell.dart');
    expect(shell, contains('extendBody: true,'));
    expect(shell, contains('bottomNavigationBar: keyboard\n            ? null'));
    expect(shell, contains('hidden: open > 0,'));
    expect(shell, contains('if (isDesktopLayout(context))'), reason: 'the computer keeps its sidebar');
    final r = src('lib/core/router/app_router.dart');
    final shellPart = r.substring(r.indexOf('StatefulShellRoute.indexedStack('));
    expect('StatefulShellBranch(observers: [ShellOverlayObserver()], routes: ['.allMatches(shellPart).length, 7);
    expect('StatefulShellBranch(routes: ['.allMatches(shellPart).length, 0);
    // Every page of a tab makes room for the capsule.
    final builders = RegExp(r'builder: \(context, state\) => (.*)').allMatches(shellPart).map((m) => m.group(1)!).toList();
    for (final b in builders) {
      if (b.contains('NewGroupScreen')) continue; // opens over everything (root navigator)
      expect(b.startsWith('NavRoom') || b.startsWith('const NavRoom'), isTrue, reason: b);
    }
    for (final s in ['CargoMarketplaceScreen()', 'ConversationsScreen()', 'ProfileScreen()', 'DeferredPage(load: market.loadLibrary, builder: (_) => market.MarketHomeScreen())']) {
      expect(shellPart, contains('NavRoom.behind(child: $s)'), reason: s);
    }
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart'), contains('math.max(96, MediaQuery.paddingOf(context).bottom + 16)'));
    expect(src('lib/features/chat/presentation/conversations_screen.dart'), contains('14 + MediaQuery.paddingOf(context).bottom'));
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains('32 + MediaQuery.paddingOf(context).bottom'));
    expect(src('lib/features/market/presentation/market_home_screen.dart'), contains('SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)'));
  });
}

// Safari navigation + Home Screen PWA freeze fixes (2026-10-13).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/router/safe_navigation.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('One tap = one navigation (NavDebounce)', () {
    test('a second push to the same page right away is dropped', () {
      final g = NavDebounce();
      final t0 = DateTime(2026, 10, 13, 12);
      expect(g.allow('/load/1', t0), isTrue);
      expect(g.allow('/load/1', t0.add(const Duration(milliseconds: 120))), isFalse);
    });
    test('a different page is never blocked', () {
      final g = NavDebounce();
      final t0 = DateTime(2026, 10, 13, 12);
      expect(g.allow('/load/1', t0), isTrue);
      expect(g.allow('/user/2', t0.add(const Duration(milliseconds: 50))), isTrue);
    });
    test('the same page again later is allowed', () {
      final g = NavDebounce();
      final t0 = DateTime(2026, 10, 13, 12);
      expect(g.allow('/load/1', t0), isTrue);
      expect(g.allow('/load/1', t0.add(const Duration(seconds: 1))), isTrue);
    });
  });

  group('Navigation wiring', () {
    test('no direct context.push( left in screens (all go through pushOnce)', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('safe_navigation.dart'))
          .where((f) => f.readAsStringSync().contains('context.push('))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty);
    });
    test('bottom bar: each tab tap is debounced', () {
      expect(_read('lib/core/router/main_shell.dart').contains("_tabGuard.allow('tab:"), isTrue);
    });
    test('router is not refreshed by token refreshes', () {
      expect(_read('lib/core/router/app_router.dart').contains('AuthChangeEvent.tokenRefreshed'), isTrue);
    });
    test('browser back/forward is not animated twice', () {
      expect(_read('lib/core/theme/app_theme.dart').contains('recentBrowserNavigation()'), isTrue);
    });
  });

  group('PWA freeze guards', () {
    test('pwa_guard.js loads before Flutter', () {
      final index = _read('web/index.html');
      final guard = index.indexOf('src="pwa_guard.js"');
      expect(guard, greaterThan(0));
      expect(index.indexOf('src="flutter_bootstrap.js"'), greaterThan(guard));
    });
    test('old service workers are removed, user storage untouched', () {
      final guard = _read('web/pwa_guard.js');
      expect(guard.contains('unregister'), isTrue);
      expect(guard.contains('localStorage.'), isFalse);
      final sw = _read('web/flutter_service_worker.js');
      expect(sw.contains('unregister'), isTrue);
      expect(sw.contains('localStorage.'), isFalse);
    });
    test('presence does not rebuild the whole shell', () {
      final shell = _read('lib/core/router/main_shell.dart');
      expect(shell.contains('ref.watch(onlineUsersProvider)'), isFalse);
      expect(shell.contains('ref.listen(onlineUsersProvider'), isTrue);
    });
    test('one shared subscription for received messages', () {
      final p = _read('lib/features/chat/presentation/providers/chat_providers.dart');
      expect('watchReceived('.allMatches(p).length, 1);
      expect(p.contains('StreamProvider.autoDispose.family<List<MessageModel>, String>'), isTrue);
    });
  });
}

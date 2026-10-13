// AutoFix pure logic — runs in GitHub Actions (flutter test).
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/autofix/autofix_logic.dart';

void main() {
  group('classifyError', () {
    test('expired session → auth, transient', () {
      final i = classifyError('PostgrestException', 'PostgrestException(message: JWT expired, code: PGRST301, details: , hint: null)');
      expect(i.kind, AutoFixKind.auth);
      expect(i.code, 'PGRST301');
      expect(i.transient, isTrue);
    });

    test('Failed to fetch → network, transient', () {
      final i = classifyError('ClientException', 'ClientException: XMLHttpRequest error., uri=https://x.supabase.co/rest/v1/cargo');
      expect(i.kind, AutoFixKind.network);
      expect(i.transient, isTrue);
    });

    test('permission error → api, NOT transient (no blind retry)', () {
      final i = classifyError('PostgrestException', 'PostgrestException(message: permission denied for table x, code: 42501, details: null, hint: null)');
      expect(i.kind, AutoFixKind.api);
      expect(i.code, '42501');
      expect(i.transient, isFalse);
    });

    test('server 5xx → api, transient', () {
      final i = classifyError('PostgrestException', 'PostgrestException(message: upstream error 500, code: PGRST000, details: null, hint: null)');
      expect(i.kind, AutoFixKind.api);
      expect(i.transient, isTrue);
    });

    test('chat stream error → messaging', () {
      final i = classifyError('RealtimeSubscribeException', 'RealtimeSubscribeException(status: channelError)', messaging: true);
      expect(i.kind, AutoFixKind.messaging);
      expect(i.transient, isTrue);
    });

    test('word ERROR in a text is not taken as a database code', () {
      final i = classifyError('StateError', 'Bad state: ERROR in widget');
      expect(i.kind, AutoFixKind.runtime);
      expect(i.transient, isFalse);
    });

    test('code bug → runtime, not transient (manual fix)', () {
      final i = classifyError('_TypeError', "Null check operator used on a null value");
      expect(i.kind, AutoFixKind.runtime);
      expect(i.transient, isFalse);
      expect(autofixActionFor(i.kind), isNull);
    });

    test('unknown route → navigation', () {
      final i = classifyError('GoException', 'GoException: no routes for location: /abc');
      expect(i.kind, AutoFixKind.navigation);
    });
  });

  group('recovery table', () {
    test('only safe kinds have an action', () {
      expect(autofixActionFor(AutoFixKind.messaging), 'reconnect');
      expect(autofixActionFor(AutoFixKind.network), 'refresh_data');
      expect(autofixActionFor(AutoFixKind.api), 'refresh_data');
      expect(autofixActionFor(AutoFixKind.auth), 'refresh_data');
      expect(autofixActionFor(AutoFixKind.freeze), 'reload_when_idle');
      expect(autofixActionFor(AutoFixKind.runtime), isNull);
      expect(autofixActionFor(AutoFixKind.navigation), isNull);
    });
  });

  group('parseAppFrame', () {
    test('finds the first app frame with line', () {
      const stack = '#0      Foo.bar (package:flutter/src/widgets/framework.dart:12:3)\n'
          '#1      _CargoCardState.build (package:freightlink/features/cargo/presentation/widgets/cargo_card.dart:141:7)';
      final loc = parseAppFrame(stack)!;
      expect(loc.file, 'lib/features/cargo/presentation/widgets/cargo_card.dart');
      expect(loc.line, 141);
    });

    test('minified release stack → null', () {
      expect(parseAppFrame('at a.b (main.dart.js:1:23456)\nat c.d (main.dart.js:1:999)'), isNull);
    });
  });

  test('screenFileForRoute picks the most specific screen', () {
    expect(screenFileForRoute('/messages/with/abc'), 'lib/features/chat/presentation/conversation_thread_screen.dart');
    expect(screenFileForRoute('/messages'), 'lib/features/chat/presentation/conversations_screen.dart');
    expect(screenFileForRoute('/cargo/create'), 'lib/features/cargo/presentation/cargo_create_screen.dart');
    expect(screenFileForRoute('/cargo'), 'lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(screenFileForRoute('/nowhere'), isNull);
  });

  group('fingerprintFor', () {
    test('same problem with different ids → same fingerprint', () {
      final a = fingerprintFor('api', 'PGRST301', 'JWT expired at 12:00 for 1234', route: '/cargo/5');
      final b = fingerprintFor('api', 'PGRST301', 'JWT expired at 13:45 for 9876', route: '/cargo/7');
      expect(a, b);
    });

    test('only server-accepted characters, max 120', () {
      final fp = fingerprintFor('runtime', 'Ünïcode Error!!', 'x' * 500, route: '/user/ab');
      expect(RegExp(r'^[0-9a-z_:.-]{4,120}$').hasMatch(fp), isTrue);
    });
  });

  group('RetryLimiter', () {
    test('max attempts per window, then free again', () {
      var now = DateTime(2026, 1, 1, 12);
      final l = RetryLimiter(max: 2, window: const Duration(minutes: 2), now: () => now);
      expect(l.tryAcquire('k'), isTrue);
      expect(l.tryAcquire('k'), isTrue);
      expect(l.tryAcquire('k'), isFalse);
      expect(l.attempts('k'), 2);
      now = now.add(const Duration(minutes: 3));
      expect(l.tryAcquire('k'), isTrue);
    });
  });

  test('backoff grows and is capped', () {
    expect(backoffFor(1), const Duration(seconds: 3));
    expect(backoffFor(2), const Duration(seconds: 10));
    expect(backoffFor(9), const Duration(seconds: 30));
  });

  test('freeze threshold', () {
    expect(isFreeze(const Duration(seconds: 2), const Duration(seconds: 3)), isFalse);
    expect(isFreeze(const Duration(seconds: 2), const Duration(seconds: 7)), isTrue);
  });
}

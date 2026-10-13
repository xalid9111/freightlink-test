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

    test('same Flutter error on different objects → same fingerprint', () {
      // Live case: "RenderBox was not laid out: minified:a8G#78ac7" and
      // "…#4cf48" were two groups for one bug.
      final a = fingerprintFor('runtime', 'minified:hF', 'Bad state: RenderBox was not laid out: minified:a8G#78ac7',
          route: '/profile');
      final b = fingerprintFor('runtime', 'minified:hF', 'Bad state: RenderBox was not laid out: minified:a8G#4cf48',
          route: '/profile');
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

  group('diagnostics: no personal data', () {
    test('e-mail, phones, tokens and query strings are removed', () {
      final out = scrubPii('user a.b@mail.az phone +994 50 123 45 67 / 050 123 45 67 / 0501234567 '
          'key eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig sb_publishable_AbC123 url /cargo?q=Ali');
      expect(out, isNot(contains('a.b@mail.az')));
      expect(out, isNot(contains('123 45 67')));
      expect(out, isNot(contains('0501234567')));
      expect(out, isNot(contains('eyJhbGci')));
      expect(out, isNot(contains('AbC123')));
      expect(out, isNot(contains('q=Ali')));
    });

    test('stack positions, dates, times and error codes stay readable', () {
      const s = 'at A.mx.bj (main.dart.js:97069:13) 2026-10-13 13:29:05 code 42501 RenderFoo#78ac7';
      expect(scrubPii(s), s);
    });

    test('ids in routes are masked, query dropped', () {
      expect(maskRoute('/user/1b2c3d4e-1111-2222-3333-444455556666?tab=x'), '/user/:id');
      expect(maskRoute('/messages/with/1b2c3d4e-1111-2222-3333-444455556666'), '/messages/with/:id');
      expect(maskRoute('/cargo/42'), '/cargo/:id');
      expect(maskRoute('/profile'), '/profile');
    });
  });

  group('diagnostics: breadcrumbs', () {
    test('keeps only the last 10 steps', () {
      final b = Breadcrumbs(max: 10);
      for (var i = 0; i < 15; i++) {
        b.add('12:00:0${i % 10}', 'step $i');
      }
      final lines = b.toString().split('\n');
      expect(lines.length, 10);
      expect(lines.first, endsWith('step 5'));
      expect(lines.last, endsWith('step 14'));
    });

    test('a step repeated right away is kept once with a counter', () {
      final b = Breadcrumbs(max: 10)
        ..add('12:00:00', '→ /profile')
        ..add('12:00:01', '✖ runtime minified:hF')
        ..add('12:00:01', '✖ runtime minified:hF')
        ..add('12:00:02', '✖ runtime minified:hF');
      expect(b.toString(), '12:00:00 → /profile\n12:00:01 ✖ runtime minified:hF ×3');
    });

    test('personal data in a step is removed', () {
      final b = Breadcrumbs()..add('12:00:00', 'error for a@b.az');
      expect(b.toString(), isNot(contains('a@b.az')));
    });
  });

  group('diagnostics: device and screen', () {
    test('tap position is a zone and percent, nothing from the screen', () {
      expect(tapLabel(360, 30, 390, 844), 'tap ↗ 92%,4%');
      expect(tapLabel(195, 800, 390, 844), 'tap ↓ 50%,95%');
      expect(tapLabel(10, 422, 390, 844, swipe: true), 'swipe ← 3%,50%');
      expect(tapLabel(5, 5, 0, 0), 'tap');
    });

    test('device line: screen, ratio, pwa, language, then user agent (max 300)', () {
      final d = deviceSummary(
          width: 390, height: 844, pixelRatio: 3, standalone: true, language: 'az', userAgent: 'UA ' * 200);
      expect(d, startsWith('390×844 @3.0 · pwa · az | UA'));
      expect(d.length, lessThanOrEqualTo(300));
    });

    test('stack starts with what Flutter was doing, max 4000', () {
      final s = stackForReport('x' * 5000, context: 'during performLayout() · rendering library');
      expect(s, startsWith('context: during performLayout() · rendering library\n'));
      expect(s.length, 4000);
      expect(stackForReport('trace'), 'trace');
    });
  });
}

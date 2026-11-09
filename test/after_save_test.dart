// Back after a save (owner, 09.11.2026): the form stays until the server
// has answered; after a successful answer a short notice and back to the
// page it was opened from; opened from a link — the section's main page; a
// failure never leaves; a double tap never saves twice.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/router/after_save.dart';
import 'package:go_router/go_router.dart';

String src(String p) => File(p).readAsStringSync();

GoRouter _router(String initial) => GoRouter(initialLocation: initial, routes: [
      GoRoute(path: '/list', builder: (_, __) => const Scaffold(body: Text('LIST'))),
      GoRoute(path: '/item', builder: (_, __) => const Scaffold(body: Text('ITEM'))),
      GoRoute(
        path: '/form',
        builder: (context, _) => Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => leaveAfterSave(c, fallback: '/list', notice: 'Saxlandı'),
              child: const Text('SAVE'),
            ),
          ),
        ),
      ),
    ]);

void main() {
  testWidgets('opened from a page: back to that page, with the notice', (t) async {
    final r = _router('/item');
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    r.push('/form');
    await t.pumpAndSettle();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(find.text('ITEM'), findsOneWidget, reason: 'the page it was opened from, not the fallback');
    expect(r.routerDelegate.currentConfiguration.uri.path, '/item');
    expect(find.text('Saxlandı'), findsOneWidget);
  });

  testWidgets('opened from a link (no history): the section main page', (t) async {
    final r = _router('/form');
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    await t.pumpAndSettle();
    await t.tap(find.text('SAVE'));
    await t.pumpAndSettle();
    expect(find.text('LIST'), findsOneWidget);
    expect(r.routerDelegate.currentConfiguration.uri.path, '/list');
  });

  test('wired in every add / edit form: back only after the server said yes, never twice', () {
    const forms = {
      'lib/features/cargo/presentation/cargo_quick_form.dart': "leaveAfterSave(context, fallback: '/cargo/\$id'",
      'lib/features/market/presentation/market_edit_screen.dart': 'leaveAfterSave(context,',
      'lib/features/services/presentation/service_edit_screen.dart': "leaveAfterSave(context, fallback: '/service/\${saved.id}'",
      'lib/features/jobs/presentation/job_seeker_form.dart': "leaveAfterSave(context, fallback: '/jobs'",
      'lib/features/jobs/presentation/job_vacancy_form.dart': "leaveAfterSave(context, fallback: '/jobs'",
      'lib/features/auth/presentation/profile_screen.dart': "leaveAfterSave(context, fallback: '/profile'",
      'lib/features/auth/presentation/change_password_screen.dart': "leaveAfterSave(context, fallback: '/settings')",
      'lib/features/tirpark/presentation/tir_park_manage.dart': "leaveAfterSave(context, fallback: '/tirpark/manage'",
      'lib/features/ads/presentation/ad_create_screen.dart': "leaveAfterSave(context, fallback: '/ads')",
    };
    forms.forEach((file, call) {
      final f = src(file);
      expect(f, contains(call), reason: file);
      expect(f, isNot(contains('maybePop()')), reason: '$file: a form opened from a link must not stay open');
    });
    // A double tap never saves twice.
    expect(src('lib/features/cargo/presentation/cargo_quick_form.dart'), contains('if (_submitting || _left) return;'));
    expect(src('lib/features/market/presentation/market_edit_screen.dart'), contains('if (_busy || _left) return;'));
    expect(src('lib/features/services/presentation/service_edit_screen.dart'), contains('if (_saving || _left) return;'));
    expect(src('lib/features/jobs/presentation/job_seeker_form.dart'), contains('if (_saving || _left) return;'));
    expect(src('lib/features/jobs/presentation/job_vacancy_form.dart'), contains('if (_saving || _left) return;'));
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains('if (_savingName || _left) return;'));
    expect(src('lib/features/ads/presentation/ad_create_screen.dart'), contains('if (_busy) return; // a double tap'));
    expect('if (_busy) return; // a double tap'.allMatches(src('lib/features/tirpark/presentation/tir_park_manage.dart')).length, 4);
    // A new item still goes straight to its section list.
    expect(src('lib/features/cargo/presentation/cargo_quick_form.dart'), contains("context.go('/cargo');"));
    expect(src('lib/features/market/presentation/market_edit_screen.dart'), contains("context.go('/market');"));
    expect(src('lib/features/services/presentation/service_edit_screen.dart'), contains("context.go(_shopForm ? '/services?shops=1' : '/services');"));
    // An edited service no longer leaves a second copy of its page behind.
    expect(src('lib/features/services/presentation/service_edit_screen.dart'), isNot(contains("context.pushReplacement('/service/\${saved.id}')")));
  });
}

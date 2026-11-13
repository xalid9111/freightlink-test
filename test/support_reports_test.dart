// "Təklif və iradlar", "Problem bildir" and the admins' Bildirişlər (owner,
// 13.11.2026, SQL 0120); the reset-password e-mail link (token_hash).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/finance/presentation/finance_providers.dart';
import 'package:freightlink/features/support/support.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _FakeRepo extends SupportRepository {
  final sent = <(SupportKind, String, String?)>[];
  final statuses = <(String, String)>[];
  @override
  Future<void> submit(SupportKind kind, String message, {String? paymentId}) async => sent.add((kind, message.trim(), paymentId));
  @override
  Future<void> setStatus(String id, String status, {String? note}) async => statuses.add((id, status));
  @override
  Future<int> openCount() async => 0;
}

Widget _app(Widget home, _FakeRepo repo, {List<Override> extra = const []}) {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (c, s) => const Scaffold(body: Text('home'))),
    GoRoute(path: '/form', builder: (c, s) => home),
    GoRoute(path: '/profile', builder: (c, s) => const Scaffold(body: Text('profile'))),
  ], initialLocation: '/');
  return ProviderScope(
    key: UniqueKey(),
    overrides: [stringsProvider.overrideWithValue(_az), supportRepositoryProvider.overrideWithValue(repo), ...extra],
    child: Builder(builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) => router.push('/form'));
      return MaterialApp.router(routerConfig: router);
    }),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting());
  test('the server row becomes a card', () {
    final r = SupportReport.fromJson({
      'id': 'r1',
      'kind': 'auto_payment',
      'problem': 'not_applied',
      'status': 'new',
      'created_at': '2026-11-13T10:00:00Z',
      'amount': 5,
      'currency': 'AZN',
      'payment_status': 'succeeded',
      'order_kind': 'market_vip',
      'payment_id': 'p1',
    });
    expect(r.titleKey, 'sup_problem_not_applied');
    expect((r.amount, r.orderKind, r.paymentStatus), (5.0, 'market_vip', 'succeeded'));
    expect(SupportReport.fromJson({'id': 'x', 'kind': 'feedback', 'created_at': null}).titleKey, 'sup_kind_feedback');
    expect(supportKindOf('promo'), SupportKind.promo);
    expect(supportKindOf('auto_payment'), SupportKind.feedback, reason: 'users never send the server\'s own kind');
    expect(supportErrorKey(Exception('too_many')), 'sup_err_too_many');
    expect(supportErrorKey(const SupportNotReady()), 'sup_not_ready');
  });

  testWidgets('Təklif və iradlar: choose the kind, write, Göndər → "Təşəkkürlər! …" and back', (t) async {
    final repo = _FakeRepo();
    await t.pumpWidget(_app(const SupportFormScreen(), repo));
    await t.pumpAndSettle();
    expect(find.text('Təklif və iradlar'), findsOneWidget);
    for (final k in SupportKind.values) {
      expect(find.byKey(ValueKey('sup-kind-${k.name}')), findsOneWidget);
    }
    await t.tap(find.byKey(const ValueKey('sup-send')));
    await t.pump();
    expect(find.byKey(const ValueKey('sup-error')), findsOneWidget, reason: 'an empty text is not sent');
    expect(repo.sent, isEmpty);
    await t.tap(find.byKey(const ValueKey('sup-kind-promo')));
    await t.enterText(find.byKey(const ValueKey('sup-text')), 'VIP görünmür');
    await t.tap(find.byKey(const ValueKey('sup-send')));
    await t.pumpAndSettle();
    expect(repo.sent, [(SupportKind.promo, 'VIP görünmür', null)]);
    expect(find.text('Təşəkkürlər! Adminlər qeydinizi nəzərə alacaq.'), findsOneWidget);
    expect(find.text('home'), findsOneWidget, reason: 'back where it was opened from');
  });

  testWidgets('Problem bildir from a payment carries the payment', (t) async {
    final repo = _FakeRepo();
    await t.pumpWidget(_app(const SupportFormScreen(kind: SupportKind.payment, paymentId: 'p9'), repo));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sup-with-payment')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('sup-text')), 'Pul çıxdı');
    await t.tap(find.byKey(const ValueKey('sup-send')));
    await t.pumpAndSettle();
    expect(repo.sent.single, (SupportKind.payment, 'Pul çıxdı', 'p9'));
  });

  testWidgets('Bildirişlər (admins): the reports, the server\'s finds, Baxılır / Həll olundu, Mesaj yaz, Maliyyə', (t) async {
    final repo = _FakeRepo();
    final list = [
      SupportReport.fromJson({'id': 'a', 'kind': 'feedback', 'status': 'new', 'message': 'Filtr olsun', 'user_id': 'u1', 'user_name': 'Əli',
        'created_at': '2026-11-13T10:00:00Z'}),
      SupportReport.fromJson({'id': 'b', 'kind': 'auto_payment', 'problem': 'failed', 'status': 'new', 'user_id': 'u2', 'user_name': 'Vəli',
        'payment_id': 'p1', 'amount': 7, 'currency': 'AZN', 'payment_status': 'failed', 'order_kind': 'cargo_promo',
        'created_at': '2026-11-13T09:00:00Z'}),
    ];
    await t.pumpWidget(_app(const AdminSupportScreen(), repo, extra: [
      adminSupportListProvider('new').overrideWith((ref) async => list),
      isFinanceAdminProvider.overrideWith((ref) async => true),
    ]));
    await t.pumpAndSettle();
    expect(find.text('Təklif / irad'), findsOneWidget);
    expect(find.text('Ödəniş alınmadı'), findsOneWidget);
    expect(find.text('7.00 AZN · alınmadı · Yük önə çıxar'), findsOneWidget);
    expect(find.byKey(const ValueKey('sup-message-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('sup-finance-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('sup-finance-a')), findsNothing, reason: 'no payment, no Maliyyə');
    await t.tap(find.byKey(const ValueKey('sup-resolve-b')));
    await t.pumpAndSettle();
    expect(repo.statuses, [('b', 'resolved')]);
  });

  test('wiring: Profil rows, the admins\' red count, Problem bildir on the payment sheet, routes', () {
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    expect(p.contains("ValueKey('pf-feedback')") && p.contains('openSupportForm(context)'), isTrue);
    final admin = p.substring(p.indexOf('class _HeadAdminCard'), p.indexOf('class _ProfileSubPage'));
    expect(admin.contains("ValueKey('pf-admin-reports')") && admin.contains('badge: n') && admin.contains('adminSupportCountProvider'), isTrue);
    final c = src('lib/features/finance/presentation/card_checkout.dart');
    expect(c.contains("ValueKey('pay-report-problem')") && c.contains('paymentId: p?.id'), isTrue);
    final r = src('lib/core/router/app_router.dart');
    expect(r.contains("path: '/support'") && r.contains("path: '/admin-reports'"), isTrue);
    final repo = src('lib/features/support/support.dart');
    expect(RegExp(r"\.from\('support_reports'\)").hasMatch(repo), isFalse, reason: 'only through the server functions');
  });

  test('the reset-password e-mail opens the app\'s own page with token_hash (works in any browser)', () {
    final r = src('lib/core/router/app_router.dart');
    expect(r.contains("ResetPasswordScreen(tokenHash: state.uri.queryParameters['token_hash'])"), isTrue);
    final doc = src('docs/RESET_PASSWORD_EMAIL.md');
    expect(doc.contains('https://tirlink.app/#/reset-password?token_hash={{ .TokenHash }}&type=recovery'), isTrue);
  });

  test('texts in all six languages', () {
    final keys = (jsonDecode(src('assets/i18n/az.json')) as Map<String, dynamic>).keys.where((k) => k.startsWith('sup_')).toList();
    expect(keys.length, greaterThan(40));
    for (final l in ['tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$l.json')) as Map<String, dynamic>;
      for (final k in keys) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
    }
  });
}

// "Təsdiqlənmiş hesab" (owner, 07.11.2026, 0104): on the Profil card under
// the account owner's details — not yet verified: the pale badge, the slogan
// and "Ayda 20 AZN · Aktiv et"; paid or granted by the Baş admin: the clear
// blue badge. No made-up payment: without a LIVE checkout nothing is ordered.
// Only the Baş admin gives the badge without payment (server + admin UI).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/finance/domain/finance_models.dart';
import 'package:freightlink/features/finance/presentation/card_checkout.dart';
import 'package:freightlink/features/finance/presentation/finance_providers.dart';
import 'package:freightlink/features/verified/verified_account.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _FakeRepo extends VerifiedAccountRepository {
  int orders = 0;
  @override
  Future<VipCheckoutTarget> order() async {
    orders++;
    throw StateError('no checkout in the test');
  }
}

Future<_FakeRepo> _pump(WidgetTester tester, {VerifiedStatus? status, bool legacy = false, String mode = 'test', bool own = true}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _FakeRepo();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      verifiedAccountRepositoryProvider.overrideWithValue(repo),
      verifiedStatusProvider('u1').overrideWith((ref) async => status),
      verifiedPlanProvider.overrideWith((ref) async => const VerifiedPlan(months: 1, price: 20, currency: 'AZN')),
      checkoutAvailabilityProvider.overrideWith(
          (ref) async => CheckoutAvailability(available: mode != 'off', mode: mode, methods: const [PayMethod.card])),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.only(left: 116, right: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            VerifiedAccountBlock(s: _az, userId: 'u1', legacyVerified: legacy, own: own),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('the status keeps the two ways apart; either one verifies', () {
    expect(VerifiedStatus.fromJson({'granted': false, 'paid': false}).verified, isFalse);
    expect(VerifiedStatus.fromJson({'granted': true, 'paid': false}).verified, isTrue);
    final paid = VerifiedStatus.fromJson({'granted': false, 'paid': true, 'paid_until': '2026-12-07T10:00:00Z'});
    expect([paid.verified, paid.granted, paid.paidUntil != null], [true, false, true]);
  });

  testWidgets('not verified yet: pale badge, the slogan and "Ayda 20 AZN · Aktiv et" — small, no overflow', (tester) async {
    await _pump(tester, status: const VerifiedStatus());
    expect(find.byKey(const ValueKey('vf-passive')), findsOneWidget);
    expect(find.text('Təsdiqlənmiş hesab'), findsOneWidget);
    expect(find.text('Etibarını göstər, daha çox müştəri qazan'), findsOneWidget);
    expect(find.text('Ayda 20 AZN · Aktiv et'), findsOneWidget);
    expect(find.byKey(const ValueKey('vf-active')), findsNothing);
    final badge = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('vf-passive')), matching: find.byType(Icon)));
    expect(badge.color!.a, lessThan(0.6), reason: 'pale, passive');
    // (The test font is much wider than Arial, so the slogan wraps here.)
    expect(tester.getSize(find.byKey(const ValueKey('vf-offer'))).height, lessThan(150), reason: 'the card does not grow much');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no LIVE payment yet: "Aktiv et" explains it and orders nothing (no made-up activation)', (tester) async {
    final repo = await _pump(tester, status: const VerifiedStatus(), mode: 'test');
    await tester.tap(find.byKey(const ValueKey('vf-activate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vf-not-live')), findsOneWidget);
    expect(repo.orders, 0);
  });

  testWidgets('LIVE checkout: "Aktiv et" makes the server order', (tester) async {
    final repo = await _pump(tester, status: const VerifiedStatus(), mode: 'live');
    await tester.tap(find.byKey(const ValueKey('vf-activate')));
    await tester.pumpAndSettle();
    expect(repo.orders, 1);
  });

  testWidgets('paid subscription active: the clear blue badge, no offer', (tester) async {
    await _pump(tester, status: VerifiedStatus(paid: true, paidUntil: DateTime(2026, 12, 7)));
    expect(find.byKey(const ValueKey('vf-active')), findsOneWidget);
    final badge = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('vf-active')), matching: find.byType(Icon)));
    expect(badge.color!.a, 1.0);
    expect(find.byKey(const ValueKey('vf-slogan')), findsNothing);
    expect(find.byKey(const ValueKey('vf-activate')), findsNothing);
  });

  testWidgets('the Baş admin\'s grant (no payment): the same clear badge', (tester) async {
    await _pump(tester, status: const VerifiedStatus(granted: true));
    expect(find.byKey(const ValueKey('vf-active')), findsOneWidget);
    expect(find.byKey(const ValueKey('vf-activate')), findsNothing);
  });

  testWidgets('another person\'s card: no offer', (tester) async {
    await _pump(tester, status: const VerifiedStatus(), own: false);
    expect(find.byKey(const ValueKey('vf-passive')), findsOneWidget);
    expect(find.byKey(const ValueKey('vf-activate')), findsNothing);
  });

  test('wired: under the owner\'s details on Profil; admin UI and server allow only the Baş admin', () {
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    expect(p, contains('VerifiedAccountBlock(s: strings, userId: widget.userId, legacyVerified: verified),'));
    final a = src('lib/features/admin/presentation/admin_pages.dart');
    expect(a, contains('ref.read(verifiedAccountRepositoryProvider).adminSet(id, !v)'));
    expect(a, contains("if (chief) 'is_verified': verified,"));
    expect(a.contains("updateUser(id, {'is_verified': !v})"), isFalse, reason: 'ordinary admins no longer toggle it');
    final sql = src('supabase/migrations/0104_verified_account.sql');
    expect(sql, contains("raise exception 'chief_admin_only'"));
    expect(sql, contains("if v_new = 'succeeded' and v_pay.verified_order_id is not null and v_pay.mode = 'live' then"));
    expect(sql, contains("if s.mode is distinct from 'live' then raise exception 'payments_not_live'"));
    expect(sql.toLowerCase().contains('delete from'), isFalse);
    expect(sql.toLowerCase().contains('drop table'), isFalse);
    final fn = src('supabase/functions/payments-checkout/index.ts');
    expect(fn, contains('rpc/verified_payment_create'));
    expect(src('docs/payments/payments-checkout.dashboard.ts'), contains('rpc/verified_payment_create'));
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = jsonDecode(src('assets/i18n/$l.json')) as Map;
      for (final k in ['vf_slogan', 'vf_activate', 'vf_not_live', 'vf_failed', 'pf_verified_account']) {
        expect(j.containsKey(k), isTrue, reason: '$l $k');
      }
      expect('${j['vf_activate']}', contains('{price}'), reason: l);
    }
  });
}

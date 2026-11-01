import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/finance/domain/finance_models.dart';
import 'package:freightlink/features/finance/presentation/card_checkout.dart';
import 'package:freightlink/features/finance/presentation/finance_providers.dart';
import 'package:freightlink/features/tirpark/data/tir_park_repository.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_booking.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_manage.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

final _park = TirPark.fromJson({
  'id': 'p1',
  'name': 'Utep TIR Parkı',
  'lat': 40.456,
  'lng': 49.73,
  'status': 'approved',
  'manager_id': 'm1',
  'manager_status': 'approved',
  'capacity': 20,
  'bookable': 2,
  'price': '5.00',
  'price_unit': 'hour',
  'currency': 'AZN',
  'hours': '24/7',
  'phone': '+994501234567',
  'booking_open': true,
});

class _FakeRepo extends TirParkRepository {
  int free = 2;
  final booked = <String>[];
  final codes = <String>[];
  List<TirPark> managed = const [];
  List<TirParkBooking> mine = const [];
  @override
  Future<int> freePlaces(String parkId, DateTime from, DateTime to) async => free;
  @override
  Future<TirParkBooking> book(String parkId, DateTime from, DateTime to, int trucks) async {
    booked.add('$parkId|$trucks');
    return TirParkBooking(
        id: 'b1', bookingNo: 'TP1', parkId: parkId, trucks: trucks, units: 2, unit: 'hour', startAt: from, endAt: to, amount: 10, status: 'pending_payment');
  }
  @override
  Future<List<TirPark>> myManaged() async => managed;
  @override
  Future<List<TirParkBooking>> managerBookings(String parkId) async => const [];
  @override
  Future<List<TirParkBooking>> myBookings() async => mine;
  @override
  Future<TirParkBooking> checkIn(String parkId, String code) async {
    codes.add(code);
    throw const TirParkRefused('already_used');
  }
}

Widget _app(Widget child, _FakeRepo repo, {bool payOn = true}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        tirParkRepositoryProvider.overrideWithValue(repo),
        tirParksProvider.overrideWith((ref) async => [_park]),
        checkoutAvailabilityProvider.overrideWith((ref) async =>
            payOn ? const CheckoutAvailability(available: true, mode: 'test', methods: [PayMethod.card]) : const CheckoutAvailability(available: false, mode: 'test')),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the park opens for booking only with an approved manager, price and free places (as the server)', () {
    expect(_park.canBook, isTrue);
    expect(TirPark.fromJson({'id': 'x', 'name': 'A', 'lat': 1, 'lng': 2, 'status': 'approved'}).canBook, isFalse, reason: 'parks from 0077 stay as they were');
    expect(TirPark.fromJson({..._jsonOf(_park), 'manager_status': 'pending'}).canBook, isFalse);
    expect(TirPark.fromJson({..._jsonOf(_park), 'booking_open': false}).canBook, isFalse);
    final t0 = DateTime(2026, 11, 2, 10);
    expect(tirParkUnits(t0, t0.add(const Duration(hours: 2, minutes: 10)), 'hour'), 3, reason: 'started hours count whole (server: ceil)');
    expect(tirParkUnits(t0, t0.add(const Duration(hours: 25)), 'day'), 2);
    final b = TirParkBooking.fromJson({
      'id': 'b', 'booking_no': 'TP1', 'park_id': 'p1', 'trucks': 1, 'units': 1, 'unit': 'hour', 'start_at': '2026-11-02T10:00:00Z',
      'end_at': '2026-11-02T11:00:00Z', 'amount': '5', 'status': 'pending_payment', 'hold_until': '2020-01-01T00:00:00Z',
    });
    expect(b.shownStatus, 'expired', reason: 'an old hold shows as expired');
  });

  testWidgets('booking: price, capacity, free places; summary with the conditions before payment; then the secure checkout',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), repo));
    await tester.pumpAndSettle();
    expect(find.text('Qiymət: 5.00 AZN / saat'), findsOneWidget);
    expect(find.text('Ümumi tutum: 20 TIR'), findsOneWidget);
    expect(find.text('Seçilən vaxtda boş yer: 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpb-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tpb-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpb-terms')), findsOneWidget, reason: 'cancel / refund conditions shown first');
    expect(find.textContaining('× 2 TIR'), findsWidgets);
    expect(repo.booked, isEmpty, reason: 'nothing is held before the driver agrees');
    await tester.tap(find.byKey(const ValueKey('tpb-go')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repo.booked, ['p1|2']);
    expect(find.byType(CheckoutSheet), findsOneWidget, reason: 'the existing checkout; the server confirms');
  });

  testWidgets('no free places → no booking; payment not active → said plainly, no button', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..free = 0;
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), repo));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('tpb-book'))).onPressed, isNull);
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), _FakeRepo(), payOn: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpb-pay-off')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-book')), findsNothing, reason: 'a test checkout is never shown as real');
  });

  testWidgets('my bookings: the entry code of a confirmed booking, TEST marked, cancel', (tester) async {
    final repo = _FakeRepo()
      ..mine = [
        TirParkBooking(
            id: 'b1', bookingNo: 'TP261102-ABC', parkId: 'p1', trucks: 1, units: 2, unit: 'hour',
            startAt: DateTime.now().add(const Duration(hours: 3)), endAt: DateTime.now().add(const Duration(hours: 5)),
            amount: 10, status: 'confirmed', paidMode: 'test', code: 'K7M2P9QX'),
      ];
    await tester.pumpWidget(_app(const MyParkBookingsScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('K7M2P9QX'), findsOneWidget);
    expect(find.text('TEST ödənişi — real pul köçməyib'), findsOneWidget);
    expect(find.text('Təsdiqlənib'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-cancel-b1')), findsOneWidget);
  });

  testWidgets('manager: a pending application waits; an approved park shows payouts honestly, the code check and bookings',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()
      ..managed = [
        TirPark.fromJson({..._jsonOf(_park), 'id': 'p2', 'name': 'Yeni park', 'status': 'pending', 'manager_status': 'pending'}),
        _park,
      ];
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('Admin təsdiqi gözləyir'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpm-code-p2')), findsNothing, reason: 'no managing before approval');
    expect(find.byKey(const ValueKey('tpm-payout-p1')), findsOneWidget);
    expect(find.textContaining('real ödəniş provayderi qoşulmayıb'), findsOneWidget);
    expect(find.textContaining('kart nömrəsi, CVV'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('tpm-code-p1')), 'k7m2p9qx');
    await tester.tap(find.byKey(const ValueKey('tpm-checkin-p1')));
    await tester.pumpAndSettle();
    expect(repo.codes, ['k7m2p9qx'], reason: 'the server checks the code');
    expect(find.text('Bu kod artıq istifadə olunub.'), findsOneWidget);
  });

  test('wired: server-side rules, checkout, webhook, RLS, no card data, no commission', () {
    final sql = src('supabase/migrations/0079_tir_park_booking.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'card_number', 'cvv', 'iban', 'pan ']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('select * into p from tir_parks where id = p_park for update;'), reason: 'atomic: the park row is locked');
    expect(sql, contains("raise exception 'no_space'"));
    expect(sql, contains('hold_until > now()'));
    expect(sql, contains("case when s.mode = 'test' then 'test' else s.provider end, s.mode, 0, p_key)"), reason: 'commission 0');
    expect(sql, contains('perform public._tir_park_booking_paid(v_pay.tir_park_booking_id, v_pay.mode);'));
    expect(sql, contains("if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not_authorized'"));
    expect(sql, contains('using (user_id = auth.uid() or public.is_admin());'), reason: 'drivers see only their own bookings');
    expect(sql, contains('revoke all on public.tir_park_bookings from anon, authenticated;'));
    expect(sql, contains("if v_b.status in ('checked_in', 'completed') then raise exception 'already_used'"));
    for (final f in ['supabase/functions/payments-checkout/index.ts', 'docs/payments/payments-checkout.dashboard.ts']) {
      expect(src(f), contains('rpc/tir_park_booking_payment_create'), reason: f);
    }
    expect(src('lib/features/finance/data/finance_repository.dart'), contains("'tir_park_booking_id': bookingId"));
    expect(src('lib/core/router/app_router.dart'), contains("path: 'manage'"));
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains("context.pushOnce('/tirpark/manage')"));
    expect(src('supabase/tests/local/run_local.sh'), contains('117_tir_park_booking.sql'));
    final lib = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in lib) {
      final s = f.readAsStringSync().toLowerCase();
      expect(s.contains("'cvv'") || s.contains('card_number'), isFalse, reason: f.path);
    }
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in ['tpb_book', 'tpb_terms', 'tpb_pay_off', 'tpm_title', 'tpm_payout_body', 'tpb_st_checked_in', 'pay_success_booking_test']) {
        expect(m[k], isNotNull, reason: '$lang $k');
      }
    }
  });
}

Map<String, dynamic> _jsonOf(TirPark p) => {
      'id': p.id,
      'name': p.name,
      'lat': p.lat,
      'lng': p.lng,
      'status': p.status,
      'manager_id': p.managerId,
      'manager_status': p.managerStatus,
      'capacity': p.capacity,
      'bookable': p.bookable,
      'price': p.price,
      'price_unit': p.priceUnit,
      'currency': p.currency,
      'hours': p.hours,
      'phone': p.phone,
      'booking_open': p.bookingOpen,
    };

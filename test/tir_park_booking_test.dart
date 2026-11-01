import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
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
  List<TirParkBooking> parkBookings = const [];
  final confirmed = <String>[];
  TirParkPayDetails? details;
  @override
  Future<List<TirParkBooking>> managerBookings(String parkId) async => parkBookings;
  @override
  Future<void> confirmPayment(String bookingId) async => confirmed.add(bookingId);
  @override
  Future<TirParkPayDetails?> payDetails(String parkId) async => details;
  @override
  Future<TirParkPayDetails?> bookingPayDetails(String bookingId) async => const TirParkPayDetails(
      holder: 'Utep MMC', bank: 'Kapital Bank', account: 'AZ21NABZ00000000137010001944', card: '4169 7388 1234 5678', amount: 10, bookingNo: 'TP1');
  @override
  Future<List<TirParkBooking>> myBookings() async => mine;
  @override
  Future<TirParkBooking> checkIn(String parkId, String code) async {
    codes.add(code);
    throw const TirParkRefused('already_used');
  }
}

Widget _app(Widget child, _FakeRepo repo) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        tirParkRepositoryProvider.overrideWithValue(repo),
        tirParksProvider.overrideWith((ref) async => [_park]),
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

  testWidgets('booking: price, capacity, free places; conditions first; then the park''s own details to transfer to (no checkout)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), repo));
    await tester.pumpAndSettle();
    expect(find.text('Qiymət: 5.00 AZN / saat'), findsOneWidget);
    expect(find.text('Ümumi tutum: 20 TIR'), findsOneWidget);
    expect(find.text('Seçilən vaxtda boş yer: 2'), findsOneWidget);
    expect(find.textContaining('Utep MMC'), findsNothing, reason: 'payment details are not on the park card');
    await tester.tap(find.byKey(const ValueKey('tpb-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tpb-book')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpb-terms')), findsOneWidget, reason: 'conditions shown first');
    expect(find.textContaining('FreightLink pul qəbul etmir'), findsWidgets);
    expect(repo.booked, isEmpty, reason: 'nothing is held before the driver agrees');
    await tester.tap(find.byKey(const ValueKey('tpb-go')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repo.booked, ['p1|2']);
    expect(find.byType(TirParkPaySheet), findsOneWidget, reason: 'after booking: where to pay');
    expect(find.text('4169 7388 1234 5678'), findsOneWidget);
    expect(find.text('AZ21NABZ00000000137010001944'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-upload')), findsOneWidget, reason: 'the receipt picture');
  });

  testWidgets('no free places → no booking; a park without payment details → said plainly', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..free = 0;
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), repo));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('tpb-book'))).onPressed, isNull);
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), _ClosedRepo()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpb-closed')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-book')), findsNothing);
  });

  testWidgets('my bookings: "Ödəniş yoxlanılır"; after the park confirms, the code with its QR', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final later = DateTime.now().add(const Duration(hours: 3));
    final repo = _FakeRepo()
      ..mine = [
        TirParkBooking(
            id: 'b1', bookingNo: 'TP261102-ABC', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'confirmed', paidMode: 'transfer', code: 'K7M2P9QX'),
        TirParkBooking(
            id: 'b2', bookingNo: 'TP261102-DEF', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'payment_review'),
        TirParkBooking(
            id: 'b3', bookingNo: 'TP261102-GHI', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'pending_payment',
            holdUntil: DateTime.now().add(const Duration(minutes: 30)), rejectNote: 'Pul gəlməyib'),
      ];
    await tester.pumpWidget(_app(const MyParkBookingsScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('K7M2P9QX'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-qr-b1')), findsOneWidget, reason: 'QR of the entry code');
    expect(find.text('Ödəniş yoxlanılır'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-code-b2')), findsNothing, reason: 'no code before the park confirms');
    expect(find.byKey(const ValueKey('tpb-pay-b3')), findsOneWidget, reason: 'unpaid: details and receipt again');
    expect(find.textContaining('Pul gəlməyib'), findsOneWidget);
  });

  testWidgets('manager: pending waits; approved: payment details form (no provider notice), code check, "Ödənişi təsdiqlə"',
      (tester) async {
    tester.view.physicalSize = const Size(400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final repo = _FakeRepo()
      ..managed = [
        TirPark.fromJson({..._jsonOf(_park), 'id': 'p2', 'name': 'Yeni park', 'status': 'pending', 'manager_status': 'pending'}),
        _park,
      ]
      ..parkBookings = [
        TirParkBooking(
            id: 'b9', bookingNo: 'TP9', parkId: 'p1', trucks: 1, units: 1, unit: 'hour', startAt: now, endAt: now.add(const Duration(hours: 1)),
            amount: 5, status: 'payment_review', receiptPath: 'u/b9/r.jpg'),
      ];
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('Admin təsdiqi gözləyir'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpm-code-p2')), findsNothing, reason: 'no managing before approval');
    expect(find.textContaining('provayderi qoşulmayıb'), findsNothing, reason: 'the old notice is gone');
    expect(find.byKey(const ValueKey('tpm-paydet-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpm-paydet-need-p1')), findsOneWidget, reason: 'no details yet → asked for');
    expect(find.textContaining('CVV, PIN'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpm-receipt-b9')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpm-confirm-b9')));
    await tester.pumpAndSettle();
    expect(repo.confirmed, ['b9'], reason: 'the server makes the code');
    await tester.enterText(find.byKey(const ValueKey('tpm-code-p1')), 'k7m2p9qx');
    await tester.tap(find.byKey(const ValueKey('tpm-checkin-p1')));
    await tester.pumpAndSettle();
    expect(repo.codes, ['k7m2p9qx']);
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
    expect(sql, contains('using (user_id = auth.uid() or public.is_admin());'), reason: 'drivers see only their own bookings');
    expect(sql, contains('revoke all on public.tir_park_bookings from anon, authenticated;'));
    expect(sql, contains("if v_b.status in ('checked_in', 'completed') then raise exception 'already_used'"));
    // 0080: direct transfer to the park; FreightLink takes no money.
    final d = src('supabase/migrations/0080_tir_park_direct_payment.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'cvv']) {
      expect(d.contains(bad), isFalse, reason: bad);
    }
    expect(d, contains('revoke all on public.tir_park_pay_details from anon, authenticated;'), reason: 'details not readable directly');
    expect(d, contains("if v_b.id is null or v_b.user_id is distinct from auth.uid() then raise exception 'not_found'"),
        reason: 'details only for the driver of that booking');
    expect(d, contains("raise exception 'payments_disabled'"), reason: 'the card checkout for bookings is closed');
    expect(d, contains("set status = 'confirmed', paid_mode = 'transfer', code = v_code"), reason: 'the code only after the manager confirms');
    expect(d, contains("values ('tirpark-receipts', 'tirpark-receipts', false"), reason: 'private receipts');
    expect(src('lib/features/tirpark/presentation/tir_park_booking.dart').contains('CheckoutSheet'), isFalse,
        reason: 'no card checkout in the booking flow');
    expect(src('supabase/tests/local/run_local.sh'), contains('118_tir_park_direct_payment.sql'));
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
      for (final k in ['tpb_book', 'tpb_terms', 'tpb_st_payment_review', 'tpm_title', 'tpm_paydet_hint', 'tpm_confirm', 'tpb_upload', 'tpb_no_money']) {
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

class _ClosedRepo extends _FakeRepo {
  @override
  Future<int> freePlaces(String parkId, DateTime from, DateTime to) async => throw const TirParkRefused('not_bookable');
}

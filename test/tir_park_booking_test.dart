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
  'price_unit': 'day',
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
  Future<TirParkBooking> book(String parkId, DateTime from, DateTime to, int trucks, String plate) async {
    booked.add('$parkId|$trucks|$plate');
    return TirParkBooking(
        id: 'b1', bookingNo: 'TP1', parkId: parkId, trucks: trucks, units: 2, unit: 'hour', startAt: from, endAt: to, amount: 10,
        status: 'pending_payment', plate: plate);
  }
  @override
  Future<List<TirPark>> myManaged() async => managed;
  // Owner panel (0086).
  TirParkOwnerRequest? request;
  final applied = <String>[];
  final entered = <String>[];
  final exited = <String>[];
  List<TirParkStay> inPark = const [];
  @override
  Future<TirParkOwnerRequest?> myOwnerRequest() async => request;
  @override
  Future<void> ownerApply(String name) async => applied.add(name);
  @override
  Future<TirParkStay> stayEnter(String parkId, String plate) async {
    entered.add('$parkId|$plate');
    return TirParkStay(id: 'new', plate: plate, enteredAt: DateTime.now(), rate: 3);
  }
  @override
  Future<double> stayExit(String stayId) async {
    exited.add(stayId);
    return 3.5;
  }
  @override
  Future<TirParkParked> parked(String parkId) async => TirParkParked(inPark: inPark);
  @override
  Future<TirParkSummary> ownerSummary(String parkId) async =>
      const TirParkSummary(capacity: 250, inPark: 184, free: 66, todayPaid: 552, accruing: 34.2, open: true);
  @override
  Future<List<TirParkFeedItem>> ownerFeed(String parkId) async =>
      [TirParkFeedItem(kind: 'in', plate: '99-AC-981', at: DateTime.now())];
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
    expect(TirPark.fromJson({..._jsonOf(_park), 'price_unit': 'hour'}).canBook, isFalse, reason: 'days only: an hourly park waits for a day price');
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
    expect(find.text('Qiymət: 5.00 AZN / gün'), findsOneWidget);
    expect(find.text('Gəlmə günü\n${tirParkDay(DateTime.now())}'), findsOneWidget, reason: 'a day, no hour (owner, 03.11.2026)');
    expect(find.text('Ümumi tutum: 20 TIR'), findsOneWidget);
    expect(find.text('Seçilən vaxtda boş yer: 2'), findsOneWidget);
    expect(find.textContaining('Utep MMC'), findsNothing, reason: 'payment details are not on the park card');
    await tester.tap(find.byKey(const ValueKey('tpb-trucks-plus')));
    await tester.pump();
    expect(find.text('5.00 AZN / gün × 1 gün × 2 TIR = 10.00 AZN'), findsOneWidget, reason: 'the calculation before paying');
    await tester.tap(find.byKey(const ValueKey('tpb-book')));
    await tester.pumpAndSettle();
    expect(find.text('Maşının dövlət nömrəsini yazın (məs. 99-ZB-911).'), findsOneWidget, reason: 'no booking without the plate');
    expect(find.byKey(const ValueKey('tpb-terms')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('tpb-plate')), ' 99 zb 911 ');
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
    expect(repo.booked, ['p1|2|99-ZB-911'], reason: 'the plate goes with the booking, tidy');
    expect(find.text('Maşının dövlət nömrəsi: 99-ZB-911'), findsOneWidget, reason: 'on the payment sheet');
    expect(find.byType(TirParkPaySheet), findsOneWidget, reason: 'after booking: where to pay');
    expect(find.text('4169 7388 1234 5678'), findsOneWidget);
    expect(find.text('AZ21NABZ00000000137010001944'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-upload')), findsOneWidget, reason: 'the receipt picture');
    expect(find.byKey(const ValueKey('tpb-pay-no')), findsNothing, reason: 'no "Təyinat" line (owner, 03.11.2026)');
    expect(find.textContaining('Təyinat'), findsNothing);
  });

  testWidgets('no free places → no booking; a park without payment details → said plainly', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..free = 0;
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), repo));
    await tester.pumpAndSettle();
    expect(find.text('Boş yer yoxdur'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-book')), findsNothing, reason: '"Boş yer yoxdur" instead of the button');
    await tester.pumpWidget(_app(
        Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: TirPark.fromJson({..._jsonOf(_park), 'booking_open': false}), s: _az))),
        _FakeRepo()));
    await tester.pumpAndSettle();
    expect(find.text('Rezervasiya bağlıdır'), findsOneWidget, reason: 'the manager turned booking off');
    expect(find.byKey(const ValueKey('tpb-book')), findsNothing);
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: _park, s: _az))), _ClosedRepo()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpb-closed')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-book')), findsNothing);
  });

  testWidgets('my bookings: "Ödəniş yoxlanılır"; after the park confirms: the plate, no code / QR', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final later = DateTime.now().add(const Duration(hours: 3));
    final repo = _FakeRepo()
      ..mine = [
        TirParkBooking(
            id: 'b1', bookingNo: 'TP261102-ABC', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'confirmed', paidMode: 'transfer', code: 'K7M2P9QX',
            plate: '99-ZB-911'),
        TirParkBooking(
            id: 'b2', bookingNo: 'TP261102-DEF', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'payment_review'),
        TirParkBooking(
            id: 'b3', bookingNo: 'TP261102-GHI', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'pending_payment',
            holdUntil: DateTime.now().add(const Duration(minutes: 30)), rejectNote: 'Pul gəlməyib'),
        TirParkBooking(
            id: 'b4', bookingNo: 'TP261102-JKL', parkId: 'p1', trucks: 1, units: 2, unit: 'hour', startAt: later,
            endAt: later.add(const Duration(hours: 2)), amount: 10, status: 'cancelled', cancelReason: 'payment_rejected',
            rejectNote: 'Məbləğ azdır'),
      ];
    await tester.pumpWidget(_app(const MyParkBookingsScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('K7M2P9QX'), findsNothing, reason: 'no entry code (owner, 03.11.2026)');
    expect(find.byKey(const ValueKey('tpb-qr-b1')), findsNothing, reason: 'no QR');
    expect(find.byKey(const ValueKey('tpb-plate-b1')), findsOneWidget, reason: 'the plate on the confirmed booking');
    expect(find.text('Təsdiqləndi. Parka gələndə maşının nömrəsini deyin: 99-ZB-911'), findsOneWidget);
    expect(find.text('Ödəniş yoxlanılır'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-code-b2')), findsNothing, reason: 'no code before the park confirms');
    expect(find.byKey(const ValueKey('tpb-pay-b3')), findsOneWidget, reason: 'unpaid: details and receipt again');
    expect(find.textContaining('Pul gəlməyib'), findsOneWidget);
    expect(find.text('Ödəniş rədd edildi'), findsOneWidget, reason: '0081: "Rədd et" ends the booking');
    expect(find.byKey(const ValueKey('tpb-rejected-b4')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-pay-b4')), findsNothing, reason: 'no paying for a rejected booking');
  });

  test('money by the time: 3 AZN / 24 h — 5 h = 0.63, 1 day 4 h = 3.50, 2 days = 6.00; a paid booking first', () {
    final t0 = DateTime(2026, 11, 3, 8);
    expect(tirParkStayAmount(3, t0, null, t0.add(const Duration(hours: 5))), 0.63);
    expect(tirParkStayAmount(3, t0, null, t0.add(const Duration(hours: 28))), 3.50);
    expect(tirParkStayAmount(3, t0, null, t0.add(const Duration(hours: 48))), 6.00);
    expect(tirParkStayAmount(3, t0, t0.add(const Duration(days: 2)), t0.add(const Duration(hours: 30))), 0, reason: 'inside the paid days');
    expect(tirParkStayAmount(3, t0, t0.add(const Duration(days: 2)), t0.add(const Duration(hours: 53))), 0.63, reason: 'overstay by the hour');
  });

  test('the plate is tidied like the server does (0082)', () {
    expect(tidyTruckPlate(' 99 zb 911 '), '99-ZB-911');
    expect(tidyTruckPlate('99.zb/911'), '99-ZB-911');
    expect(tidyTruckPlate('99--ZB--911'), '99-ZB-911');
    expect(tidyTruckPlate('AA 1234 BB'), 'AA-1234-BB');
    expect(tidyTruckPlate(''), isNull);
    expect(tidyTruckPlate('ABC'), isNull, reason: 'a plate has digits');
    expect(tidyTruckPlate('1234567890123456'), isNull, reason: 'too long');
    final b = TirParkBooking.fromJson({'id': 'b', 'status': 'confirmed', 'plate': '99-ZB-911'});
    expect(b.plate, '99-ZB-911');
  });

  testWidgets('days only: a park still priced per hour says "Rezervasiya bağlıdır" (section and card)', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hourly = TirPark.fromJson({..._jsonOf(_park), 'price_unit': 'hour'});
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: hourly, s: _az))), _FakeRepo()));
    await tester.pumpAndSettle();
    expect(find.text('Rezervasiya bağlıdır'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpb-book')), findsNothing);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        tirParkRepositoryProvider.overrideWithValue(_FakeRepo()),
        tirParksProvider.overrideWith((ref) async => [hourly]),
        tirParkBookingNowProvider.overrideWith((ref) async => {'p1': const TirParkBookingNow(open: true, free: 6)}),
      ],
      child: MaterialApp(home: Scaffold(body: TirParkCardBooking(park: hourly, s: _az))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Rezervasiya bağlıdır'), findsOneWidget, reason: 'even if the server still counts it open');
    expect(find.byKey(const ValueKey('tpc-book-p1')), findsNothing);
  });

  testWidgets('a day park: arrival, stay in days, TIRs → 3 AZN/gün × 2 gün × 2 TIR = 12 AZN', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = TirPark.fromJson({..._jsonOf(_park), 'price': 3, 'price_unit': 'day', 'bookable': 6});
    final repo = _FakeRepo()..free = 6;
    await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: TirParkBookingSection(park: day, s: _az))), repo));
    await tester.pumpAndSettle();
    expect(find.text('Qalma müddəti'), findsOneWidget);
    expect(find.text('1 gün'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpb-len-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tpb-trucks-plus')));
    await tester.pumpAndSettle();
    expect(find.text('2 gün'), findsOneWidget);
    expect(find.text('3.00 AZN / gün × 2 gün × 2 TIR = 12.00 AZN'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('tpb-plate')), '10-AB-123');
    await tester.tap(find.byKey(const ValueKey('tpb-book')));
    await tester.pumpAndSettle();
    expect(find.text('Maşının dövlət nömrəsi: 10-AB-123'), findsOneWidget, reason: 'the plate in the summary');
    expect(find.byKey(const ValueKey('tpb-calc-confirm')), findsOneWidget, reason: 'the calculation again before anything is held');
    expect(find.textContaining('Yekun: 12.00 AZN'), findsOneWidget);
  });

  testWidgets('the booking sheet stays above the keyboard: the plate field and what is typed stay in view', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = TirPark.fromJson({..._jsonOf(_park), 'price': 3, 'price_unit': 'day', 'bookable': 6, 'capacity': 250});
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        tirParkRepositoryProvider.overrideWithValue(_FakeRepo()..free = 6),
        tirParksProvider.overrideWith((ref) async => [day]),
        tirParkBookingNowProvider.overrideWith((ref) async => {'p1': const TirParkBookingNow(open: true, free: 6)}),
      ],
      child: MaterialApp(home: Scaffold(body: TirParkCardBooking(park: day, s: _az))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tpc-book-p1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tpb-plate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tpb-plate')));
    // The keyboard opens: 330 pt of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tpb-plate')), '99-ZB-911');
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byKey(const ValueKey('tpb-plate')));
    expect(field.bottom, lessThanOrEqualTo(844 - 330), reason: 'the field is above the keyboard');
    expect(field.top, greaterThanOrEqualTo(0));
    expect(find.text('99-ZB-911'), findsOneWidget);
    tester.view.resetViewInsets();
  });

  testWidgets('park card: "Boş yerlər: 6" + "Yeri rezerv et"; "Rezervasiya bağlıdır"; "Boş yer yoxdur"', (tester) async {
    Future<void> show(TirParkBookingNow now) async {
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          stringsProvider.overrideWithValue(_az),
          tirParkRepositoryProvider.overrideWithValue(_FakeRepo()),
          tirParksProvider.overrideWith((ref) async => [_park]),
          tirParkBookingNowProvider.overrideWith((ref) async => {'p1': now}),
        ],
        child: MaterialApp(home: Scaffold(body: TirParkCardBooking(park: _park, s: _az))),
      ));
      await tester.pumpAndSettle();
    }

    await show(const TirParkBookingNow(open: true, free: 6));
    expect(find.text('Boş yerlər: 6'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpc-book-p1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpc-book-p1')));
    await tester.pumpAndSettle();
    expect(find.byType(TirParkBookingSection), findsOneWidget, reason: 'the booking opens from the card');
    await show(const TirParkBookingNow(open: false, free: 0));
    expect(find.text('Rezervasiya bağlıdır'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpc-book-p1')), findsNothing);
    await show(const TirParkBookingNow(open: true, free: 0));
    expect(find.text('Boş yer yoxdur'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpc-book-p1')), findsNothing);
    // A park without a manager has no booking line.
    await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        child: MaterialApp(
            home: Scaffold(
                body: TirParkCardBooking(park: TirPark.fromJson({'id': 'x', 'name': 'A', 'lat': 1, 'lng': 2, 'status': 'approved'}), s: _az)))));
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('owner panel: Ümumi (numbers, receipts, gedişat) · Maşınlar (add by plate, exit with the money) · Ayarlar',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final repo = _FakeRepo()
      ..managed = [_park]
      ..inPark = [TirParkStay(id: 's1', plate: '99-AC-981', enteredAt: now.subtract(const Duration(hours: 28)), rate: 3)]
      ..parkBookings = [
        TirParkBooking(
            id: 'b9', bookingNo: 'TP9', parkId: 'p1', trucks: 1, units: 1, unit: 'day', startAt: now, endAt: now.add(const Duration(days: 1)),
            amount: 5, status: 'payment_review', receiptPath: 'u/b9/r.jpg', plate: '99-ZB-911'),
      ];
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    // Ümumi
    expect(find.text('Sahibkar paneli'), findsOneWidget, reason: 'an approved owner goes straight to his panel');
    expect(find.text('İşləyir'), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('184'), findsOneWidget);
    expect(find.text('66'), findsOneWidget);
    expect(find.text('552.00 AZN'), findsOneWidget, reason: 'Bu gün = money taken today');
    expect(find.textContaining('34.20 AZN (hələ alınmayıb)'), findsOneWidget, reason: 'run up in the park, shown apart');
    expect(find.byKey(const ValueKey('tpm-new-payments-p1')), findsOneWidget, reason: 'receipts waiting');
    expect(find.byKey(const ValueKey('tpm-plate-b9')), findsOneWidget);
    expect(find.text('Parkın gedişatı'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpm-confirm-b9')));
    await tester.pumpAndSettle();
    expect(repo.confirmed, ['b9']);
    expect(find.text('Ödəniş təsdiqləndi: TP9.'), findsOneWidget, reason: 'no entry code any more');
    ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('tpo-nav')))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    // Maşınlar
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('tpo-nav')), matching: find.text('Maşınlar')));
    await tester.pumpAndSettle();
    expect(find.text('Parkda olan maşınlar'), findsOneWidget);
    expect(find.text('1 gün 4 saat'), findsOneWidget);
    expect(find.text('3.50 AZN'), findsOneWidget, reason: '3 AZN / 24 h × 28 h');
    await tester.tap(find.byKey(const ValueKey('tpo-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('tpo-plate')), 'abc');
    await tester.tap(find.byKey(const ValueKey('tpo-plate-go')));
    await tester.pumpAndSettle();
    expect(repo.entered, isEmpty, reason: 'a plate needs digits');
    await tester.enterText(find.byKey(const ValueKey('tpo-plate')), ' 10 bb 442 ');
    await tester.tap(find.byKey(const ValueKey('tpo-plate-go')));
    await tester.pumpAndSettle();
    expect(repo.entered, ['p1|10-BB-442']);
    await tester.tap(find.byKey(const ValueKey('tpo-exit-s1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Məbləğ: 3.50 AZN'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tpo-exit-go')));
    await tester.pumpAndSettle();
    expect(repo.exited, ['s1']);
    expect(find.text('Çıxdı: 99-AC-981 · 3.50 AZN'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byKey(const ValueKey('tpo-nav')))).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    // Ayarlar: price per day, payment details; no entry-code check any more.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('tpo-nav')), matching: find.text('Ayarlar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpm-paydet-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpm-unit-p1')), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byKey(const ValueKey('tpm-code-p1')), findsNothing, reason: 'no entry code (owner, 03.11.2026)');
    expect(find.byKey(const ValueKey('tpm-free-p1')), findsNothing, reason: 'bookings take places from the whole capacity');
  });

  testWidgets('"Park işlədirəm": only the name → waiting for the admin → "Parkı qur"', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpo-apply-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpm-f-phone')), findsNothing, reason: 'only the name');
    await tester.enterText(find.byKey(const ValueKey('tpo-apply-name')), 'Göygöl TIR Park');
    await tester.tap(find.byKey(const ValueKey('tpo-apply-send')));
    await tester.pumpAndSettle();
    expect(repo.applied, ['Göygöl TIR Park']);
    repo.request = const TirParkOwnerRequest(id: 'r1', parkName: 'Göygöl TIR Park', status: 'pending');
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('«Göygöl TIR Park» — admin təsdiqi gözləyir.'), findsOneWidget);
    expect(find.byKey(const ValueKey('tpo-apply-name')), findsNothing);
    repo.request = const TirParkOwnerRequest(id: 'r1', parkName: 'Göygöl TIR Park', status: 'approved');
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpo-setup')), findsOneWidget, reason: 'approved: put the park on the map');
    // A park applied for the old way (0079) still shows as waiting.
    repo
      ..request = null
      ..managed = [TirPark.fromJson({..._jsonOf(_park), 'id': 'p2', 'name': 'Yeni park', 'status': 'pending', 'manager_status': 'pending'})];
    await tester.pumpWidget(_app(const TirParkManageScreen(), repo));
    await tester.pumpAndSettle();
    expect(find.text('Admin təsdiqi gözləyir'), findsOneWidget);
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
    // 0081: the booking line on the card; "Rədd et" frees the space.
    final c = src('supabase/migrations/0081_tir_park_booking_card.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'tir_park_pay_details d']) {
      expect(c.contains(bad), isFalse, reason: bad);
    }
    expect(c, contains("set status = 'cancelled', cancelled_at = now(), cancel_reason = 'payment_rejected', hold_until = null"));
    expect(c, contains("'open', public.tir_park_bookable(p)"), reason: 'the same open rule as booking itself');
    expect(src('supabase/migrations/0080_tir_park_direct_payment.sql'), contains("status in ('confirmed', 'checked_in', 'payment_review')"),
        reason: 'a receipt being checked keeps its space');
    expect(src('supabase/tests/local/run_local.sh'), contains('119_tir_park_booking_card.sql'));
    // 0085: the manager is told about a receipt (notice + Mesajlar), never blocking it.
    final nt = src('supabase/migrations/0085_tir_park_receipt_notice.sql');
    expect(nt, contains("'tirpark_payment_review'"));
    expect(nt, contains('public.get_or_create_direct_conversation(v_p.manager_id)'));
    expect(nt, contains('null;   -- a notice never stops the receipt'));
    expect(nt.toLowerCase().contains('drop table') || nt.toLowerCase().contains('delete from'), isFalse);
    expect(src('supabase/tests/local/run_local.sh'), contains('123_tir_park_receipt_notice.sql'));
    // 0086: owner panel — cars by plate, money by the hour, bookings from 00:00.
    final op = src('supabase/migrations/0086_tir_park_owner_panel.sql');
    expect(op, contains('round(coalesce(p_rate, 0) * greatest(0, extract(epoch from (p_to - greatest(p_from, coalesce(p_paid_until, p_from))))) / 86400.0, 2)'));
    expect(op, contains("raise exception 'already_in'"));
    expect(op, contains('public._tir_park_today_start() - interval'));
    expect(op, contains('perform public._require_admin();'));
    expect(op.toLowerCase().contains('drop table') || op.toLowerCase().contains('delete from'), isFalse);
    expect(src('supabase/tests/local/run_local.sh'), contains('124_tir_park_owner_panel.sql'));
    expect(src('lib/features/tirpark/presentation/tir_park_booking.dart').contains('QrImageView'), isFalse, reason: 'no QR');
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains('ref.watch(tirParkManagerPendingProvider)'),
        reason: 'the red count on Profil → TIR parkı idarə edirəm');
    // 0082: the truck's plate.
    final pl = src('supabase/migrations/0082_tir_park_booking_plate.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'update tir_park_bookings set plate']) {
      expect(pl.contains(bad), isFalse, reason: bad);
    }
    expect(pl, contains("if v_plate is null then raise exception 'invalid_plate'"));
    expect(pl, contains("'plate', b.plate"), reason: 'the manager sees it');
    expect(src('supabase/tests/local/run_local.sh'), contains('120_tir_park_booking_plate.sql'));
    expect(src('lib/features/tirpark/data/tir_park_repository.dart'), contains("'p_plate': plate,"));
    expect(src('supabase/tests/local/run_local.sh'), contains('0081_tir_park_booking_card.sql'));
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart'), contains('TirParkCardBooking(park: p, s: s)'));
    expect(src('lib/features/tirpark/presentation/tir_park_detail_screen.dart'), contains('if (park.isManaged) ...['));
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
      for (final k in ['tpb_free_now', 'tpb_closed', 'tpb_full', 'tpb_calc', 'tpb_stay', 'tpb_st_payment_rejected', 'tpb_rejected_end',
                       'tpb_book', 'tpb_terms', 'tpb_st_payment_review', 'tpm_title', 'tpm_paydet_hint', 'tpm_confirm', 'tpb_upload', 'tpb_no_money']) {
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

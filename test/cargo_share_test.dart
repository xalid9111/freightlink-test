// The load card's "Paylaş" (owner's pictures, 21.11.2026): "Sürücü seç" from
// my Maşınlarım drivers (linked accounts), "Sürücüyə göndər" = a message in
// Mesajlar with the load's link; no drivers = the link at once; WhatsApp;
// a TırLink link in a chat opens the page in the app; the promo marks stand
// left of the heart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/presentation/widgets/cargo_share_sheet.dart';
import 'package:freightlink/features/chat/data/group_repository.dart';
import 'package:freightlink/features/chat/domain/message_repository.dart';
import 'package:freightlink/features/chat/presentation/providers/chat_providers.dart';
import 'package:freightlink/features/chat/presentation/widgets/chat_scroll.dart';
import 'package:freightlink/features/fleet/domain/fleet.dart';
import 'package:freightlink/features/fleet/presentation/fleet_providers.dart';
import 'package:freightlink/models/message_model.dart';
import 'package:freightlink/repositories/profile_repository.dart';

String src(String p) => File(p).readAsStringSync();
AppStrings lang(String l) => AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/$l.json')) as Map));

class _Groups implements GroupRepository {
  final opened = <String>[];
  @override
  Future<ConversationModel> openDirect(String userId) async {
    opened.add(userId);
    return ConversationModel(id: 'conv-$userId', cargoOwnerId: 'me', carrierUserId: userId);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Messages implements MessageRepository {
  final sent = <(String, String, String)>[];
  @override
  Future<void> send({required String conversationId, required String senderId, required String receiverId, required String message}) async =>
      sent.add((conversationId, receiverId, message));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('my drivers: linked accounts only, once each with their plates, never someone else\'s trucks', () {
    const data = FleetData(trucks: [
      FleetTruck(id: 't1', ownerId: 'me', name: 'Volvo', plate: '99-JM-547', driverName: 'Rauf Məmmədov', driverId: 'd1'),
      FleetTruck(id: 't2', ownerId: 'me', name: 'MAN', plate: '10-UT-826', driverName: 'Rauf Məmmədov', driverId: 'd1'),
      FleetTruck(id: 't3', ownerId: 'me', name: 'DAF', plate: '77-BX-903', driverName: 'Elvin Əliyev', driverId: 'd2'),
      FleetTruck(id: 't4', ownerId: 'me', name: 'Scania', plate: '90-KR-271', driverName: 'Yalnız ad'),
      FleetTruck(id: 't5', ownerId: 'x', name: 'Iveco', plate: '01-AA-001', driverName: 'Mən', driverId: 'me'),
    ]);
    final d = shareDriversOf(data, 'me');
    expect([for (final x in d) x.userId], ['d2', 'd1'], reason: 'by name; the typed-only driver and my own driving are left out');
    expect(d.firstWhere((x) => x.userId == 'd1').plates, ['99-JM-547', '10-UT-826']);
  });

  test('the text sent: route · details · price', () {
    expect(cargoShareText(route: '🇦🇿 Bakı → 🇷🇺 Sankt-Peterburq', details: '22 T · Ref · 30 noy', price: '5 100 USD'),
        '🇦🇿 Bakı → 🇷🇺 Sankt-Peterburq · 22 T · Ref · 30 noy · 5 100 USD');
  });

  test('a TırLink link in a chat opens the page in the app; other links stay outside', () {
    expect(appPathOf(Uri.parse('https://tirlink.app/#/cargo/abc')), '/cargo/abc');
    expect(appPathOf(Uri.parse('https://www.tirlink.app/#/cargo/abc')), '/cargo/abc');
    expect(appPathOf(Uri.parse('https://example.com/#/cargo/abc')), isNull);
    expect(appPathOf(Uri.parse('https://tirlink.app/')), isNull);
    expect(src('lib/features/chat/presentation/widgets/chat_scroll.dart'), contains('GoRouter.of(context).go(inApp);'));
  });

  testWidgets('Sürücü seç: search, pick one, Sürücüyə göndər → a message with the load link in Mesajlar', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final groups = _Groups();
    final messages = _Messages();
    const drivers = [
      ShareDriver(userId: 'd1', name: 'Rauf Məmmədov', plates: ['99-JM-547']),
      ShareDriver(userId: 'd2', name: 'Elvin Əliyev', plates: ['77-BX-903']),
    ];
    await t.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(lang('az')),
        currentUserIdProvider.overrideWithValue('me'),
        groupRepositoryProvider.overrideWithValue(groups),
        messageRepositoryProvider.overrideWithValue(messages),
        publicProfileProvider.overrideWith((ref, id) async => null),
        fleetProvider.overrideWith((ref) async => const FleetData()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: c,
                isScrollControlled: true,
                builder: (_) => CargoShareSheet(drivers: drivers, text: 'Bakı → Sankt-Peterburq · 5 100 USD', url: 'https://tirlink.app/#/cargo/c1', strings: lang('az')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Sürücü seç'), findsOneWidget);
    expect(find.text('2 sürücü'), findsOneWidget);
    expect(find.byKey(const ValueKey('share-whatsapp')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('share-send'))).onPressed, isNull, reason: 'nobody picked yet');
    await t.enterText(find.byKey(const ValueKey('share-search')), '77-bx');
    await t.pump();
    expect(find.byKey(const ValueKey('share-driver-d1')), findsNothing, reason: 'search by plate');
    await t.enterText(find.byKey(const ValueKey('share-search')), '');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('share-driver-d1')));
    await t.pump();
    expect(find.textContaining('Rauf Məmmədov'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('share-send')));
    await t.pumpAndSettle();
    expect(groups.opened, ['d1']);
    expect(messages.sent.single.$2, 'd1');
    expect(messages.sent.single.$3, contains('https://tirlink.app/#/cargo/c1'));
    expect(find.text('Göndərildi ✓ — Mesajlar-da'), findsOneWidget);
    expect(find.text('Sürücü seç'), findsNothing, reason: 'the sheet closes');
  });

  test('wired: Paylaş uses the driver sheet; the marks stand by the heart, not over the price', () {
    final c = src('lib/features/cargo/presentation/widgets/cargo_card.dart');
    expect(c, contains('Future<void> share() => shareCargo('));
    final marks = c.indexOf("key: const ValueKey('row-marks')");
    expect(marks, greaterThan(c.indexOf('// İrəli çək / VIP / Premium left of the heart')));
    expect(marks, lessThan(c.indexOf("key: const ValueKey('row-heart')")));
    expect(src('lib/features/cargo/presentation/widgets/cargo_share_sheet.dart'), contains('if (drivers.isEmpty) {'),
        reason: 'no drivers: the link at once');
  });
}

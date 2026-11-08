// Profil (owner's two-screen design, 04.11.2026): one entry each for
// "Şəxsi məlumatlarım", "Mənim fəaliyyətim" and "TIR Parkı"; Admin Panel for
// every platform admin (an appointed admin must get in), Maliyyə only for
// the finance owner.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/admin/presentation/admin_shell.dart';
import 'package:freightlink/features/admin/presentation/head_admin.dart';
import 'package:freightlink/features/ads/presentation/ads_providers.dart';
import 'package:freightlink/features/auth/data/activities_repository.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/profile_screen.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/finance/presentation/finance_providers.dart';
import 'package:freightlink/features/services/presentation/services_providers.dart';
import 'package:freightlink/features/tirpark/data/tir_park_repository.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/repositories/profile_page_repository.dart';
import 'package:freightlink/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _NameRepo implements ProfileRepository {
  final saved = <String>[];
  @override
  Future<void> updateName(String name) async => saved.add(name);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoActs implements ActivitiesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _admin = AppUser(id: 'u1', email: 'a@b.az', fullName: 'SSD', role: 'admin', isVerified: true);
const _driver = AppUser(id: 'u2', email: 'd@b.az', fullName: 'Elvin', role: 'carrier', isVerified: true);

Widget _app(Widget home, {AppUser user = _admin, bool head = false, bool finance = false, int tirWaiting = 0, ProfileRepository? repo}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        authStateProvider.overrideWith((ref) => Stream.value(user)),
        publicProfileProvider.overrideWith((ref, id) async => null),
        profileDetailsProvider.overrideWith((ref, id) async => null),
        myActivitiesProvider.overrideWith((ref) => MyActivitiesController(_NoActs(), null)),
        tirParkManagerPendingProvider.overrideWith((ref) async => tirWaiting),
        tirParkPendingWorkersProvider.overrideWith((ref) async => 0),
        myWorkParksProvider.overrideWith((ref) async => const <TirParkWorkPlace>[]),
        isHeadAdminProvider.overrideWith((ref) async => head),
        isFinanceAdminProvider.overrideWith((ref) async => finance),
        myServiceProvider.overrideWith((ref) async => null),
        adsOrderingEnabledProvider.overrideWith((ref) async => true),
        myAdOrdersProvider.overrideWith((ref) => Stream.value(const [])),
        if (repo != null) profileRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Profil: one entry each; no role buttons or activity links on the main page', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const ProfileScreen(), tirWaiting: 2));
    await tester.pumpAndSettle();
    // The card (owner's picture, 04.11.2026): cover + photo over its edge,
    // the account's own name and role — right on the Profil tab.
    expect(find.byKey(const ValueKey('profile-summary')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-tab-cover-edit')), findsOneWidget, reason: 'the cover can be changed here');
    expect(find.text('SSD'), findsOneWidget, reason: 'the signed-in user\'s name, not a fixed text');
    expect(find.text('Administrator'), findsOneWidget);
    final cover = tester.getRect(find.byKey(const ValueKey('profile-tab-cover-edit')));
    final photo = tester.getRect(find.byKey(const ValueKey('profile-summary-photo')));
    final card = tester.getRect(find.byKey(const ValueKey('profile-summary')));
    expect(photo.top, lessThan(card.top + 120), reason: 'the photo starts on the cover');
    expect(photo.bottom, greaterThan(card.top + 120), reason: '…and reaches below its edge');
    expect(cover.top, greaterThan(card.top));
    expect(find.text('Şəxsi məlumatlarım'), findsOneWidget);
    expect(find.text('Ad, e-poçt, telefon və doğum tarixi'), findsOneWidget);
    expect(find.text('Mənim fəaliyyətim'), findsOneWidget);
    expect(find.text('Rollarım, yüklərim və xidmətlərim'), findsOneWidget);
    expect(find.text('TIR Parkı'), findsOneWidget);
    expect(find.text('Parkım və işçi dəvətləri'), findsOneWidget);
    // "Park rezervasiyalarım" right under "TIR Parkı" (owner, 06.11.2026).
    expect(find.text('Park rezervasiyalarım'), findsOneWidget);
    expect(find.text('Rezervasiyalar və statuslar'), findsOneWidget);
    final tir = tester.getRect(find.byKey(const ValueKey('pf-tirpark')));
    final book = tester.getRect(find.byKey(const ValueKey('pf-bookings')));
    expect(book.top, greaterThanOrEqualTo(tir.bottom - 1), reason: 'directly under TIR Parkı');
    expect(book.top - tir.bottom, lessThan(4), reason: 'nothing in between');
    expect(find.byKey(const ValueKey('pf-badge')), findsOneWidget, reason: 'the TIR count still shows on Profil');
    expect(find.byKey(const ValueKey('act-carrier')), findsNothing, reason: 'the roles moved to "Mənim fəaliyyətim"');
    expect(find.text('Yüklərim'), findsNothing);
    expect(find.text('İş Mərkəzi'), findsNothing);
    expect(find.byKey(const ValueKey('profile-age')), findsNothing, reason: 'personal details on their own page');
    expect(find.text('Hesab və görünüş'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-text-size')), findsOneWidget, reason: 'text size stays in Profil (24.10.2026)');
  });

  testWidgets('Admin Panel for every platform admin; Maliyyə only for the finance owner', (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // An admin the owner appointed (owner, 04.11.2026): Admin Panel, no Maliyyə.
    await tester.pumpWidget(_app(const ProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-head-admin')), findsOneWidget);
    expect(find.text('Admin idarəetməsi'), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-admin')), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-finance')), findsNothing);
    // A user: nothing.
    await tester.pumpWidget(_app(const ProfileScreen(), user: _driver, head: true, finance: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-head-admin')), findsNothing);
    // The Baş admin: the group with both.
    await tester.pumpWidget(_app(const ProfileScreen(), head: true, finance: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-head-admin')), findsOneWidget);
    expect(find.text('Baş admin idarəetməsi'), findsOneWidget);
    expect(find.text('Yalnız Baş admin'), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-finance')), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-admin')), findsOneWidget);
  });

  testWidgets('a direct /admin link: an appointed admin gets in, a user does not', (tester) async {
    await tester.pumpWidget(_app(const AdminShell(section: 'dashboard'), user: _driver));
    await tester.pumpAndSettle();
    expect(find.text('Giriş qadağandır'), findsOneWidget);
    expect(find.text('Bu bölmə yalnız administratorlar üçündür.'), findsOneWidget);
    expect(src('lib/features/admin/presentation/admin_shell.dart'), isNot(contains('isHeadAdminProvider')),
        reason: 'an admin is never stopped for not being the Baş admin');
  });

  testWidgets('Mənim fəaliyyətim: roles (2 × 2) and every activity section, as before', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const ProfileActivityScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Mənim fəaliyyətim'), findsOneWidget);
    expect(find.text('Fəaliyyət rollarım'), findsOneWidget);
    for (final k in ['act-carrier', 'act-shipper', 'act-service', 'act-seller']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    final a = tester.getTopLeft(find.byKey(const ValueKey('act-carrier')));
    final c = tester.getTopLeft(find.byKey(const ValueKey('act-service')));
    expect(c.dy, greaterThan(a.dy), reason: 'two in a row: Usta / Servis under Daşıyıcı');
    expect(find.text('Fəaliyyət bölmələrim'), findsOneWidget);
    for (final t in ['Yüklərim', 'Səhifəm və kataloqum', 'İş Mərkəzi']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // The old banner ads are not offered in Profil any more (owner,
    // 06.11.2026) — even with the admin's switch on; only existing orders keep the row.
    expect(find.text('Reklam sifarişi'), findsNothing);
  });

  testWidgets('TIR Parkı: park management and work at a park; no "Dayanacaq əlavə et" (0100); bookings on Profil', (tester) async {
    await tester.pumpWidget(_app(const ProfileTirParkScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-tirpark-manage')), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-tirpark-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-tirpark-stop')), findsNothing);
    expect(find.text('Dayanacaq əlavə et'), findsNothing);
    expect(find.byKey(const ValueKey('pf-tirpark-bookings')), findsNothing);
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    expect(p.contains('/tirpark?add='), isFalse);
    expect(p, contains("key: const ValueKey('pf-bookings'),"));
    expect(p, contains("onTap: () => context.pushOnce('/tirpark/bookings'),"), reason: 'the same bookings screen');
  });

  testWidgets('Şəxsi məlumatlarım: name, e-mail, phone and birth date in one place', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const ProfilePersonalScreen()));
    await tester.pumpAndSettle();
    expect(find.text('a@b.az'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-age')), findsOneWidget);
    // Owner, 09.11.2026: no pencil on top; the name field below instead.
    expect(find.byTooltip(_az.t('profile_name_edit')), findsNothing);
    expect(find.byKey(const ValueKey('profile-name-field')), findsOneWidget);
  });

  testWidgets('Şəxsi məlumatlarım (owner, 09.11.2026): order name · e-mail · phone · birth date · Yadda saxla; the saved name stays on top; emptied = faint placeholder; saving works', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _NameRepo();
    await tester.pumpWidget(_app(const ProfilePersonalScreen(), user: _driver, repo: repo));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('profile-name-field'));
    expect(tester.widget<TextField>(field).controller!.text, 'Elvin', reason: 'starts with the saved name');
    // The order, top to bottom.
    final ys = [
      tester.getTopLeft(field).dy,
      tester.getTopLeft(find.text('d@b.az')).dy,
      tester.getTopLeft(find.byIcon(Icons.phone_outlined)).dy,
      tester.getTopLeft(find.byKey(const ValueKey('profile-age'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('profile-save'))).dy,
    ];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: 'item $i');
    }
    // Emptied: the faint placeholder; saving an empty name is refused clearly.
    await tester.enterText(field, '');
    await tester.pump();
    expect(tester.widget<TextField>(field).decoration!.hintText, _az.t('profile_name_label'));
    expect(find.text(_az.t('profile_name_label')), findsOneWidget, reason: 'the placeholder shows');
    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pump();
    expect(repo.saved, isEmpty);
    expect(find.text(_az.t('register_name_required')), findsOneWidget);
    // A new name is saved; the saved name on top stays visible meanwhile.
    await tester.enterText(field, 'Elvin Logistics MMC');
    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(repo.saved, ['Elvin Logistics MMC']);
    expect(find.text(_az.t('profile_name_saved')), findsOneWidget);
    expect(tester.widget<TextField>(field).controller!.text, 'Elvin Logistics MMC', reason: 'what was saved stays in the field');
    expect(find.byWidgetPredicate((w) => w is Text && w.data == 'Elvin'), findsOneWidget, reason: 'the saved name on top until the account is read again');
  });

  test('routes and the server-side rule are wired', () {
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("GoRoute(path: 'personal'"));
    expect(r, contains("GoRoute(path: 'activity'"));
    expect(r, contains("GoRoute(path: 'tirpark'"));
    final h = src('lib/features/admin/presentation/head_admin.dart');
    expect(h, contains('isFinanceAdminProvider'));
    expect(h, contains('founderIds()'));
    expect(src('lib/features/admin/presentation/admin_shell.dart'), contains("'Bu bölmə yalnız administratorlar üçündür.'"));
  });
}

// Profil (owner's two-screen design, 04.11.2026): one entry each for
// "Şəxsi məlumatlarım", "Mənim fəaliyyətim" and "TIR Parkı"; "Baş admin
// idarəetməsi" (Maliyyə, Admin Panel) only for the Baş admin, also behind a
// direct /admin link.
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
import 'package:freightlink/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _NoActs implements ActivitiesRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _admin = AppUser(id: 'u1', email: 'a@b.az', fullName: 'SSD', role: 'admin', isVerified: true);
const _driver = AppUser(id: 'u2', email: 'd@b.az', fullName: 'Elvin', role: 'carrier', isVerified: true);

Widget _app(Widget home, {AppUser user = _admin, bool head = false, bool finance = false, int tirWaiting = 0}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        authStateProvider.overrideWith((ref) => Stream.value(user)),
        publicProfileProvider.overrideWith((ref, id) async => null),
        myActivitiesProvider.overrideWith((ref) => MyActivitiesController(_NoActs(), null)),
        tirParkManagerPendingProvider.overrideWith((ref) async => tirWaiting),
        tirParkPendingWorkersProvider.overrideWith((ref) async => 0),
        myWorkParksProvider.overrideWith((ref) async => const <TirParkWorkPlace>[]),
        isHeadAdminProvider.overrideWith((ref) async => head),
        isFinanceAdminProvider.overrideWith((ref) async => finance),
        myServiceProvider.overrideWith((ref) async => null),
        adsOrderingEnabledProvider.overrideWith((ref) async => true),
        myAdOrdersProvider.overrideWith((ref) => Stream.value(const [])),
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
    expect(find.text('Şəxsi məlumatlarım'), findsOneWidget);
    expect(find.text('Ad, e-poçt, telefon və doğum tarixi'), findsOneWidget);
    expect(find.text('Mənim fəaliyyətim'), findsOneWidget);
    expect(find.text('Rollarım, yüklərim və xidmətlərim'), findsOneWidget);
    expect(find.text('TIR Parkı'), findsOneWidget);
    expect(find.text('Parkım, işçi dəvətləri və rezervasiyalar'), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-badge')), findsOneWidget, reason: 'the TIR count still shows on Profil');
    expect(find.byKey(const ValueKey('act-carrier')), findsNothing, reason: 'the roles moved to "Mənim fəaliyyətim"');
    expect(find.text('Yüklərim'), findsNothing);
    expect(find.text('İş Mərkəzi'), findsNothing);
    expect(find.byKey(const ValueKey('profile-age')), findsNothing, reason: 'personal details on their own page');
    expect(find.text('Hesab və görünüş'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-text-size')), findsOneWidget, reason: 'text size stays in Profil (24.10.2026)');
  });

  testWidgets('Baş admin idarəetməsi: only the Baş admin sees Maliyyə and Admin Panel', (tester) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // An ordinary administrator: nothing.
    await tester.pumpWidget(_app(const ProfileScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-head-admin')), findsNothing);
    expect(find.text('Admin Panel'), findsNothing);
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

  testWidgets('a direct /admin link: an ordinary administrator gets "Giriş qadağandır"', (tester) async {
    await tester.pumpWidget(_app(const AdminShell(section: 'dashboard')));
    await tester.pumpAndSettle();
    expect(find.text('Giriş qadağandır'), findsOneWidget);
    expect(find.text('Bu bölmə yalnız Baş admin üçündür.'), findsOneWidget);
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
    for (final t in ['Yüklərim', 'Səhifəm və kataloqum', 'İş Mərkəzi', 'Reklam sifarişi']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('TIR Parkı: park management, work at a park, bookings', (tester) async {
    await tester.pumpWidget(_app(const ProfileTirParkScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pf-tirpark-manage')), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-tirpark-work')), findsOneWidget);
    expect(find.byKey(const ValueKey('pf-tirpark-bookings')), findsOneWidget);
  });

  testWidgets('Şəxsi məlumatlarım: name, e-mail, phone and birth date in one place', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const ProfilePersonalScreen()));
    await tester.pumpAndSettle();
    expect(find.text('a@b.az'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-age')), findsOneWidget);
    expect(find.byTooltip(_az.t('profile_name_edit')), findsOneWidget);
  });

  test('routes and the server-side rule are wired', () {
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("GoRoute(path: 'personal'"));
    expect(r, contains("GoRoute(path: 'activity'"));
    expect(r, contains("GoRoute(path: 'tirpark'"));
    final h = src('lib/features/admin/presentation/head_admin.dart');
    expect(h, contains('isFinanceAdminProvider'));
    expect(h, contains('founderIds()'));
    expect(src('lib/features/admin/presentation/admin_shell.dart'), contains("'Bu bölmə yalnız Baş admin üçündür.'"));
  });
}

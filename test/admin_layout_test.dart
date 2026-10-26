// Admin panel layout guard: every section must lay out without a single
// Flutter error on iPhone (390×844), a small phone (320×568) and desktop
// (1280×800), with long Azerbaijani names, many rows and badges. Uses the
// app's real font (Arial = Liberation Sans) so text widths are realistic.
// Supabase is not used: every admin data provider is overridden.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/site/site_access.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/admin/presentation/admin_shell.dart';
import 'package:freightlink/features/admin/presentation/admin_providers.dart';
import 'package:freightlink/features/admin/presentation/admin_services_page.dart';
import 'package:freightlink/features/ads/presentation/ads_providers.dart';

Future<void> _loadFonts() async {
  final arial = FontLoader('Arial');
  for (final f in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
    arial.addFont(Future.value(ByteData.sublistView(File('assets/fonts/LiberationSans-$f.ttf').readAsBytesSync())));
  }
  await arial.load();
}

const uid = '11111111-2222-3333-4444-555555555555';
List<Map<String, dynamic>> rows(int n, Map<String, dynamic> Function(int i) f) => [for (var i = 0; i < n; i++) f(i)];
final users = rows(30, (i) => {
      'id': '$i${uid.substring(i.toString().length)}', 'full_name': 'İstifadəçi Çox Uzun Adlı Şirkət MMC $i', 'email': 'user$i@example.com',
      'phone': '+99450123456$i', 'role': ['cargo_owner', 'carrier', 'driver', 'admin'][i % 4], 'is_active': i % 7 != 0,
      'is_verified': i.isEven, 'created_at': '2026-10-1${i % 9}T10:00:00Z', 'blocked_until': null, 'block_reason': null,
    });
final cargo = rows(30, (i) => {
      'id': 'c$i${uid.substring(i.toString().length + 1)}', 'owner_id': users[i]['id'], 'title': 'Yük $i', 'pickup_city': 'Bakı',
      'pickup_country': 'AZ', 'destination_city': 'İstanbul', 'destination_country': 'TR', 'status': ['new', 'agreed', 'in_transit'][i % 3],
      'weight_kg': 12000.0 + i, 'offered_price': 2500.0, 'currency': 'USD', 'created_at': '2026-10-13T09:00:00Z', 'is_hidden': false,
      'cargo_type': 'Tekstil', 'truck_type': 'Tent', 'pickup_date': '2026-10-15',
    });
final stats = <String, dynamic>{
  'users_total': 1234, 'cargo_total': 567, 'offers_total': 89, 'shipments_total': 45, 'reports_open': 3,
  'users_new_1d': 5, 'users_new_7d': 40, 'users_new_30d': 150, 'cargo_new_1d': 2, 'cargo_new_7d': 20, 'cargo_new_30d': 80,
};

Widget app(String section) => ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(const AppUser(id: uid, email: 'a@b.az', fullName: 'Admin Adı', role: 'admin', isVerified: true))),
        adminStatsProvider.overrideWith((ref) async => stats),
        siteStatusProvider.overrideWith((ref) => Stream.value(SiteStatus.open)),
        adminUsersProvider.overrideWith((ref) => Stream.value(users)),
        adminCargoProvider.overrideWith((ref) => Stream.value(cargo)),
        adminOffersProvider.overrideWith((ref) => Stream.value(const [])),
        adminShipmentsProvider.overrideWith((ref) => Stream.value(const [])),
        adminReportsProvider.overrideWith((ref) => Stream.value(const [])),
        adminAuditProvider.overrideWith((ref) => Stream.value(const [])),
        adminAdOrdersProvider.overrideWith((ref) => Stream.value(const [])),
        adminServiceCountsProvider.overrideWith((ref) async => {'pending': 2, 'claims': 1, 'reports': 0}),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: AdminShell(section: section)),
    );

void main() {
  setUpAll(() async {
    await _loadFonts();
    dotenv.testLoad(fileInput: 'APP_ENV=test');
  });
  const sizes = {'iphone390': Size(390, 844), 'small320': Size(320, 568), 'desktop1280': Size(1280, 800)};
  for (final entry in sizes.entries) {
    for (final s in adminSections) {
      testWidgets('${entry.key} ${s.key}', (tester) async {
        tester.view.physicalSize = entry.value * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final errors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) => errors.add('${d.context?.toDescription() ?? ''} :: ${d.exceptionAsString().split('\n').first}');
        await tester.pumpWidget(app(s.key));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Phones: the section list lives in the drawer — open it too.
        if (entry.value.width < 900) {
          await tester.tap(find.byTooltip('Open navigation menu'));
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        FlutterError.onError = prev;
        // Two sections (Services, WhatsApp PoC) read the Supabase client
        // directly while building; there is no Supabase in unit tests. That
        // is the test environment, not a layout problem — everything else
        // (layout, overflow, "RenderBox was not laid out", …) fails here.
        final real = errors.where((e) => !e.contains('You must initialize the supabase instance')).toList();
        expect(real, isEmpty, reason: real.toSet().join('\n'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}

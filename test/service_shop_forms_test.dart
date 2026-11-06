// Usta / Servis and Mağaza profile forms (owner's pictures, 06.11.2026):
// one long scrolled page each, in the same order — logo + background, name
// (only a faint placeholder), kinds, about, city + address + map, phone +
// WhatsApp, hours, photos, save. The shop shows only shop fields (new and
// used parts together); the service keeps all its own kinds and fields.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/covers/profile_covers.dart';
import 'package:freightlink/features/services/data/services_repository.dart';
import 'package:freightlink/features/services/presentation/service_edit_screen.dart';
import 'package:freightlink/features/services/presentation/services_providers.dart';
import 'package:freightlink/models/service_models.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _FakeServices implements ServicesRepository {
  final ServiceProvider? existing;
  _FakeServices(this.existing);
  @override
  Future<ServiceProvider?> mine(String uid) async => existing;
  @override
  Future<ServiceProvider?> byId(String id) async => existing;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeMedia extends CoverRepository {
  @override
  Future<PlaceMedia> serviceMedia(String id) async => const PlaceMedia();
}

ServiceCategory _c(String id, String az, int order) => ServiceCategory(id: id, names: {'az': az}, icon: 'parts', sortOrder: order, isActive: true);

final _cats = [
  _c('spare_parts', 'Ehtiyat hissələri satışı', 0),
  _c('tyres', 'Təkər təmiri', 40),
  _c('tow', 'Evakuator', 60),
  _c('shop_new', 'Yeni ehtiyat hissələri', 200),
  _c('shop_used', 'İşlənmiş ehtiyat hissələri', 201),
  _c('shop_engine', 'Mühərrik', 202),
  _c('shop_tyres', 'Təkər və disk', 204),
];

ServiceProvider _svc(List<String> cats) => ServiceProvider(
      id: 's1', ownerId: 'u1', kind: 'center', name: 'Mənim yerim', categories: cats, lat: 40.4, lng: 49.8,
      isMobile: false, is24h: false, isActive: true, status: 'approved', isVerified: false, addedByAdmin: false,
      photos: const [], ratingAvg: 0, ratingCount: 0,
    );

Widget _edit({required bool shop, ServiceProvider? existing, bool byId = false}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        currentUserIdProvider.overrideWithValue('u1'),
        servicesRepositoryProvider.overrideWithValue(_FakeServices(existing)),
        coverRepositoryProvider.overrideWithValue(_FakeMedia()),
        serviceCategoriesProvider.overrideWith((ref) async => _cats),
        myServiceProvider.overrideWith((ref) async => existing),
      ],
      child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (c, st) => ServiceEditScreen(id: byId ? 's1' : null, initialKind: 'center', shop: shop)),
      ])),
    );

Finder _chip(String label) => find.widgetWithText(FilterChip, label);
bool _ticked(WidgetTester t, String label) => t.widget<FilterChip>(_chip(label)).selected;

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Mağaza: its own title, an empty name with the faint "Mağaza adı", new + used parts together, no service parts', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_edit(shop: true));
    await tester.pumpAndSettle();
    expect(find.text('Mağaza profili yarat'), findsOneWidget);
    final name = tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('svc-name')), matching: find.byType(TextField)));
    expect(name.controller!.text, isEmpty, reason: 'no sample name');
    expect(name.decoration!.hintText, 'Mağaza adı');
    for (final t in ['Mağazanın adı', 'Məhsul kateqoriyaları', 'Təsvir', 'Şəhər', 'Tam ünvan', 'Xəritədə yeri seç', 'Telefon', 'WhatsApp', 'İş saatları',
      'Mağaza indi açıqdır', 'Mağazanı yadda saxla', 'Loqo əlavə et', 'Fon şəkli əlavə et']) {
      expect(find.textContaining(t, findRichText: true), findsWidgets, reason: t);
    }
    await tester.tap(_chip('Yeni ehtiyat hissələri'));
    await tester.pump();
    await tester.tap(_chip('İşlənmiş ehtiyat hissələri'));
    await tester.pump();
    expect(_ticked(tester, 'Yeni ehtiyat hissələri'), isTrue);
    expect(_ticked(tester, 'İşlənmiş ehtiyat hissələri'), isTrue, reason: 'both at the same time');
    // Never the service parts.
    for (final t in ['Təkər təmiri', 'Evakuator', 'Ehtiyat hissələri satışı', 'Növ', 'İxtisas', 'Mobil xidmət (yerə gəlirəm)']) {
      expect(find.text(t), findsNothing, reason: t);
    }
    expect(find.byType(SegmentedButton<String>), findsNothing);
    // The kinds in the owner's order, new parts first.
    final xs = [for (final id in ['shop_new', 'shop_used', 'shop_engine', 'shop_other']) tester.getTopLeft(find.byKey(ValueKey('svc-kind-$id')))];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i].dy > xs[i - 1].dy || (xs[i].dy == xs[i - 1].dy && xs[i].dx > xs[i - 1].dx), isTrue, reason: 'order $i');
    }
    // Telefon | WhatsApp and İş saatları | 24/7 side by side.
    expect(tester.getTopLeft(find.text('WhatsApp', findRichText: true)).dy, tester.getTopLeft(find.text('Telefon *', findRichText: true)).dy);
    expect(tester.getCenter(find.byKey(const ValueKey('svc-24h'))).dx, greaterThan(250));
  });

  testWidgets('both forms follow the same order, top to bottom', (tester) async {
    await _phone(tester);
    for (final shop in [true, false]) {
      await tester.pumpWidget(_edit(shop: shop));
      await tester.pumpAndSettle();
      final keys = ['svc-logo', 'svc-name', 'svc-kinds', 'svc-city', 'svc-map-pick', 'svc-phone', 'svc-photo-add', 'svc-save'];
      final ys = [for (final k in keys) tester.getTopLeft(find.byKey(ValueKey(k))).dy];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: '${keys[i - 1]} before ${keys[i]} (shop: $shop)');
      }
      expect(tester.getTopLeft(find.byKey(const ValueKey('svc-cover'))).dy, tester.getTopLeft(find.byKey(const ValueKey('svc-logo'))).dy,
          reason: 'logo and background side by side');
      expect(tester.takeException(), isNull, reason: 'nothing overflows on a 390 pt phone');
    }
  });

  testWidgets('Usta / Servis: its own title and placeholder; every service kind and field stays; no shop kinds', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_edit(shop: false));
    await tester.pumpAndSettle();
    expect(find.text('Usta / Servis profili yarat'), findsOneWidget);
    final name = tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('svc-name')), matching: find.byType(TextField)));
    expect(name.controller!.text, isEmpty);
    expect(name.decoration!.hintText, 'Servis adı');
    for (final t in ['Təkər təmiri', 'Evakuator', 'Ehtiyat hissələri satışı']) {
      expect(_chip(t), findsOneWidget, reason: t);
    }
    for (final t in ['Yeni ehtiyat hissələri', 'İşlənmiş ehtiyat hissələri', 'Mühərrik']) {
      expect(_chip(t), findsNothing, reason: t);
    }
    expect(find.byType(SegmentedButton<String>), findsOneWidget, reason: 'Usta / Servis mərkəzi kept');
    expect(find.text('Mobil xidmət (yerə gəlirəm)'), findsOneWidget);
    expect(find.text('Servis profilini yadda saxla'), findsOneWidget);
  });

  testWidgets('saving a shop without a product kind is refused clearly', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_edit(shop: true));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('svc-name')), 'Mənim mağazam');
    await tester.enterText(find.byKey(const ValueKey('svc-phone')), '+994501234567');
    await tester.tap(find.byKey(const ValueKey('svc-save')));
    await tester.pump();
    expect(find.text('Ən azı bir məhsul növü seçin.'), findsOneWidget);
  });

  testWidgets('an existing shop opens as a shop; a service gets the shop kinds added, its own kept', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_edit(shop: false, byId: true, existing: _svc(['spare_parts', 'shop_new', 'shop_used'])));
    await tester.pumpAndSettle();
    expect(find.text('Mağazanı redaktə et'), findsOneWidget);
    expect(_ticked(tester, 'Yeni ehtiyat hissələri'), isTrue);
    expect(_ticked(tester, 'İşlənmiş ehtiyat hissələri'), isTrue);
    final name = tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('svc-name')), matching: find.byType(TextField)));
    expect(name.controller!.text, 'Mənim yerim', reason: 'the saved name is shown for editing');

    await tester.pumpWidget(_edit(shop: true, existing: _svc(['tyres'])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('svc-shop-note')), findsOneWidget);
    expect(_chip('Təkər təmiri'), findsNothing, reason: 'the shop form shows shop fields only');

    await tester.pumpWidget(_edit(shop: false, byId: true, existing: _svc(['tyres', 'spare_parts'])));
    await tester.pumpAndSettle();
    expect(find.text('Profili redaktə et'), findsOneWidget, reason: 'a service that also sells parts stays a service');
    expect(_ticked(tester, 'Təkər təmiri'), isTrue);
    expect(_ticked(tester, 'Ehtiyat hissələri satışı'), isTrue);
  });

  test('the texts always match the app: the web build reads them fresh, never an old cached copy', () {
    final l = src('lib/core/localization/localization_service.dart');
    expect(l, contains("import 'fresh_text_stub.dart' if (dart.library.js_interop) 'fresh_text_web.dart' as fresh;"));
    expect(l, contains('await fresh.fetchFreshText(path) ?? await rootBundle.loadString(path)'));
    expect(src('lib/core/localization/fresh_text_web.dart'), contains("RequestInit(cache: 'no-cache')"));
  });

  test('wired: logo / background saved with the profile, map picker, 10 photos, shop kinds off the Servislər chips, SQL 0097', () {
    final edit = src('lib/features/services/presentation/service_edit_screen.dart');
    expect(edit, contains('await _saveMedia(saved.id);'));
    expect(edit, contains('if (_logoDirty) await media.setServiceLogo(id, _logoUrl);'));
    expect(edit, contains('static const _maxPhotos = 10;'));
    expect(edit, contains('class _MapPlacePicker'));
    expect(edit.contains('_name.text = me!.fullName'), isFalse, reason: 'no name filled in for the user');
    expect(src('lib/features/services/presentation/services_map_screen.dart'), contains('if (!c.isShopKind) c'));
    expect(src('lib/features/services/presentation/service_detail_screen.dart'), contains('avatar: roundPicture(\n        media.logo,'));
    final sql = src('supabase/migrations/0097_service_shop_profile.sql');
    expect(sql, contains('on conflict (id) do nothing'));
    expect(sql, contains("public._place_cover_ok(p_url, 'service', false)"));
    expect(sql, contains('grant select (logo_url) on table public.service_providers to authenticated;'));
    for (final bad in ['drop table', 'truncate', 'delete from']) {
      expect(sql.toLowerCase().contains(bad), isFalse, reason: bad);
    }
  });
}

// Six new load types, other spellings and the remembered tile (owner,
// 25.10.2026, 0063). Server side: supabase/tests/local/100_cargo_new_types.sql.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/domain/cargo_categories.dart';
import 'package:freightlink/features/cargo/domain/cargo_pictures.dart';
import 'package:freightlink/features/cargo/domain/truck_types.dart';
import 'package:freightlink/features/cargo/presentation/providers/category_providers.dart';
import 'package:freightlink/models/cargo_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

CargoModel load(String? truck) => CargoModel(
      id: 'x',
      ownerId: 'o',
      pickupCountry: 'Azerbaijan',
      pickupCity: 'Baku',
      destinationCountry: 'Georgia',
      destinationCity: 'Tbilisi',
      weightKg: 1000,
      pickupDate: DateTime(2026, 10, 25),
      offeredPrice: 100,
      truckType: truck,
    );

int pngWidth(List<int> b) => (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
int pngHeight(List<int> b) => (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];

void main() {
  test('six new truck types: icons day + night (300 x 145), six languages, form chips', () {
    for (final c in kNewTruckTypes) {
      expect(kTruckTypes, contains(c));
      for (final night in [false, true]) {
        final bytes = File(categoryIconAsset(c, night: night)).readAsBytesSync();
        expect((pngWidth(bytes), pngHeight(bytes)), (300, 145), reason: '$c $night');
        expect(bytes[25], 6, reason: '$c $night is RGBA (transparent)');
      }
      for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final j = File('assets/i18n/$lang.json').readAsStringSync();
        expect(j.contains('"cat_$c"') && j.contains('"truck_$c"'), isTrue, reason: '$lang $c');
      }
    }
    // The first six form types keep their order (form layout unchanged).
    expect(kTruckTypes.take(6), ['tent', 'ref', 'dump', 'container', 'open', 'tanker']);
    final admin = File('lib/features/cargo/presentation/admin_cargo_pictures_page.dart').readAsStringSync();
    for (final c in kNewTruckTypes) {
      expect(admin.contains("'$c':"), isTrue, reason: 'admin name $c');
    }
  });

  test('stored truck types, any letter case or other spelling, find their tile', () {
    expect(truckCategoryOf('tent'), 'tent');
    expect(truckCategoryOf('Tent'), 'tent');
    expect(truckCategoryOf('TENT'), 'tent');
    expect(truckCategoryOf(' tent '), 'tent');
    expect(truckCategoryOf('soyuducu reff'), 'ref');
    expect(truckCategoryOf('Soyuducu'), 'ref');
    expect(truckCategoryOf('REF'), 'ref');
    expect(truckCategoryOf('Рефрижератор'), 'ref');
    expect(truckCategoryOf('Qazel'), 'gazelle');
    expect(truckCategoryOf('Gazel'), 'gazelle');
    expect(truckCategoryOf('Газель'), 'gazelle');
    expect(truckCategoryOf('Lowbed'), 'lowbed');
    expect(truckCategoryOf('Evakuator'), 'tow_truck');
    expect(truckCategoryOf('Manipulyator'), 'manipulator');
    expect(truckCategoryOf('Qapalı furqon'), 'van');
    expect(truckCategoryOf('Avtovoz'), 'car_carrier');
    expect(truckCategoryOf('open'), 'open');
    // Unknown, empty and QRUPAJ (not a truck type) find no tile.
    expect(truckCategoryOf('Mega'), isNull);
    expect(truckCategoryOf(''), isNull);
    expect(truckCategoryOf(null), isNull);
    expect(truckCategoryOf('groupage'), isNull);
  });

  test('the filter (client and fallback) uses the same rule; the load itself is not changed', () {
    const tent = CargoCategoryFilter(truckType: 'tent');
    const ref = CargoCategoryFilter(truckType: 'ref');
    expect(['tent', 'Tent', 'TENT', 'ref', 'soyuducu reff', null].where((t) => tent.matches(load(t))).length, 3);
    expect(['tent', 'Tent', 'ref', 'soyuducu reff', 'open', null].where((t) => ref.matches(load(t))).length, 2);
    final l = load('soyuducu reff');
    ref.matches(l);
    expect(l.truckType, 'soyuducu reff');
    // The picture template follows the same rule.
    expect(cargoPictureCategory(truckType: 'Tent'), 'tent');
    expect(cargoPictureCategory(truckType: 'soyuducu reff'), 'ref');
    expect(cargoPictureCategory(truckType: 'van'), 'van');
  });

  test('server query: code in any case, exact spellings, pieces — all as ilike', () {
    final t = truckTypeOrFilter('tent');
    expect(t, contains('truck_type.ilike."tent"'));
    expect(t, contains('truck_type.ilike."Tent"'));
    expect(t, contains('truck_type.ilike."TENT"'));
    final r = truckTypeOrFilter('ref');
    expect(r, contains('truck_type.ilike."*soyuducu*"'));
    expect(r, contains('truck_type.ilike."*reff*"'));
    expect(truckTypeOrFilter('gazelle'), contains('truck_type.ilike."*Газел*"'));
    // Only ilike conditions, nothing that writes.
    for (final c in kCategoryChoices.where((c) => c != 'groupage')) {
      for (final part in truckTypeOrFilter(c).split(',')) {
        expect(part.startsWith('truck_type.ilike."'), isTrue, reason: part);
      }
    }
    final repo = File('lib/features/cargo/data/cargo_repository_impl.dart').readAsStringSync();
    expect(repo.contains('query.or(truckTypeOrFilter(truckType))'), isTrue);
    expect(repo.contains('truckType == null || truckCategoryOf(c.truckType) == truckType'), isTrue);
  });

  group('remembered tile', () {
    test('kept: the tile or QRUPAJ, not big / small; unknown keys are ignored', () {
      expect(const CargoCategoryFilter(truckType: 'van', size: 'big').savedKey, 'van');
      expect(CargoCategoryFilter.fromSaved('van'), const CargoCategoryFilter(truckType: 'van'));
      expect(CargoCategoryFilter.fromSaved('groupage'), const CargoCategoryFilter(groupage: true));
      expect(CargoCategoryFilter.fromSaved(''), const CargoCategoryFilter());
      expect(CargoCategoryFilter.fromSaved('plane'), const CargoCategoryFilter());
      expect(CargoCategoryFilter.fromSaved(null), const CargoCategoryFilter());
    });

    test('saved per account, read back after a restart, never shown to another account', () async {
      SharedPreferences.setMockInitialValues({});
      await loadCargoCategoryPrefs();
      final a = ProviderContainer(overrides: [currentUserIdProvider.overrideWithValue('user-a')]);
      a.read(cargoCategoryFilterProvider.notifier).state = const CargoCategoryFilter(truckType: 'lowbed', size: 'small');
      a.read(cargoCategoryFilterProvider);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(cargoCategoryPrefsKey('user-a')), 'lowbed');
      a.dispose();

      // "Restart": a new container reads the saved tile; size is not kept.
      await loadCargoCategoryPrefs();
      final a2 = ProviderContainer(overrides: [currentUserIdProvider.overrideWithValue('user-a')]);
      expect(a2.read(cargoCategoryFilterProvider), const CargoCategoryFilter(truckType: 'lowbed'));
      a2.dispose();

      final b = ProviderContainer(overrides: [currentUserIdProvider.overrideWithValue('user-b')]);
      expect(b.read(cargoCategoryFilterProvider), const CargoCategoryFilter());
      b.dispose();
      final guest = ProviderContainer(overrides: [currentUserIdProvider.overrideWithValue(null)]);
      expect(guest.read(cargoCategoryFilterProvider), const CargoCategoryFilter());
      guest.dispose();
    });

    test('"Sıfırla" clears the remembered tile', () async {
      SharedPreferences.setMockInitialValues({cargoCategoryPrefsKey('user-a'): 'van'});
      await loadCargoCategoryPrefs();
      final c = ProviderContainer(overrides: [currentUserIdProvider.overrideWithValue('user-a')]);
      expect(c.read(cargoCategoryFilterProvider).truckType, 'van');
      c.read(cargoCategoryFilterProvider.notifier).state = const CargoCategoryFilter();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(cargoCategoryPrefsKey('user-a')), '');
      c.dispose();
    });

    test('the strip brings the chosen tile into view and keeps its sizes', () {
      final bar = File('lib/features/cargo/presentation/widgets/cargo_category_bar.dart').readAsStringSync();
      expect(bar.contains('controller: _scroll'), isTrue);
      expect(bar.contains('_reveal(ref.read(cargoCategoryFilterProvider), animate: false)'), isTrue);
      expect(bar.contains('width: 64,'), isTrue);
      expect(bar.contains('height: 27,'), isTrue);
      expect(bar.contains('scrollDirection: Axis.horizontal'), isTrue);
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('await loadCargoCategoryPrefs();'), isTrue);
    });
  });

  test('0063 is safe: one named constraint, no drop table / truncate / delete / update', () {
    final sql = File('supabase/migrations/0063_cargo_new_types.sql').readAsStringSync().toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'update public', 'drop column', 'drop policy']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(RegExp(r'drop constraint (\w+)').allMatches(sql).map((m) => m.group(1)).toSet(),
        {'cargo_image_templates_category_check'});
    expect(sql.contains("and c.conname = 'cargo_image_templates_category_check'"), isTrue);
    final run = File('supabase/tests/local/run_local.sh').readAsStringSync();
    expect(run, contains('0063_cargo_new_types.sql'));
    expect(run, contains('100_cargo_new_types.sql'));
  });
}

// Owner, 24.10.2026: a load without a picture shows an admin template of
// its type (a different one per load); a load past its loading date
// leaves the Loads page; the owner turns a load off / on (with a new
// date) in "Yüklərim" (0061). Server rules: supabase/tests/local/98_cargo_active.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/cargo_pictures.dart';
import 'package:freightlink/models/cargo_model.dart';

CargoModel load({required DateTime date, String status = 'new', bool paused = false, bool hidden = false}) => CargoModel(
      id: 'x',
      ownerId: 'o',
      pickupCountry: 'Azerbaijan',
      pickupCity: 'Baku',
      destinationCountry: 'Georgia',
      destinationCity: 'Tbilisi',
      weightKg: 1000,
      pickupDate: date,
      offeredPrice: 100,
      status: status,
      isPaused: paused,
      isHidden: hidden,
    );

String src(String p) => File(p).readAsStringSync();

void main() {
  group('template picture', () {
    final t = ['a', 'b', 'c', 'd'];
    test('no template for the type -> none (type icon)', () => expect(templateFor(const [], 'id'), isNull));
    test('one load always shows the same template', () {
      expect(templateFor(t, 'c0ffee00-1'), templateFor(t, 'c0ffee00-1'));
    });
    test('loads of one type get different templates', () {
      final used = {for (var i = 0; i < 40; i++) templateFor(t, 'load-$i')};
      expect(used.length, greaterThan(2));
    });
    test('used on tiles and on the load page; own picture still first', () {
      expect(src('lib/features/cargo/presentation/widgets/cargo_card.dart'), contains('seed: cargo.id)'));
      final pic = src('lib/features/cargo/presentation/widgets/cargo_picture.dart');
      expect(pic, contains('if ((url == null || url.isEmpty) && cat != null && seed != null)'));
      expect(src('lib/features/cargo/presentation/cargo_detail_screen.dart'), contains('] else if (template != null) ...['));
    });
  });

  group('expired / switched off', () {
    final now = DateTime(2026, 10, 24, 15, 30);
    test('the loading day itself is still listed, the next day not', () {
      expect(load(date: DateTime(2026, 10, 24)).isListedOn(now), isTrue);
      expect(load(date: DateTime(2026, 10, 23)).isExpiredOn(now), isTrue);
      expect(load(date: DateTime(2026, 10, 23)).isListedOn(now), isFalse);
      expect(load(date: DateTime(2026, 10, 30)).isListedOn(now), isTrue);
    });
    test('switched off, hidden or in a deal: not listed', () {
      final d = DateTime(2026, 10, 30);
      expect(load(date: d, paused: true).isListedOn(now), isFalse);
      expect(load(date: d, hidden: true).isListedOn(now), isFalse);
      expect(load(date: d, status: 'agreed').isListedOn(now), isFalse);
    });
    test('is_paused read from the row (missing before 0061 = on)', () {
      final row = {
        'id': 'x', 'owner_id': 'o', 'pickup_country': 'A', 'pickup_city': 'B', 'destination_country': 'C',
        'destination_city': 'D', 'weight_kg': 1, 'pickup_date': '2026-10-30', 'offered_price': 1,
      };
      expect(CargoModel.fromJson(row).isPaused, isFalse);
      expect(CargoModel.fromJson({...row, 'is_paused': true}).isPaused, isTrue);
    });
    test('every public list uses the same rule', () {
      final repo = src('lib/features/cargo/data/cargo_repository_impl.dart');
      expect('.where((c) => c.isListedOn(now))'.allMatches(repo).length, 3);
      expect(src('lib/features/ads/presentation/ads_providers.dart'), contains('c.isListedOn(DateTime.now())'));
      expect(src('lib/features/cargo/data/cargo_media_repository.dart'), contains('c.isListedOn(DateTime.now())'));
    });
    test('Yüklərim: off / on with a date; nothing is deleted', () {
      final my = src('lib/features/cargo/presentation/my_cargo_screen.dart');
      expect(my, contains("ValueKey('my-cargo-off-\${c.id}')"));
      expect(my, contains("ValueKey('my-cargo-on-\${c.id}')"));
      expect(my, contains('showDatePicker('));
      expect(my, contains('firstDate: today'));
      final media = src('lib/features/cargo/data/cargo_media_repository.dart');
      expect(media, contains("update({'is_paused': true})"));
      expect(media, contains("update({...row, 'is_paused': false})"));
      expect(my.contains('.delete('), isFalse);
    });
    test('0061 is safe and in the SQL suite', () {
      final sql = src('supabase/migrations/0061_cargo_active.sql').toLowerCase();
      for (final bad in ['drop table', 'truncate', 'delete from', 'drop column']) {
        expect(sql.contains(bad), isFalse, reason: bad);
      }
      expect(sql, contains('add column if not exists is_paused boolean not null default false'));
      final run = src('supabase/tests/local/run_local.sh');
      expect(run, contains('0061_cargo_active.sql'));
      expect(run, contains('98_cargo_active.sql'));
    });
  });

  // Review of the load functions (24.10.2026): each fix stays in place.
  group('load functions review', () {
    test('form: no leaving while saving, lists refreshed, new load opens in front', () {
      final f = src('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f, contains('canPop: !_submitting'));
      expect(f, contains('container.invalidate(marketplaceProvider);'));
      expect(f, contains("context.go('/cargo/\$id');"));
      expect(f.contains("context.pushReplacement('/cargo/\$id')"), isFalse);
    });
    test('form: no past loading date; price and weight kept exactly', () {
      final f = src('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f, contains('firstDate: today,'));
      expect(f, contains('_priceCtrl.text = _plain(c.offeredPrice);'));
      expect(f, contains('_customTonsCtrl.text = _plain(t);'));
    });
    test('detail: delete / accept refresh lists even if the page was left', () {
      final d = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
      expect('ProviderScope.containerOf(context, listen: false)'.allMatches(d).length, greaterThanOrEqualTo(3));
      expect(d, contains('container.invalidate(myCargoProvider); // "Yüklərim": no longer Active'));
      expect(d, contains('// Was unhandled: a failed withdraw now says so.'));
    });
    test('favourites open in front; tile and search lists refresh', () {
      expect(src('lib/features/cargo/presentation/favorite_cargo_screen.dart'), contains("pushOnce('/load/\${list[i].id}')"));
      expect(src('lib/features/cargo/presentation/providers/category_providers.dart'), contains('  ref.watch(marketplaceProvider);'));
      expect(src('lib/features/cargo/presentation/providers/cargo_providers.dart'),
          contains('final filteredCargoProvider = FutureProvider.autoDispose.family'));
    });
  });
}

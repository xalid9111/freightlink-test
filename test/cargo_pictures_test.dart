// Load pictures + favourite loads (0058, owner 22.10.2026). Server rules:
// supabase/tests/local/95_cargo_pictures_favorites.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/cargo_pictures.dart';
import 'package:freightlink/models/cargo_model.dart';

CargoModel load({String? image}) => CargoModel(
      id: 'x',
      ownerId: 'o',
      pickupCountry: 'Azerbaijan',
      pickupCity: 'Baku',
      destinationCountry: 'Georgia',
      destinationCity: 'Tbilisi',
      weightKg: 1000,
      pickupDate: DateTime(2026, 10, 22),
      offeredPrice: 100,
      imageUrl: image,
    );

void main() {
  group('picture templates', () {
    test('QRUPAJ first, then the 7 load types; a typed type has none', () {
      expect(cargoPictureCategory(truckType: 'tent', groupage: true), 'groupage');
      expect(cargoPictureCategory(truckType: ' Ref '), 'ref');
      expect(cargoPictureCategory(truckType: 'tanker'), 'tanker');
      expect(cargoPictureCategory(truckType: 'Lowboy'), isNull);
      expect(cargoPictureCategory(), isNull);
      expect(kMaxCargoTemplates, 10);
    });

    test('uploads go to my own folder; admin templates to templates/<type>', () {
      expect(cargoPhotoPath(userId: 'u1', ext: 'JPEG', stamp: 5), 'u1/5.jpg');
      expect(cargoPhotoPath(userId: 'u1', ext: 'png', templateCategory: 'ref', stamp: 5), 'templates/ref/5.png');
    });

    test('only my own photo is ever deleted from storage, never a template', () {
      const base = 'https://p.supabase.co/storage/v1/object/public/cargo-photos';
      expect(isOwnCargoPhoto('$base/u1/5.jpg', 'u1'), isTrue);
      expect(isOwnCargoPhoto('$base/templates/ref/5.jpg', 'u1'), isFalse);
      expect(isOwnCargoPhoto('$base/u2/5.jpg', 'u1'), isFalse);
    });
  });

  group('load model', () {
    test('a picture is not required and is left out until 0058 is run', () {
      expect(load().toInsertJson()['image_url'], isNull);
      expect(load(image: 'https://x/a.jpg').toInsertJson()['image_url'], 'https://x/a.jpg');
      expect(load(image: 'https://x/a.jpg').toInsertJson(withImage: false).containsKey('image_url'), isFalse);
      final back = CargoModel.fromJson({
        'id': 'x', 'owner_id': 'o', 'pickup_country': 'A', 'pickup_city': 'a', 'destination_country': 'B',
        'destination_city': 'b', 'weight_kg': 1, 'pickup_date': '2026-10-22', 'offered_price': 1,
      });
      expect(back.imageUrl, isNull);
    });
  });

  group('wiring', () {
    String src(String p) => File(p).readAsStringSync();

    test('load form: picture card, kept on edit, uploads cleaned up without reading ref in dispose', () {
      final f = src('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.contains('CargoPictureField('), isTrue);
      // Up to 6 pictures since 0060: the list is kept on edit, the first is image_url.
      expect(f.contains('_images = c.pictures;'), isTrue);
      expect(f.contains('imageUrl: _images.isEmpty ? null : _images.first,'), isTrue);
      expect(f.contains('imageUrls: _images,'), isTrue);
      final dispose = f.substring(f.indexOf('void dispose()'), f.indexOf('super.dispose();'));
      expect(dispose.contains('ref.'), isFalse);
    });

    test('phone Loads page: heart + profile circles; computer: heart next to the bell', () {
      expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart').contains('HeaderCircles(strings: strings)'), isTrue);
      final desk = src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart');
      expect(desk.contains("key: const ValueKey('desk-favorites')"), isTrue);
      final c = src('lib/features/cargo/presentation/widgets/cargo_picture.dart');
      expect(c.contains("context.pushOnce('/cargo/favorites')"), isTrue);
      expect(c.contains("context.go('/profile')"), isTrue);
      expect(src('lib/core/router/app_router.dart').contains("path: '/cargo/favorites'"), isTrue);
    });

    test('admin: "Yük şəkilləri" section; detail page heart + admin remove', () {
      final shell = src('lib/features/admin/presentation/admin_shell.dart');
      expect(shell.contains("AdminSection('cargo_pictures', 'Yük şəkilləri'"), isTrue);
      expect(shell.contains('return const AdminCargoPicturesPage();'), isTrue);
      final d = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
      expect(d.contains('CargoFavoriteHeart(cargoId: cargoId'), isTrue);
      expect(d.contains('user?.role == AppConstants.roleAdmin'), isTrue);
    });

    test('0058 is safe: no drop table, truncate or bulk delete', () {
      final sql = File('supabase/migrations/0058_cargo_pictures_favorites.sql').readAsStringSync().toLowerCase();
      expect(sql.contains('drop table'), isFalse);
      expect(sql.contains('truncate'), isFalse);
      expect(RegExp(r'delete from cargo_image_templates where id = p_id').hasMatch(sql), isTrue);
      expect(RegExp(r'delete\s+from\s+(public\.)?cargo\b').hasMatch(sql), isFalse);
      for (final fn in ['admin_add_cargo_image_template', 'admin_delete_cargo_image_template',
                        'admin_reorder_cargo_image_templates', 'admin_clear_cargo_image']) {
        final body = sql.substring(sql.indexOf('function public.$fn('));
        expect(body.substring(0, body.indexOf(r'end $$')).contains('_require_admin()'), isTrue, reason: fn);
      }
    });
  });
}

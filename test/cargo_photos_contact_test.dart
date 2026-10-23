// Up to 6 load pictures, an optional contact number, one-tap contact and
// the new load page (owner, 23.10.2026, migration 0060). Server rules:
// supabase/tests/local/97_cargo_photos_contact.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/utils/phone_utils.dart';
import 'package:freightlink/features/cargo/data/cargo_media_repository.dart';
import 'package:freightlink/features/cargo/data/cargo_repository_impl.dart';
import 'package:freightlink/models/cargo_model.dart';

CargoModel load({String? image, List<String> images = const []}) => CargoModel(
      id: 'x',
      ownerId: 'o',
      pickupCountry: 'Azerbaijan',
      pickupCity: 'Baku',
      destinationCountry: 'Georgia',
      destinationCity: 'Tbilisi',
      weightKg: 1000,
      pickupDate: DateTime(2026, 10, 24),
      offeredPrice: 100,
      imageUrl: image,
      imageUrls: images,
    );

void main() {
  group('phone numbers', () {
    test('international format is kept; spaces, dashes and 00 are fine', () {
      expect(normalizePhone('+994 50-123 45 67'), '+994501234567');
      expect(normalizePhone('00994 50 123 45 67'), '+994501234567');
      expect(normalizePhone('(+90) 532 123 45 67'), '+905321234567');
    });

    test('no country code, too short, empty → not international', () {
      expect(normalizePhone('050 123 45 67'), isNull);
      expect(normalizePhone('+12'), isNull);
      expect(normalizePhone(''), isNull);
      expect(normalizePhone(null), isNull);
      expect(normalizePhone('+0501234567'), isNull);
    });

    test('WhatsApp digits only for a full international number', () {
      expect(whatsappDigits('+994 50 123 45 67'), '994501234567');
      expect(whatsappDigits('050 123 45 67'), isNull);
    });

    test("the load's own number first, else the registered one, else none", () {
      expect(cargoContactNumber(contactPhone: '+994551112233', registeredPhone: '+994501234567'), '+994551112233');
      expect(cargoContactNumber(contactPhone: '  ', registeredPhone: '+994501234567'), '+994501234567');
      expect(cargoContactNumber(contactPhone: null, registeredPhone: ''), isNull);
    });
  });

  group('pictures: image_url and image_urls stay in step', () {
    test('an old one-picture load shows that picture as its gallery', () {
      expect(load(image: 'https://a/1.jpg').pictures, ['https://a/1.jpg']);
      expect(load().pictures, isEmpty);
    });

    test('several pictures: the first is image_url, all go to image_urls', () {
      final j = load(images: ['https://a/1.jpg', 'https://a/2.jpg']).toInsertJson();
      expect(j['image_url'], 'https://a/1.jpg');
      expect(j['image_urls'], ['https://a/1.jpg', 'https://a/2.jpg']);
    });

    test('an old picture kept on edit is sent as the list too', () {
      final j = load(image: 'https://a/old.jpg').toInsertJson();
      expect(j['image_url'], 'https://a/old.jpg');
      expect(j['image_urls'], ['https://a/old.jpg']);
    });

    test('until 0060 is run: only the main picture; until 0058: none', () {
      final j = load(images: ['https://a/1.jpg', 'https://a/2.jpg']).toInsertJson(withImages: false);
      expect((j['image_url'], j.containsKey('image_urls')), ('https://a/1.jpg', false));
      final k = load(images: ['https://a/1.jpg']).toInsertJson(withImage: false);
      expect(k.containsKey('image_url') || k.containsKey('image_urls'), isFalse);
    });

    test('reading: the list from the server, empty when missing', () {
      final c = CargoModel.fromJson({
        'id': 'x', 'owner_id': 'o', 'pickup_country': 'A', 'pickup_city': 'a', 'destination_country': 'B',
        'destination_city': 'b', 'weight_kg': 1, 'pickup_date': '2026-10-22', 'offered_price': 1,
        'image_url': 'https://a/1.jpg', 'image_urls': ['https://a/1.jpg', 'https://a/2.jpg'],
      });
      expect(c.pictures.length, 2);
      expect(CargoModel.maxPictures, 6);
    });

    test('"image_urls missing" is told apart from "image_url missing"', () {
      const urls = "Could not find the 'image_urls' column of 'cargo' in the schema cache";
      const url = "Could not find the 'image_url' column of 'cargo' in the schema cache";
      expect(isMissingImagesColumn('PGRST204', urls), isTrue);
      expect(isMissingImageColumn('PGRST204', urls), isFalse);
      expect(isMissingImageColumn('PGRST204', url), isTrue);
      expect(isMissingImagesColumn('PGRST204', url), isFalse);
    });

    test('upload check: 5 MB, JPG / PNG / WEBP', () {
      expect(CargoMediaRepository.checkUpload(1000, 'jpg'), isNull);
      expect(CargoMediaRepository.checkUpload(1000, 'WEBP'), isNull);
      expect(CargoMediaRepository.checkUpload(6 * 1024 * 1024, 'png'), 'cargo_pics_too_big');
      expect(CargoMediaRepository.checkUpload(1000, 'gif'), 'cargo_pics_bad_type');
    });
  });

  group('wiring', () {
    String src(String p) => File(p).readAsStringSync();

    test('form: up to 6 pictures and an optional, checked contact number', () {
      final f = src('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.contains("key: const ValueKey('cargo-alt-phone')"), isTrue);
      expect(f.contains('normalizePhone(v) != null'), isTrue);
      expect(f.contains('await _media.setContactPhone(id, alt);'), isTrue);
      final field = src('lib/features/cargo/presentation/widgets/cargo_picture_field.dart');
      expect(field.contains('static const _max = CargoModel.maxPictures;'), isTrue);
      expect(field.contains('CargoMediaRepository.checkUpload(bytes.length, ext)'), isTrue);
    });

    test('load page: gallery + full screen, own number first, "Əlaqə saxla", no number handled', () {
      final d = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
      for (final k in ['detail-gallery', 'detail-gallery-full', 'detail-contact', 'detail-no-phone', 'detail-load', 'detail-notes']) {
        expect(d.contains("ValueKey('$k')"), isTrue, reason: k);
      }
      expect(d.contains("cargoContactNumber(contactPhone: contact['contact_phone'], registeredPhone: contact['phone'])"), isTrue);
      expect(d.contains('if (c.maxWidth < 900)'), isTrue); // phone vs computer
      expect(src('lib/repositories/credits_repository.dart').contains("'contact_phone': row?['contact_phone']"), isTrue);
    });

    test('0060 is safe: nothing dropped or deleted, contact numbers not in public.cargo', () {
      final sql = src('supabase/migrations/0060_cargo_photos_contact.sql').toLowerCase();
      expect(sql.contains('drop table'), isFalse);
      expect(sql.contains('truncate'), isFalse);
      expect(RegExp(r'delete\s+from').hasMatch(sql), isFalse);
      expect(sql.contains('alter table public.cargo add column if not exists contact'), isFalse);
      expect(sql.contains('revoke execute on function public.get_cargo_contact(uuid) from public, anon;'), isTrue);
    });
  });
}

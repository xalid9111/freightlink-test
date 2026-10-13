// Service ad: why "my own picture" was not accepted (no more silent
// "could not be uploaded") and the admin "Servis şablonları" order logic.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/admin/presentation/admin_ad_templates.dart';
import 'package:freightlink/features/ads/presentation/ad_error_keys.dart';
import 'package:freightlink/models/ad_models.dart';

AdTemplate _t(String id, int sort, {String audience = 'cargo'}) => AdTemplate(
      id: id,
      name: id,
      imageUrl: 'https://x/$id.png',
      fields: const [],
      colors: const [],
      layout: 'standard_v2',
      audience: audience,
      isActive: true,
      sort: sort,
    );

void main() {
  group('ownImageErrorKey', () {
    test('admin switched ordering off → says so', () {
      expect(ownImageErrorKey('PostgrestException(message: ordering_disabled, code: 42501, details: null, hint: null)'),
          'adv_err_ordering_disabled');
    });
    test('blocked account', () {
      expect(ownImageErrorKey('PostgrestException(message: account_blocked, code: 42501)'), 'adv_err_account_blocked');
    });
    test('20 own pictures already', () {
      expect(ownImageErrorKey('PostgrestException(message: too_many_backgrounds, code: 54000)'), 'adv_own_image_too_many');
    });
    test('bad picture / too big / wrong type', () {
      expect(ownImageErrorKey('PostgrestException(message: invalid_image, code: 22023)'), 'adv_own_image_invalid');
      expect(ownImageErrorKey('StorageException(message: Payload too large, statusCode: 413, error: Payload too large)'),
          'adv_own_image_invalid');
      expect(ownImageErrorKey('StorageException(message: mime type image/heic is not supported, statusCode: 415)'),
          'adv_own_image_invalid');
    });
    test('anything else → general text', () {
      expect(ownImageErrorKey('StorageException(message: new row violates row-level security policy, statusCode: 403)'),
          'adv_own_image_failed');
      expect(ownImageErrorKey('TimeoutException after 0:00:20.000000: Future not completed'), 'adv_own_image_failed');
    });
  });

  group('adErrorCode (shown in brackets)', () {
    test('server function missing → PGRST202 (migration not run)', () {
      expect(
          adErrorCode('PostgrestException(message: Could not find the function public.create_own_ad_background(p_image_url) '
              'in the schema cache, code: PGRST202, details: Searched for the function, hint: null)'),
          'PGRST202');
    });
    test('server word', () {
      expect(adErrorCode('PostgrestException(message: ordering_disabled, code: 42501)'), 'ordering_disabled');
    });
    test('Postgres code without a word', () {
      expect(adErrorCode('PostgrestException(message: permission denied, code: 42501)'), '42501');
    });
    test('storage status', () {
      expect(adErrorCode('StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)'),
          'storage_403');
    });
    test('timeout / network / unknown', () {
      expect(adErrorCode('TimeoutException after 0:02:00.000000: Future not completed'), 'timeout');
      expect(adErrorCode('ClientException: Failed to fetch'), 'network');
      expect(adErrorCode('Something odd'), '');
    });
  });

  group('swapTemplates (admin template order)', () {
    final all = [_t('a', 1), _t('s1', 2, audience: 'service'), _t('b', 3), _t('s2', 4, audience: 'all')];
    test('swaps only the two, nothing lost or repeated', () {
      final out = swapTemplates(all, 's1', 's2');
      expect(out.map((t) => t.id), ['a', 's2', 'b', 's1']);
      expect(out.toSet().length, all.length);
    });
    test('neighbours in the full list = same as moving one place', () {
      expect(swapTemplates(all, 'a', 's1').map((t) => t.id), ['s1', 'a', 'b', 's2']);
    });
    test('unknown id → unchanged', () {
      expect(swapTemplates(all, 'a', 'zz').map((t) => t.id), ['a', 's1', 'b', 's2']);
    });
  });
}

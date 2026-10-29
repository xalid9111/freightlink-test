// Animated GIF as the profile picture and the cover (owner, 29.10.2026).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/utils/gif.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('a GIF is known by its first bytes, not by its name', () {
    expect(isGifBytes(Uint8List.fromList(ascii.encode('GIF89a......'))), isTrue);
    expect(isGifBytes(Uint8List.fromList(ascii.encode('GIF87a......'))), isTrue);
    expect(isGifBytes(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), isFalse, reason: 'PNG');
    expect(isGifBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])), isFalse, reason: 'JPEG');
    expect(isGifBytes(Uint8List.fromList(ascii.encode('GIF'))), isFalse, reason: 'too short');
    expect(kGifMaxBytes, 5 * 1024 * 1024, reason: 'the profile-media bucket limit (0031)');
  });

  test('wired: the avatar and the cover go up as GIF, other pictures as before', () {
    final prof = src('lib/features/auth/presentation/profile_screen.dart');
    expect(prof, contains("contentType: gif ? 'image/gif' : file.mimeType"));
    expect(prof, contains("strings.t('profile_gif_too_big')"));
    expect(prof, contains('maxWidth: 512,'), reason: 'photos are still made small');
    final pub = src('lib/features/ads/presentation/public_profile_screen.dart');
    expect(pub, contains("uploadCover(picked, contentType: 'image/gif')"), reason: 'no crop for a GIF');
    expect(pub, contains('CoverCropScreen(bytes: picked'), reason: 'photos are still cropped');
    expect(src('supabase/migrations/0031_profile_catalog_message_delete.sql'), contains("'image/gif'"),
        reason: 'the cover bucket accepts GIF — no new SQL');
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      expect((jsonDecode(src('assets/i18n/$lang.json')) as Map)['profile_gif_too_big'], isNotNull, reason: lang);
    }
  });
}

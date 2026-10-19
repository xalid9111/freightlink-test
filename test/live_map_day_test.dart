import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map_day_geo.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map_night_geo.dart';

/// Width / height from a JPEG's SOF header.
(int, int) _jpegSize(Uint8List b) {
  var i = 2;
  while (i < b.length) {
    final marker = b[i + 1];
    final len = (b[i + 2] << 8) | b[i + 3];
    if (marker >= 0xC0 && marker <= 0xC2) return ((b[i + 7] << 8) | b[i + 8], (b[i + 5] << 8) | b[i + 6]);
    i += 2 + len;
  }
  return (0, 0);
}

void main() {
  test('night shows the owner\'s night clouds map (19.10.2026), day the colourful country map', () {
    // New file name, so a phone never shows an old cached picture with the new hubs.
    expect(liveMapImage(day: false), 'assets/images/world_map_night_v2.jpg');
    expect(liveMapImage(day: true), 'assets/images/world_map_day.jpg');
  });

  test('day picture (owner design): every hub and city light is placed on it, light for iPhone', () {
    // No extra cloud pictures: the owner's picture already fades to white.
    expect(File('assets/images/clouds_day_top.jpg').existsSync(), isFalse);
    final day = File('assets/images/world_map_day.jpg').readAsBytesSync();
    expect(_jpegSize(day), (kDayImgW.toInt(), kDayImgH.toInt()));
    expect(day.length, lessThan(300 * 1024));
    // Same hubs as the night map (same order), all on the picture.
    final night = File('lib/features/cargo/presentation/widgets/live_map.dart').readAsStringSync();
    final hubBlock = night.substring(night.indexOf('const List<Offset> _hubs = ['), night.indexOf('];', night.indexOf('const List<Offset> _hubs = [')));
    expect(kDayHubs.length, RegExp(r'Offset\(').allMatches(hubBlock).length);
    for (final p in [...kDayHubs, ...kDaySparks]) {
      expect(p.dx >= 0 && p.dx <= kDayImgW && p.dy >= 0 && p.dy <= kDayImgH, isTrue, reason: '$p');
    }
    expect(File('scripts/make_day_map.py').existsSync(), isTrue);
  });

  test('day cloud scene: clouds above / below the map, light, never at night', () {
    for (final f in ['world_map_day_top.jpg', 'world_map_day_bottom.jpg']) {
      final bytes = File('assets/images/$f').readAsBytesSync();
      expect(_jpegSize(bytes).$1, kDayImgW.toInt(), reason: '$f: same width as the map, so they join');
      expect(bytes.length, lessThan(40 * 1024), reason: f);
    }
    final home = File('lib/features/cargo/presentation/cargo_marketplace_screen.dart').readAsStringSync();
    expect(home.contains("final scene = day ? 'assets/images/world_map_day' : 'assets/images/world_map_night_v2';"), isTrue);
  });

  test('night cloud scene: every hub and city light on the picture, edges fade to the night page colour', () {
    final map = File('assets/images/world_map_night_v2.jpg').readAsBytesSync();
    expect(_jpegSize(map), (kNightImgW.toInt(), kNightImgH.toInt()));
    expect(map.length, lessThan(300 * 1024));
    expect(kNightHubs.length, liveMapSourceHubCount, reason: 'same hubs, same order');
    for (final p in [...kNightHubs, ...kNightSparks]) {
      expect(p.dx >= 0 && p.dx <= kNightImgW && p.dy >= 0 && p.dy <= kNightImgH, isTrue, reason: '$p');
    }
    for (final f in ['world_map_night_v2_top.jpg', 'world_map_night_v2_bottom.jpg']) {
      final bytes = File('assets/images/$f').readAsBytesSync();
      expect(_jpegSize(bytes).$1, kNightImgW.toInt(), reason: '$f: same width as the map, so they join');
      expect(bytes.length, lessThan(120 * 1024), reason: f);
    }
    final script = File('scripts/make_night_map.py').readAsStringSync();
    expect(script.contains('BG = np.array([2, 5, 12], float)'), isTrue, reason: 'fades to #02050C (AppColors night background)');
  });
}

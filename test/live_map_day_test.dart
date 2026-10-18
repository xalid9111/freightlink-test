import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map_day_geo.dart';

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
  test('night keeps the night-lights map, day shows the colourful country map', () {
    expect(liveMapImage(day: false), 'assets/images/world_map.jpg');
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
}

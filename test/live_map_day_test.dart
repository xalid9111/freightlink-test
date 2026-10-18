import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/widgets/live_map.dart';

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

  test('day map has the same layout as the night map (hubs, routes and trucks line up), light for iPhone', () {
    final night = File('assets/images/world_map.jpg').readAsBytesSync();
    final day = File('assets/images/world_map_day.jpg').readAsBytesSync();
    expect(_jpegSize(day), _jpegSize(night));
    expect(_jpegSize(day), (1220, 580));
    expect(day.length, lessThan(200 * 1024));
    expect(File('scripts/make_day_map.py').existsSync(), isTrue);
  });
}

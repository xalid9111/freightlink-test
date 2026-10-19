import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
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
  // Both modes: the owner's cloud pictures of 19.10.2026 (scripts/make_cloud_map.py).
  final modes = [
    (name: 'world_map_day_v3', w: kDayImgW, h: kDayImgH, hubs: kDayHubs, sparks: kDaySparks, page: const Color(0xFFFFFFFF)),
    (name: 'world_map_night_v4', w: kNightImgW, h: kNightImgH, hubs: kNightHubs, sparks: kNightSparks, page: const Color(0xFF02050C)),
  ];

  test('day and night show the owner\'s cloud maps (new file names: no old cached picture with new hubs)', () {
    expect(liveMapImage(day: true), 'assets/images/world_map_day_v3.jpg');
    expect(liveMapImage(day: false), 'assets/images/world_map_night_v4.jpg');
    for (final old in ['world_map_day.jpg', 'world_map_day_v2.jpg', 'world_map_night_v2.jpg', 'world_map_night_v3.jpg']) {
      expect(File('assets/images/$old').existsSync(), isFalse, reason: old);
    }
    final home = File('lib/features/cargo/presentation/cargo_marketplace_screen.dart').readAsStringSync();
    expect(home.contains("final scene = day ? 'assets/images/world_map_day_v3' : 'assets/images/world_map_night_v4';"), isTrue);
    expect(File('scripts/make_cloud_map.py').existsSync(), isTrue);
  });

  for (final m in modes) {
    test('${m.name}: every hub and city light on the picture, scene pictures join, light for phones', () {
      final map = File('assets/images/${m.name}.jpg').readAsBytesSync();
      expect(_jpegSize(map), (m.w.toInt(), m.h.toInt()));
      expect(map.length, lessThan(300 * 1024));
      expect(m.hubs.length, liveMapSourceHubCount, reason: 'same hubs, same order');
      for (final p in [...m.hubs, ...m.sparks]) {
        expect(p.dx >= 0 && p.dx <= m.w && p.dy >= 0 && p.dy <= m.h, isTrue, reason: '$p');
      }
      for (final f in ['${m.name}_top.jpg', '${m.name}_bottom.jpg']) {
        final bytes = File('assets/images/$f').readAsBytesSync();
        expect(_jpegSize(bytes).$1, m.w.toInt(), reason: '$f: same width as the map, so they join');
        expect(bytes.length, lessThan(120 * 1024), reason: f);
      }
    });
  }

  testWidgets('no line at the top or bottom — the outer rows are the page colour (day and night)', (tester) async {
    // Average colour of one row of a picture.
    Future<List<double>> row(String file, {required bool last}) => tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(File('assets/images/$file').readAsBytesSync());
          final img = (await codec.getNextFrame()).image;
          final px = (await img.toByteData())!;
          final y = last ? img.height - 1 : 0;
          final sum = [0.0, 0.0, 0.0];
          for (var x = 0; x < img.width; x++) {
            final o = (y * img.width + x) * 4;
            for (var c = 0; c < 3; c++) {
              sum[c] += px.getUint8(o + c);
            }
          }
          return [for (final v in sum) v / img.width];
        }).then((v) => v!);
    for (final m in modes) {
      final expected = [m.page.r * 255, m.page.g * 255, m.page.b * 255];
      for (final (file, last) in [('${m.name}_top.jpg', false), ('${m.name}_bottom.jpg', true)]) {
        final got = await row(file, last: last);
        for (var c = 0; c < 3; c++) {
          expect((got[c] - expected[c]).abs(), lessThan(3), reason: '$file edge must match the page colour, got $got');
        }
      }
    }
  });
}

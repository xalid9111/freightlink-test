// TIR Link logo and app icons (owner, 14.11.2026): the new logo replaces the
// old orange chart icon left of "TırLink" (never taller than its capital T),
// on the Home Screen / manifest icons (square, not transparent, new file
// names so no cache keeps the old one) and on the dark start-up screen.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/widgets/tirlink_wordmark.dart';

String src(String p) => File(p).readAsStringSync();

/// Width, height and PNG colour type (2 = RGB, 6 = RGBA) from the IHDR chunk.
(int, int, int) png(String p) {
  final b = ByteData.sublistView(File(p).readAsBytesSync());
  expect(b.getUint32(0), 0x89504E47, reason: '$p is a PNG');
  return (b.getUint32(16), b.getUint32(20), b.getUint8(25));
}

void main() {
  tearDown(() => AppColors.use(AppPalette.dark));

  testWidgets('home header: logo left of TırLink, from its top to the bottom of the site line', (t) async {
    AppColors.use(AppPalette.dark);
    await t
        .pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: TirLinkWordmark(size: 18, showLogo: true)))));
    final logo = t.getRect(find.byKey(const ValueKey('tirlink-logo')));
    final word = t.getRect(find.byKey(const ValueKey('tirlink-wordmark')));
    final site = t.getRect(find.byKey(const ValueKey('tirlink-site')));
    expect(logo.right, lessThanOrEqualTo(word.left), reason: 'logo on the left');
    // Owner, 15.11.2026: as tall as TırLink + www.tirlink.app together.
    expect(logo.top, closeTo(word.top, 0.5), reason: 'starts at the top of TırLink');
    expect(logo.bottom, closeTo(site.bottom, 0.5), reason: 'ends at the bottom of the site line');
    expect(site.top, greaterThanOrEqualTo(word.bottom - 0.5), reason: 'site right under the word');
    expect(site.left, closeTo(word.left, 0.5), reason: 'aligned with the word');
    final siteText = t.widget<Text>(find.byKey(const ValueKey('tirlink-site')));
    expect(siteText.style!.color, Colors.white);
  });

  test('the old orange chart icon is gone from the header and the sidebar', () {
    for (final p in [
      'lib/features/cargo/presentation/cargo_marketplace_screen.dart',
      'lib/core/router/main_shell.dart'
    ]) {
      expect(src(p), isNot(contains('Icons.show_chart')), reason: p);
      expect(src(p), contains('showLogo: true'), reason: p);
    }
    // The phone's compact header (owner's design, 17.11.2026): logo +
    // TırLink + www.tirlink.app, no slogan line.
    final home = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(home, contains("ValueKey('home-compact-header')"));
    expect(home, contains('TirLinkWordmark(size: 22, showLogo: true)'));
    expect(File(TirLinkWordmark.logoAsset).existsSync(), isTrue);
    expect(src('pubspec.yaml'), contains('- assets/images/brand/'));
  });

  test('Home Screen / manifest icons: square, not transparent, versioned names', () {
    final manifest = jsonDecode(src('web/manifest.json')) as Map<String, dynamic>;
    final icons = [for (final i in manifest['icons'] as List) i as Map<String, dynamic>];
    expect(icons.map((i) => i['src']), [
      'icons/tirlink-icon-v3-192.png',
      'icons/tirlink-icon-v3-512.png',
      'icons/tirlink-icon-v3-maskable-192.png',
      'icons/tirlink-icon-v3-maskable-512.png',
    ]);
    for (final i in icons) {
      final (w, h, type) = png('web/${i['src']}');
      expect('${w}x$h', i['sizes'], reason: '${i['src']}');
      expect(type, 2, reason: '${i['src']} has no transparency');
    }
    final html = src('web/index.html');
    expect(html, contains('<link rel="apple-touch-icon" sizes="180x180" href="icons/tirlink-apple-touch-v3.png">'));
    expect(png('web/icons/tirlink-apple-touch-v3.png'), (180, 180, 2));
    expect(html, contains('href="favicon-v3.png"'));
    expect(png('web/favicon-v3.png'), (32, 32, 2));
    expect(html, isNot(contains('href="icons/apple-touch-icon.png"')));
    expect(html, isNot(contains('href="favicon.png"')));
  });

  test('start-up screen: the new logo (small WebP + PNG), dark ground and spinner unchanged', () {
    final html = src('web/index.html');
    expect(html, contains('<source srcset="icons/tirlink-logo-v2-144.webp" type="image/webp">'));
    expect(html, contains('<img src="icons/tirlink-logo-v2-144.png" alt="TırLink" width="72" height="72">'));
    expect(html, isNot(contains('<img src="icons/Icon-192.png"')));
    expect(html, contains('<div class="spinner"></div>'));
    expect(File('web/icons/tirlink-logo-v2-144.webp').lengthSync(), lessThan(20 * 1024),
        reason: 'light, no slower start');
    // No service worker is turned back on.
    expect(html, isNot(contains('serviceWorker.register(')));
  });

  // Owner, 15.11.2026: "kənarlarında qara xətt olmasın" — the icon fills the
  // square edge to edge; no dark ground on its sides or in the corners that
  // iPhone / Android keep after their own rounding.
  testWidgets('icons have no dark rim', (t) async {
    await t.runAsync(() async {
      for (final p in [
        'web/icons/tirlink-apple-touch-v3.png',
        'web/icons/tirlink-icon-v3-512.png',
        'web/icons/tirlink-icon-v3-maskable-512.png'
      ]) {
        final codec = await ui.instantiateImageCodec(File(p).readAsBytesSync());
        final img = (await codec.getNextFrame()).image;
        final px = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final n = img.width;
        int light(double fx, double fy) {
          final i = ((fy * (n - 1)).round() * n + (fx * (n - 1)).round()) * 4;
          return px.getUint8(i) + px.getUint8(i + 1) + px.getUint8(i + 2);
        }

        // Edge midpoints and points just inside the iOS corner curve.
        for (final (x, y) in [
          (0.0, 0.5),
          (1.0, 0.5),
          (0.5, 0.0),
          (0.5, 1.0),
          (0.08, 0.08),
          (0.92, 0.08),
          (0.08, 0.92),
          (0.92, 0.92)
        ]) {
          expect(light(x, y), greaterThan(60), reason: '$p at ($x, $y) is not the dark ground');
        }
      }
    });
  });
}

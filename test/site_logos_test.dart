// Admin → Loqolar (owner, 15.11.2026, SQL 0124): the Baş admin uploads and
// frames a logo for three places — the phone icon, the logo left of
// "TırLink" (Yüklər, sidebar, login) and the start-up screen — and the site
// follows: the header at once, the icon links at once, the start-up logo
// from the next start (the device's last copy, read before the app loads).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/brand/site_logos.dart';
import 'package:freightlink/core/widgets/framed_image.dart';
import 'package:freightlink/core/widgets/tirlink_wordmark.dart';
import 'package:freightlink/features/admin/data/rpc_migrations.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  tearDown(() => SiteLogos.homeLogo.value = null);

  test('the editor\'s framing lands in the square the same way (cover, zoom, place)', () {
    const img = Size(200, 100);
    expect(framedRect(img, 100, ImageFraming.centre), const Rect.fromLTWH(-50, 0, 200, 100));
    expect(framedRect(img, 100, const ImageFraming(ax: -1)), const Rect.fromLTWH(0, 0, 200, 100), reason: 'left edge');
    expect(framedRect(img, 100, const ImageFraming(ax: 1)), const Rect.fromLTWH(-100, 0, 200, 100),
        reason: 'right edge');
    final z = framedRect(img, 100, const ImageFraming(z: 2));
    expect(z.size, const Size(400, 200));
    expect(z.center, const Offset(50, 50), reason: 'zoom keeps the centre');
  });

  testWidgets('the phone icon is a square PNG without transparency', (t) async {
    await t.runAsync(() async {
      // A 4×2 transparent picture: the icon must still be filled.
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(1, 0, 2, 2), Paint()..color = const Color(0xFFFF6600));
      final srcImg = await rec.endRecording().toImage(4, 2);
      final srcPng = (await srcImg.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final png = await renderFramedSquare(srcPng, ImageFraming.centre, 64, background: kAppIconGround);
      final b = ByteData.sublistView(png);
      expect(b.getUint32(0), 0x89504E47, reason: 'PNG');
      expect((b.getUint32(16), b.getUint32(20)), (64, 64));
      final out = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
      final px = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(px.getUint8(3), 255, reason: 'corner not transparent');
    });
  });

  testWidgets('the header follows the Baş admin\'s logo, else the built-in one', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: TirLinkWordmark(size: 18, showLogo: true))));
    DecorationImage img() =>
        ((t.widget<DecoratedBox>(find.byKey(const ValueKey('tirlink-logo'))).decoration as BoxDecoration).image)!;
    expect(img().image, isA<AssetImage>());
    SiteLogos.homeLogo.value = 'https://x.supabase.co/storage/v1/object/public/market-photos/a/logo.png';
    await t.pump();
    expect(img().image, isA<NetworkImage>());
  });

  test('wired everywhere: start-up page, icon links, app start, admin, login', () {
    final html = src('web/index.html');
    final script = html.indexOf('<script id="site-logos">');
    expect(script, greaterThan(html.indexOf('<div id="app-loading">')), reason: 'after the start-up logo');
    expect(script, lessThan(html.indexOf('flutter_bootstrap.js')), reason: 'before the app');
    expect(html, contains("var KEY = 'fl_site_logos';"));
    expect(html, contains('window.flLogos = {'));
    expect(html, contains('link[rel="apple-touch-icon"], link[rel="icon"]'));
    expect(src('lib/main.dart'), contains('unawaited(SiteLogos.load());'));
    expect(src('lib/features/admin/presentation/admin_shell.dart'), contains("AdminSection('logos', 'Loqolar'"));
    expect(src('lib/features/auth/presentation/login_screen.dart'), contains('showLogo: true'));
    expect(kRpcMigration['admin_site_logo_set'], '0124_site_logos.sql');
    final sql = src('supabase/migrations/0124_site_logos.sql');
    expect(sql, contains('if not public.is_chief_admin()'));
    expect(sql, contains("_admin_log('site_logo.set'"));
  });
}

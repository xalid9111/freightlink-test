// Faster site, stage 1 (owner, 16.11.2026): the admins' heavy PNGs (load
// templates 2.5 MB, page banners 2.7 MB) are asked for light (WebP at the
// shown size) through Supabase's image service; the original is the fallback.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/utils/light_image.dart';

String src(String p) => File(p).readAsStringSync();

const host = 'https://jqdqtfmxnqezlsetelpi.supabase.co';

void main() {
  test('templates and banners get the light address', () {
    expect(lightImageUrl('$host/storage/v1/object/public/cargo-photos/templates/container/1.png', 507),
        '$host/storage/v1/render/image/public/cargo-photos/templates/container/1.png?width=640&resize=contain&quality=80');
    // A banner saved with a doubled "/" still gives one clean address.
    expect(lightImageUrl('$host//storage/v1/object/public/market-photos/u1/hero_17.png', 1170),
        '$host/storage/v1/render/image/public/market-photos/u1/hero_17.png?width=1280&resize=contain&quality=80');
  });

  test('the whole picture, never a cut strip (owner, 16.11.2026)', () {
    // Supabase keeps the original height when only a width is given and cuts
    // a narrow strip out of the picture; "contain" keeps the whole picture.
    expect(lightImageUrl('$host/storage/v1/object/public/cargo-photos/templates/ref/1.png', 300), contains('&resize=contain'));
  });

  test('everything else stays exactly as it was', () {
    for (final u in [
      '$host/storage/v1/object/public/cargo-photos/u1/17.jpg', // a user's own load photo
      '$host/storage/v1/object/public/market-photos/u1/17.jpg', // a TIR Bazarı ad photo
      '$host/storage/v1/object/public/market-photos/u1/hero_17.gif', // a moving banner
      '$host/storage/v1/object/public/cargo-photos/templates/ref/1.png?x=1',
      'https://example.com/hero_1.png',
      'assets/images/cargo/type_ref_night.png',
    ]) {
      expect(lightImageUrl(u, 600), u, reason: u);
      expect(isLightImage(u), isFalse, reason: u);
    }
  });

  test('TIR Bazarı list cards: the ad photo comes light too (owner, 16.11.2026)', () {
    const photo = '$host//storage/v1/object/public/market-photos/5d67/1792567636370000.jpg';
    expect(lightImageUrl(photo, 338, photo: true),
        '$host/storage/v1/render/image/public/market-photos/5d67/1792567636370000.jpg?width=480&resize=contain&quality=80');
    expect(lightImageUrl(photo, 338), photo, reason: 'the ad page and full screen keep the original');
    for (final u in [
      '$host/storage/v1/object/public/market-photos/u1/17.gif',
      '$host/storage/v1/object/public/cargo-photos/u1/17.jpg',
      '$host/storage/v1/object/public/chat-files/u1/17.jpg',
    ]) {
      expect(lightImageUrl(u, 338, photo: true), u, reason: u);
    }
  });

  test('a light picture is never shrunk again on the phone (Safari stops the scroll)', () {
    for (final f in [
      'lib/features/cargo/presentation/widgets/cargo_picture.dart',
      'lib/features/market/presentation/market_card.dart',
      'lib/core/widgets/page_hero.dart',
    ]) {
      expect(src(f), contains('cacheWidth: headers == null ? w : null'), reason: f);
    }
    final card = src('lib/features/market/presentation/market_card.dart');
    expect('MarketPhoto(url: l.cover, light: true)'.allMatches(card).length, 2);
    expect(src('lib/features/market/presentation/market_lists_screens.dart'), contains('MarketPhoto(url: l.cover, light: true)'));
    expect(src('lib/features/market/presentation/market_home_desktop.dart'), contains('MarketPhoto(url: l.cover, light: true)'));
    expect(src('lib/features/market/presentation/market_detail_screen.dart'), isNot(contains('light: true')),
        reason: 'the ad page keeps the original quality');
  });

  test('widths come in shared steps', () {
    expect(lightWidthStep(100), 480);
    expect(lightWidthStep(480), 480);
    expect(lightWidthStep(481), 640);
    expect(lightWidthStep(1200), 1280);
    expect(lightWidthStep(2148), 2400, reason: 'a banner on a 3× phone, as sharp as before');
    expect(lightWidthStep(5000), 2400);
  });

  testWidgets('the light picture first, the original when it fails', (t) async {
    final asked = <(String, Map<String, String>?)>[];
    const url = '$host/storage/v1/object/public/cargo-photos/templates/ref/1.png';
    var failLight = true;
    await t.pumpWidget(MaterialApp(
      home: LightImage(
        url: url,
        px: 500,
        onError: (_, __, ___) => const Text('fallback'),
        builder: (c, s, headers, onError) {
          asked.add((s, headers));
          if (s != url && failLight) return onError(c, Exception('x'), null);
          return Text('shown $s');
        },
      ),
    ));
    expect(asked.first.$1, contains('/render/image/public/'));
    expect(asked.first.$2, kLightImageHeaders);
    await t.pump();
    expect(asked.last.$1, url, reason: 'tried again with the original');
    expect(asked.last.$2, isNull);
    expect(find.text('shown $url'), findsOneWidget);
    failLight = false;
  });

  test('used for load pictures and page banners', () {
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture.dart'), contains('return LightImage('));
    expect(src('lib/features/cargo/presentation/cargo_detail_screen.dart'), contains('LightImage('));
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture_field.dart'), contains('LightImage('));
    final hero = src('lib/core/widgets/page_hero.dart');
    expect('return LightImage('.allMatches(hero).length, 2, reason: 'cover and whole banners');
    expect(hero, contains('headers: headers,'));
  });
}

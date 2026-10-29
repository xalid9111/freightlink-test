// "Yerini düzəlt" for the profile picture and the cover (owner, 29.10.2026):
// a fixed frame, drag / zoom, save; the place travels in the link.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/widgets/framed_image.dart';
import 'package:freightlink/core/widgets/image_frame_editor.dart';
import 'package:freightlink/core/widgets/user_avatar.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

// 1×1 transparent PNG.
final _png = Uint8List.fromList(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));

void main() {
  const base = 'https://x.supabase.co/storage/v1/object/public/avatars/u1/avatar?v=123';

  test('the place and zoom are kept in the link; old links mean centre, 1×', () {
    expect(ImageFraming.of(base).isDefault, isTrue);
    expect(ImageFraming.of(null).isDefault, isTrue);
    const f = ImageFraming(ax: -0.5, ay: 0.25, z: 2);
    final url = f.applyTo(base);
    expect(url, contains('v=123'), reason: 'the cache-buster stays');
    final back = ImageFraming.of(url);
    expect([back.ax, back.ay, back.z], [-0.5, 0.25, 2]);
    expect(ImageFraming.baseOf(url), base);
    expect(ImageFraming.centre.applyTo(url), base, reason: 'reset removes the parameters');
    // Nonsense in the link is clamped, never breaks the picture.
    final odd = ImageFraming.of('$base&ax=9&ay=abc&z=99');
    expect([odd.ax, odd.ay, odd.z], [1, 0, kFrameMaxZoom]);
    expect(f.copyWith(z: 0.2).z, 1);
    // The cover check of 0031 (profile-media prefix, ≤ 1000) still holds.
    final cover = f.applyTo('https://x.supabase.co/storage/v1/object/public/profile-media/u1/cover?v=1');
    expect(cover, startsWith('https://x.supabase.co/storage/v1/object/public/profile-media/'));
    expect(cover.length, lessThan(1000));
  });

  test('dragging moves the picture by the part that is outside the frame', () {
    expect(frameShift(50, 100), -1);
    expect(frameShift(50, 0), 0, reason: 'nothing to move');
    final big = coverSize(const Size(200, 100), const Size(100, 100), 2);
    expect(big, const Size(400, 200));
  });

  testWidgets('the editor: a fixed frame, drag and zoom, Sıfırla, save returns the place', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ImageFraming? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context).push<ImageFraming>(MaterialPageRoute(
              builder: (_) => ImageFrameEditorScreen(image: MemoryImage(_png), aspect: 1, circle: true, title: 'Şəkil', s: _az),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('frame-box')), findsOneWidget);
    expect(find.text('Sıfırla'), findsOneWidget);
    final box = tester.getSize(find.byKey(const ValueKey('frame-box')));
    expect(box.width, box.height, reason: 'a round frame for the profile picture');
    // Zoom with the slider, then drag: the place changes.
    await tester.drag(find.byKey(const ValueKey('frame-zoom')), const Offset(150, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('frame-area')), const Offset(60, 40));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('frame-save')));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.z, greaterThan(1));
    expect(result!.ax, lessThan(0), reason: 'dragged right → the left part shows');
    expect(result!.ay, lessThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a framed avatar shows through FramedImage, a plain one as before', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Column(children: [
        UserAvatar(imageUrl: const ImageFraming(ax: 0.3, z: 2).applyTo(base), initials: 'AB'),
        const UserAvatar(imageUrl: base, initials: 'CD'),
      ]),
    ));
    expect(find.byType(FramedImage), findsOneWidget);
    expect(find.text('AB'), findsOneWidget, reason: 'initials stay under it while it loads');
  });

  test('wired: Profil and the cover open the editor, "Yerini düzəlt" for a picture already there', () {
    final prof = src('lib/features/auth/presentation/profile_screen.dart');
    expect(prof, contains('onTap: _uploading ? null : () => _photoMenu(profile?.avatarUrl),'));
    expect(prof, contains('uploadAvatar(bytes, contentType: gif ? \'image/gif\' : file.mimeType, framing: framing)'));
    expect(prof, contains('setAvatarFraming(current, f)'));
    final pub = src('lib/features/ads/presentation/public_profile_screen.dart');
    expect(pub, contains('onPressed: () => _coverMenu(s, details?.coverUrl),'));
    expect(pub, contains('setCoverFraming(current, f)'));
    expect(pub, contains('framing: ImageFraming.of(details.coverUrl),'));
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in ['photo_new', 'photo_adjust', 'frame_reset']) {
        expect(m[k], isNotNull, reason: '$lang $k');
      }
    }
  });
}

// "FPS artırıcı" (owner, 16.11.2026): sharpness 1x · 2x · 3x and frame rate
// 30 · (40) · Maks in Ayarlar → Görünüş, kept on the device and applied by
// web/index.html before the app starts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/perf/display_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('choices follow the screen: up to its own sharpness; 40 only on 90 Hz+', () {
    const iphone = DisplayPrefs(nativeDpr: 3, refreshHz: 60);
    expect(iphone.scaleChoices, [1, 2, 3]);
    expect(iphone.fpsChoices, [30, 0], reason: '40 is uneven on a 60 Hz screen');
    expect(const DisplayPrefs(nativeDpr: 3, refreshHz: 120).fpsChoices, [30, 40, 0]);
    expect(const DisplayPrefs(nativeDpr: 2).scaleChoices, [1, 2]);
    expect(const DisplayPrefs(nativeDpr: 1).scaleChoices, isEmpty, reason: 'nothing to choose on a 1x screen');
    expect(const DisplayPrefs(nativeDpr: 2.625).scaleChoices, [1, 2, 3], reason: 'Android 2.625 rounds to 3');
  });

  test('what the visit uses and how it is reported', () {
    expect(const DisplayPrefs(nativeDpr: 3).effectiveScale, 3, reason: 'nothing chosen = the screen');
    expect(const DisplayPrefs(nativeDpr: 3, scale: 2, fpsCap: 30).summary, 'scale=2x fps=30');
    expect(const DisplayPrefs(nativeDpr: 2, scale: 3).effectiveScale, 2, reason: 'never above the screen');
  });

  test('saved on the device; the old admin 2x switch counts as 2x', () async {
    SharedPreferences.setMockInitialValues({'flutter.native_dpr': 3, 'flutter.perf_render2': true});
    var p = await DisplayPrefs.load();
    expect(p.scale, 2);
    await DisplayPrefs.saveScale(1);
    await DisplayPrefs.saveFps(30);
    p = await DisplayPrefs.load();
    expect((p.scale, p.fpsCap), (1, 30));
    expect((await SharedPreferences.getInstance()).getBool('perf_render2'), isNull, reason: 'old switch cleared');
  });

  test('index.html applies both before the app starts', () {
    final html = src('web/index.html');
    final script = html.substring(html.indexOf('<script id="render-scale">'));
    expect(html.indexOf('<script id="render-scale">'), lessThan(html.indexOf('<script src="flutter_bootstrap.js"')));
    expect(script, contains("ls.setItem('flutter.native_dpr', JSON.stringify(native));"));
    expect(script, contains("parseFloat(ls.getItem('flutter.render_scale') || '0')"));
    expect(script, contains('if (scale >= 1 && scale < native) {'), reason: 'never sharper than the screen');
    expect(script, contains("parseInt(ls.getItem('flutter.fps_cap') || '0', 10)"));
    expect(script, contains('if (cap === 30 || cap === 40) {'));
    expect(script, contains("ls.setItem('flutter.refresh_hz', JSON.stringify(hz));"));
  });

  test('wired: Ayarlar → Görünüş for everyone; Profil cover opened at its size', () {
    final settings = src('lib/features/auth/presentation/settings_screen.dart');
    expect(settings, contains('DisplaySpeedSettings(s: s),'));
    expect(settings, isNot(contains("('render2',")), reason: 'the admin test switch became the real setting');
    final profile = src('lib/features/auth/presentation/profile_screen.dart');
    expect(profile, contains('image: ResizeImage(NetworkImage(cover!),'));
  });

  testWidgets('the two rows on an iPhone: 1x 2x 3x and 30 FPS · Maks; a change offers "İndi yenidən aç"', (t) async {
    SharedPreferences.setMockInitialValues({'flutter.native_dpr': 3, 'flutter.refresh_hz': 60});
    const s = AppStrings({'display_res_title': 'Görüntü dəqiqliyi', 'display_fps_title': 'Kadr sürəti (FPS)',
        'display_fps_max': 'Maks (50–60)', 'display_restart_now': 'İndi yenidən aç'});
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: DisplaySpeedSettings(s: s))));
    await t.pumpAndSettle();
    for (final l in ['1x', '2x', '3x', '30 FPS', 'Maks (50–60)']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.text('40 FPS'), findsNothing, reason: '60 Hz screen');
    expect(find.text('İndi yenidən aç'), findsNothing);
    await t.tap(find.text('2x'));
    await t.pumpAndSettle();
    expect(find.text('İndi yenidən aç'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getInt('render_scale'), 2);
  });
}

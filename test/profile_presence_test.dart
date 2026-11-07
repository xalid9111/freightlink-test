// Another person's profile (owner, 07.11.2026): a verified account shows the
// blue badge on the photo's corner (where the online dot was); the online /
// offline state takes the old "Təsdiqlənmiş hesab" place — a round green
// (or grey) dot and its word.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/features/ads/presentation/public_profile_screen.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

Future<void> _pump(WidgetTester tester, Widget w) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: w))));

void main() {
  testWidgets('verified: the blue badge on the photo\'s lower right corner', (tester) async {
    await _pump(tester, const VerifiedCornerAvatar(initials: 'TE', verified: true));
    final badge = tester.getRect(find.byKey(const ValueKey('profile-verified-corner')));
    final photo = tester.getRect(find.byType(CircleAvatar));
    expect(badge.right, closeTo(photo.right + 1, 3));
    expect(badge.bottom, closeTo(photo.bottom + 1, 3));
    expect(tester.widget<Icon>(find.byIcon(Icons.verified)).color, AppColors.blue);
  });

  testWidgets('not verified: no badge on the photo, no online dot there', (tester) async {
    await _pump(tester, const VerifiedCornerAvatar(initials: 'TE', verified: false));
    expect(find.byKey(const ValueKey('profile-verified-corner')), findsNothing);
    expect(find.byIcon(Icons.verified), findsNothing);
  });

  testWidgets('online: a round green dot and "Online"; offline: grey and "Offline"', (tester) async {
    await _pump(tester, ProfilePresence(online: true, s: _az));
    expect(find.byKey(const ValueKey('profile-presence-online')), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    await _pump(tester, ProfilePresence(online: false, s: _az));
    expect(find.byKey(const ValueKey('profile-presence-offline')), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
  });

  test('wired on the profile page; texts in 6 languages', () {
    final p = src('lib/features/ads/presentation/public_profile_screen.dart');
    expect(p, contains('VerifiedCornerAvatar(imageUrl: p.avatarUrl, initials: p.initials, verified: p.isVerified),'));
    expect(p, contains('ProfilePresence(online: online, s: s),'));
    expect(p.contains("_Badge(icon: Icons.verified, label: s.t('pf_verified_account')"), isFalse, reason: 'the pill moved to the photo');
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = jsonDecode(src('assets/i18n/$l.json')) as Map;
      expect(j.containsKey('presence_online') && j.containsKey('presence_offline'), isTrue, reason: l);
    }
  });
}

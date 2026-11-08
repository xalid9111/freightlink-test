// Yüklər header (owner's picture, 08.11.2026): the profile picture 15 %
// bigger and, for a verified account only, the blue badge on its lower
// right edge; the rest of the header keeps its size and place.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/data/cargo_media_repository.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_media_providers.dart';
import 'package:freightlink/features/cargo/presentation/widgets/cargo_picture.dart';
import 'package:freightlink/repositories/profile_repository.dart';

final _az = AppStrings(Map<String, String>.from(jsonDecode(File('assets/i18n/az.json').readAsStringSync()) as Map));

class _Media implements CargoMediaRepository {
  @override
  Future<Set<String>> favoriteIds() async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester, {required bool verified}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      currentUserProvider.overrideWithValue(null),
      publicProfileProvider('u1').overrideWith((ref) async => PublicProfile(id: 'u1', fullName: 'Founder', isVerified: verified)),
      cargoFavoriteIdsProvider.overrideWith((ref) => CargoFavoritesController(_Media())),
    ],
    child: MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topRight, child: HeaderCircles(strings: _az)))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('verified: the blue badge on the picture; picture 15 % bigger, the header row keeps its size', (tester) async {
    await _pump(tester, verified: true);
    expect(find.byKey(const ValueKey('hdr-profile-verified')), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('hdr-profile'))).width, closeTo(42 * 1.15, 0.01));
    expect(tester.getSize(find.byKey(const ValueKey('hdr-favorites'))).width, 42, reason: 'the heart keeps its size');
    expect(tester.getSize(find.byType(HeaderCircles)).height, 42, reason: 'nothing else in the header moves');
    // On the lower right edge of the round picture.
    final pic = tester.getRect(find.byKey(const ValueKey('hdr-profile')));
    final badge = tester.getRect(find.byKey(const ValueKey('hdr-profile-verified')));
    expect(badge.center.dx, greaterThan(pic.center.dx));
    expect(badge.center.dy, greaterThan(pic.center.dy));
    expect(badge.right, greaterThan(pic.right - 6));
    expect(badge.bottom, greaterThan(pic.bottom - 6));
  });

  testWidgets('not verified: no badge', (tester) async {
    await _pump(tester, verified: false);
    expect(find.byKey(const ValueKey('hdr-profile-verified')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('hdr-profile'))).width, closeTo(42 * 1.15, 0.01));
  });
}


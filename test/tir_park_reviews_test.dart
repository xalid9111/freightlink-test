// TIRPark PR 2 (0078): park page with pictures, rating and comments; the
// author / an admin manages pictures; one comment per user.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/tirpark/data/tir_park_repository.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_detail_screen.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

const _park = TirPark(
  id: 'p1',
  name: 'Utep TIR Parkı',
  lat: 40.456,
  lng: 49.73,
  city: 'Xırdalan',
  amenities: ['secure', 'food'],
  status: 'approved',
  ratingAvg: 4.5,
  ratingCount: 2,
  createdBy: 'author',
);

class _Repo extends TirParkRepository {
  final saved = <String>[];
  final deleted = <String>[];
  List<String>? photos;
  @override
  Future<List<TirParkReview>> reviews(String parkId) async => const [
        TirParkReview(id: 'r1', userId: 'u2', rating: 4, comment: 'Təmiz, təhlükəsiz', name: 'Rəşad'),
        TirParkReview(id: 'r2', userId: 'me', rating: 5, name: 'Mən'),
      ];
  @override
  Future<void> saveReview(String parkId, int rating, String? comment) async => saved.add('$rating|${comment ?? ''}');
  @override
  Future<void> deleteReview(String id) async => deleted.add(id);
  @override
  Future<String> uploadPhoto(String parkId, Uint8List bytes, {String? contentType}) async => 'x';
  @override
  Future<void> setPhotos(String parkId, List<String> urls) async => photos = urls;
}

Widget _app(_Repo repo, {required String me, String role = 'carrier', TirPark park = _park, bool write = false}) => ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_az),
        tirParkRepositoryProvider.overrideWithValue(repo),
        tirParksProvider.overrideWith((ref) async => [park]),
        currentUserProvider.overrideWithValue(AppUser(id: me, email: 'a@b.az', fullName: 'Mən', role: role, isVerified: true)),
      ],
      child: MaterialApp(home: TirParkDetailScreen(parkId: park.id, write: write)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('park page: rating, amenities, comments; my comment can be changed and deleted', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(_app(repo, me: 'me'));
    await tester.pumpAndSettle();
    for (final t in ['Utep TIR Parkı', '4.5', 'Təhlükəsiz', 'Yemək', 'Şərhlər (2)', 'Təmiz, təhlükəsiz', 'Rəşad', 'Şərhimi dəyiş']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byKey(const ValueKey('tp-review-delete-r2')), findsOneWidget, reason: 'mine');
    expect(find.byKey(const ValueKey('tp-review-delete-r1')), findsNothing, reason: 'not mine');
    expect(find.byKey(const ValueKey('tp-photo-add')), findsNothing, reason: 'not the author');

    // Change my comment: the stars are required, the text is optional.
    await tester.tap(find.byKey(const ValueKey('tp-write')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tp-star-3')));
    await tester.enterText(find.byKey(const ValueKey('tp-review-text')), 'Orta');
    await tester.tap(find.byKey(const ValueKey('tp-review-save')));
    await tester.pumpAndSettle();
    expect(repo.saved, ['3|Orta']);

    await tester.tap(find.byKey(const ValueKey('tp-review-delete-r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tp-review-delete-ok')));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['r2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Şərh yaz" from the card opens the form at once; no stars → not sent', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(_app(repo, me: 'someone', write: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tp-review-save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-review-save')));
    await tester.pumpAndSettle();
    expect(find.text('Ulduz seçin (1–5)'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('pictures: admins only add / replace / delete (owner, 31.10.2026)', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    const withPhotos = TirPark(
        id: 'p1', name: 'P', lat: 40, lng: 49, status: 'approved', createdBy: 'author',
        photoUrls: ['https://x.supabase.co/storage/v1/object/public/profile-media/a/1.jpg', 'https://x.supabase.co/storage/v1/object/public/profile-media/a/2.jpg']);
    await tester.pumpWidget(_app(_Repo(), me: 'author', park: withPhotos));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tp-photo-add')), findsNothing, reason: 'not even the park\'s author');
    await tester.pumpWidget(_app(repo, me: 'boss', role: 'admin', park: withPhotos));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tp-photo-add')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-thumb-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tp-photo-delete')));
    await tester.pumpAndSettle();
    expect(repo.photos, ['https://x.supabase.co/storage/v1/object/public/profile-media/a/2.jpg']);

  });

  testWidgets('the card: "Şərhlər (n) ›" and "Şərh yaz" (approved parks only)', (tester) async {
    var opened = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TirParkCard(park: _park, km: 2.5, s: _az, onTap: () {}, onReviews: () => opened = 'r', onWrite: () => opened = 'w'),
          TirParkCard(
              park: const TirPark(id: 'p2', name: 'Gözləyən', lat: 1, lng: 1), km: 1, s: _az, onTap: () {}, onReviews: () {}, onWrite: () {}),
        ]),
      ),
    ));
    expect(find.text('Şərhlər (2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('tp-write-p2')), findsNothing, reason: 'pending: no comments yet');
    await tester.tap(find.byKey(const ValueKey('tp-write-p1')));
    expect(opened, 'w');
    await tester.tap(find.byKey(const ValueKey('tp-reviews-p1')));
    expect(opened, 'r');
  });

  test('wired: route, one comment per user, rating by the server, pictures only from profile-media', () {
    expect(src('lib/core/router/app_router.dart'), contains("path: 'p/:id',"));
    final sql = src('supabase/migrations/0078_tir_park_reviews_photos.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'alter table public.users', 'drop column']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('unique (park_id, user_id)'));
    expect(sql, contains("perform set_config('app.tir_park_rating', 'on', true);"));
    expect(sql, contains("v_url !~ '^https://[^ ]+/storage/v1/object/public/profile-media/'"));
    final photos = sql.substring(sql.indexOf('function public.tir_park_set_photos('));
    expect(photos.substring(0, photos.indexOf(r'end $$')), contains('perform public._require_admin();'), reason: 'admins only');
    expect(sql, contains('create table if not exists public.tirpark_hero ('));
    expect(sql, contains("elsif p_page = 'tirpark' then"));
    // The TIRPark banner: the admin pencil, the shared editor; GIF kept.
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart'), contains("page: 'tirpark',"));
    expect(src('lib/features/tirpark/presentation/map_page_banner.dart'), contains('showPageHeroEditor(context, strings: s, page: page,'));
    final hero = src('lib/core/widgets/page_hero.dart');
    expect(hero, contains("'tirpark': 'tirpark_hero'"));
    expect(hero, contains("'gif' => 'image/gif'"));
    expect(hero, contains("isGifBytes(bytes) ? 'gif'"));
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in ['tp_reviews_short', 'tp_write', 'tp_review_send', 'tp_photo_replace', 'tp_delete', 'tp_review_stars_required']) {
        expect(m[k], isNotNull, reason: '$lang $k');
      }
    }
  });
}

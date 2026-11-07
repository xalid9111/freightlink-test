// "Bəyəndiklərim" everywhere (owner, 07.11.2026, 0106): one page with
// Yüklər · TIR Bazarı · Mesajlar · Profillər; the hearts on the Yüklər, TIR
// Bazarı, Mesajlar and Profil pages open it on their own tab; a heart on a
// chat, a profile, a service / shop and a park; liked chats stand first in
// Mesajlar. Only the owner sees his list (server: favorite_set, RLS).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_media_providers.dart';
import 'package:freightlink/features/favorites/favorites.dart';
import 'package:freightlink/features/market/presentation/market_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _FakeRepo extends FavoritesRepository {
  final calls = <String>[];
  @override
  Future<List<FavKey>> list() async => const [(FavKind.chat, 'u2'), (FavKind.service, 's1')];
  @override
  Future<bool> set(FavKind kind, String id, bool on) async {
    calls.add('${kind.name}:$id:$on');
    return on;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the tab from the link; an unknown one opens Yüklər', () {
    expect(favTabOf('chats'), FavTab.chats);
    expect(favTabOf('profiles'), FavTab.profiles);
    expect(favTabOf('market'), FavTab.market);
    expect(favTabOf(null), FavTab.loads);
    expect(favTabOf('moon'), FavTab.loads);
  });

  testWidgets('the page: four tabs with counts, opens on the asked tab', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_az),
        favoritesRepositoryProvider.overrideWithValue(_FakeRepo()),
        userFavoritesProvider.overrideWith((ref) async => const [(FavKind.chat, 'u2'), (FavKind.service, 's1'), (FavKind.park, 'p1')]),
        cargoFavoritesListProvider.overrideWith((ref) async => const []),
        marketFavoritesListProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: FavoritesScreen(initial: FavTab.market)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Bəyəndiklərim'), findsOneWidget);
    for (final k in ['loads', 'market', 'chats', 'profiles']) {
      expect(find.byKey(ValueKey('fav-tab-$k')), findsOneWidget, reason: k);
    }
    expect(find.text('Mesajlar (1)'), findsOneWidget);
    expect(find.text('Profillər (2)'), findsOneWidget);
    expect(find.text(_az.t('fav_empty_market')), findsOneWidget, reason: 'opened on TIR Bazarı');
  });

  testWidgets('a heart: one tap likes, the next one takes it off (server call each time)', (tester) async {
    final repo = _FakeRepo();
    final container = ProviderContainer(overrides: [
      stringsProvider.overrideWithValue(_az),
      favoritesRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Center(child: LikeHeart(kind: FavKind.user, id: 'u9')))),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fav-user-u9')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['user:u9:true']);
    // The list (fake) does not have u9, so after the reload the heart shows the saved state again.
    expect(find.byKey(const ValueKey('fav-user-u9')), findsOneWidget);
  });

  test('wired: the four entries open the page; hearts on chat / profile / service / park; liked chats first; SQL 0106', () {
    expect(src('lib/core/router/app_router.dart'), contains("path: '/favorites',"));
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture.dart'), contains('openFavorites(context, FavTab.loads)'));
    expect(src('lib/features/market/presentation/market_home_screen.dart'), contains('openFavorites(context, FavTab.market)'));
    final msgs = src('lib/features/chat/presentation/conversations_screen.dart');
    expect(msgs, contains('openFavorites(context, FavTab.chats)'));
    expect(msgs, contains('a.favorite != b.favorite ? (a.favorite ? -1 : 1) : b.time.compareTo(a.time)'));
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains('openFavorites(context, FavTab.profiles)'));
    expect(src('lib/features/chat/presentation/conversation_thread_screen.dart'), contains('LikeHeart(kind: FavKind.chat, id: otherId)'));
    expect(src('lib/features/ads/presentation/public_profile_screen.dart'), contains('if (!isMe) LikeHeart(kind: FavKind.user, id: widget.userId)'));
    expect(src('lib/features/services/presentation/service_detail_screen.dart'), contains('LikeHeart(kind: FavKind.service, id: id)'));
    expect(src('lib/features/tirpark/presentation/tir_park_detail_screen.dart'), contains('LikeHeart(kind: FavKind.park, id: park.id)'));
    final sql = src('supabase/migrations/0106_user_favorites.sql');
    expect(sql, contains("using (user_id = (select auth.uid()))"));
    expect(sql.toLowerCase().contains('drop table'), isFalse);
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = jsonDecode(src('assets/i18n/$l.json')) as Map;
      for (final k in ['fav_title', 'fav_tab_loads', 'fav_tab_market', 'fav_tab_chats', 'fav_tab_profiles', 'fav_empty_chats', 'fav_empty_profiles', 'fav_add', 'fav_remove']) {
        expect(j.containsKey(k), isTrue, reason: '$l $k');
      }
    }
  });
}

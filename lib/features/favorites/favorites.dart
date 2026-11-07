import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/supabase_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/localization/locale_controller.dart';
import '../../core/router/safe_navigation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/user_avatar.dart';
import '../../repositories/profile_repository.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../cargo/presentation/providers/cargo_media_providers.dart';
import '../cargo/presentation/widgets/cargo_card.dart';
import '../market/presentation/market_providers.dart';
import '../services/presentation/services_providers.dart' show serviceByIdProvider;
import '../tirpark/data/tir_park_repository.dart' show tirParksProvider;

/// "Bəyəndiklərim" (owner, 07.11.2026, 0106). Loads and TIR Bazarı ads keep
/// their own hearts (0058 / 0040); chats (a person's Mesajlar row), people's
/// profiles, services / shops and parks are kept in user_favorites. Only the
/// owner sees his list; favorite_set checks what is liked.
enum FavKind { chat, user, service, park }

typedef FavKey = (FavKind, String);

class FavoritesRepository {
  Future<List<FavKey>> list() async {
    try {
      final rows = await SupabaseConfig.client
          .from('user_favorites')
          .select('kind,target_id,created_at')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 15));
      return [
        for (final r in rows as List)
          if (FavKind.values.where((k) => k.name == r['kind']).firstOrNull case final k?) (k, '${r['target_id']}'),
      ];
    } catch (_) {
      return const []; // before SQL 0106 / offline
    }
  }

  Future<bool> set(FavKind kind, String id, bool on) async {
    final res = await SupabaseConfig.client
        .rpc('favorite_set', params: {'p_kind': kind.name, 'p_id': id, 'p_on': on}).timeout(const Duration(seconds: 15));
    return res == true;
  }
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) => FavoritesRepository());

/// My favourites (chats, profiles, services, parks), newest first.
final userFavoritesProvider = FutureProvider<List<FavKey>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return const <FavKey>[];
  return ref.watch(favoritesRepositoryProvider).list();
});

bool isFavorite(WidgetRef ref, FavKind kind, String id) =>
    (ref.watch(userFavoritesProvider).valueOrNull ?? const <FavKey>[]).contains((kind, id));

/// The heart on a chat / profile / service / park: one tap = liked / not.
class LikeHeart extends ConsumerStatefulWidget {
  final FavKind kind;
  final String id;
  final double size;
  const LikeHeart({super.key, required this.kind, required this.id, this.size = 24});

  @override
  ConsumerState<LikeHeart> createState() => _LikeHeartState();
}

class _LikeHeartState extends ConsumerState<LikeHeart> {
  bool? _shown; // what the user just tapped, until the list reloads
  bool _busy = false;

  Future<void> _toggle(bool now, AppStrings s) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _shown = !now;
    });
    try {
      await ref.read(favoritesRepositoryProvider).set(widget.kind, widget.id, !now);
      ref.invalidate(userFavoritesProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _shown = now);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('fav_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final saved = isFavorite(ref, widget.kind, widget.id);
    if (!_busy) _shown = null;
    final on = _shown ?? saved;
    return IconButton(
      key: ValueKey('fav-${widget.kind.name}-${widget.id}'),
      tooltip: s.t(on ? 'fav_remove' : 'fav_add'),
      onPressed: () => _toggle(on, s),
      icon: Icon(on ? Icons.favorite : Icons.favorite_border, size: widget.size, color: on ? AppColors.accent : null),
    );
  }
}

/// The hub's tabs, in this order.
enum FavTab { loads, market, chats, profiles }

FavTab favTabOf(String? q) => FavTab.values.where((t) => t.name == q).firstOrNull ?? FavTab.loads;

/// The heart that opens "Bəyəndiklərim" on [tab] (Yüklər, TIR Bazarı,
/// Mesajlar, Profil headers).
void openFavorites(BuildContext context, FavTab tab) => context.pushOnce('/favorites?tab=${tab.name}');

/// "Bəyəndiklərim": Yüklər · TIR Bazarı · Mesajlar · Profillər, with counts;
/// a tap opens the load / ad / chat / profile.
class FavoritesScreen extends ConsumerWidget {
  final FavTab initial;
  const FavoritesScreen({super.key, this.initial = FavTab.loads});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    // Counted from the lists (only loads / ads that still exist).
    final loads = ref.watch(cargoFavoritesListProvider).valueOrNull?.length ?? 0;
    final ads = ref.watch(marketFavoritesListProvider).valueOrNull?.length ?? 0;
    final mine = ref.watch(userFavoritesProvider).valueOrNull ?? const <FavKey>[];
    final chats = mine.where((f) => f.$1 == FavKind.chat).toList();
    final profiles = mine.where((f) => f.$1 != FavKind.chat).toList();
    String label(String key, int n) => n > 0 ? '${s.t(key)} ($n)' : s.t(key);
    return DefaultTabController(
      length: FavTab.values.length,
      initialIndex: initial.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('fav_title')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: const ValueKey('fav-tab-loads'), text: label('fav_tab_loads', loads)),
              Tab(key: const ValueKey('fav-tab-market'), text: label('fav_tab_market', ads)),
              Tab(key: const ValueKey('fav-tab-chats'), text: label('fav_tab_chats', chats.length)),
              Tab(key: const ValueKey('fav-tab-profiles'), text: label('fav_tab_profiles', profiles.length)),
            ],
          ),
        ),
        body: TabBarView(children: [
          _LoadsTab(s: s),
          _MarketTab(s: s),
          _PeopleTab(s: s, items: chats, emptyKey: 'fav_empty_chats'),
          _PeopleTab(s: s, items: profiles, emptyKey: 'fav_empty_profiles'),
        ]),
      ),
    );
  }
}

Widget _empty(AppStrings s, String key) => ListView(children: [
      Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.favorite_border, size: 44, color: AppColors.textSoft),
          const SizedBox(height: 12),
          Text(s.t(key), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
        ]),
      ),
    ]);

class _LoadsTab extends ConsumerWidget {
  final AppStrings s;
  const _LoadsTab({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(cargoFavoritesListProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _empty(s, 'home_error_loading'),
        data: (list) => list.isEmpty
            ? _empty(s, 'fav_cargo_empty')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => CargoCard(
                  cargo: list[i],
                  strings: s,
                  compact: true,
                  onTap: () => context.pushOnce('/load/${list[i].id}'),
                ),
              ),
      );
}

class _MarketTab extends ConsumerWidget {
  final AppStrings s;
  const _MarketTab({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(marketFavoritesListProvider).when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _empty(s, 'home_error_loading'),
        data: (list) => list.isEmpty
            ? _empty(s, 'fav_empty_market')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final l = list[i];
                  return _Row(
                    key: ValueKey('fav-ad-${l.id}'),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 64,
                        height: 48,
                        child: l.cover == null
                            ? ColoredBox(color: AppColors.cardAlt, child: Icon(Icons.local_shipping_outlined, color: AppColors.textSoft))
                            : Image.network(l.cover!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.cardAlt)),
                      ),
                    ),
                    title: l.title,
                    line: [if (l.price != null) '${l.price!.toStringAsFixed(0)} ${l.currency}', if ((l.city ?? '').isNotEmpty) l.city!].join(' · '),
                    onTap: () => context.pushOnce('/market/l/${l.id}'),
                  );
                },
              ),
      );
}

/// Chats (a person) and profiles (a person / service / shop / park).
class _PeopleTab extends ConsumerWidget {
  final AppStrings s;
  final List<FavKey> items;
  final String emptyKey;
  const _PeopleTab({required this.s, required this.items, required this.emptyKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(userFavoritesProvider).isLoading && items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return _empty(s, emptyKey);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => FavoriteRow(s: s, fav: items[i]),
    );
  }
}

/// One liked chat / profile, with its heart (a tap on the heart takes it off).
class FavoriteRow extends ConsumerWidget {
  final AppStrings s;
  final FavKey fav;
  const FavoriteRow({super.key, required this.s, required this.fav});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (kind, id) = fav;
    String title = '…', line = '';
    Widget leading = const UserAvatar(initials: '?', radius: 24);
    String route;
    switch (kind) {
      case FavKind.chat || FavKind.user:
        final p = ref.watch(publicProfileProvider(id)).valueOrNull;
        title = (p?.fullName ?? '').isEmpty ? '…' : p!.fullName;
        line = s.t(kind == FavKind.chat ? 'fav_kind_chat' : 'fav_kind_user');
        leading = UserAvatar(imageUrl: p?.avatarUrl, initials: p?.initials ?? '?', radius: 24);
        route = kind == FavKind.chat ? '/messages/with/$id' : '/user/$id';
      case FavKind.service:
        final sp = ref.watch(serviceByIdProvider(id)).valueOrNull;
        title = sp?.name ?? '…';
        line = [s.t(sp?.isShop == true ? 'fav_kind_shop' : 'fav_kind_service'), if ((sp?.city ?? '').isNotEmpty) sp!.city!].join(' · ');
        leading = _iconCircle(sp?.isShop == true ? Icons.storefront : Icons.build);
        route = '/service/$id';
      case FavKind.park:
        final pk = (ref.watch(tirParksProvider).valueOrNull ?? const []).where((x) => x.id == id).firstOrNull;
        title = pk?.name ?? '…';
        line = [s.t('fav_kind_park'), if ((pk?.city ?? '').isNotEmpty) pk!.city!].join(' · ');
        leading = _iconCircle(Icons.local_parking);
        route = '/tirpark/p/$id';
    }
    return _Row(
      key: ValueKey('fav-row-${kind.name}-$id'),
      leading: leading,
      title: title,
      line: line,
      trailing: LikeHeart(kind: kind, id: id, size: 22),
      onTap: () => context.pushOnce(route),
    );
  }

  Widget _iconCircle(IconData i) => CircleAvatar(radius: 24, backgroundColor: AppColors.cardAlt, child: Icon(i, color: AppColors.accent));
}

class _Row extends StatelessWidget {
  final Widget leading;
  final String title, line;
  final Widget? trailing;
  final VoidCallback onTap;
  const _Row({super.key, required this.leading, required this.title, required this.line, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text, fontSize: 15)),
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                  ],
                ]),
              ),
              if (trailing != null) trailing! else Icon(Icons.chevron_right, color: AppColors.textSoft),
            ]),
          ),
        ),
      );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../data/market_repository.dart';
import '../domain/market_models.dart';

/// Filters of the TIR Bazarı feed (category chip, search, filter sheet).
final marketFilterProvider = StateProvider<MarketFilter>((ref) => const MarketFilter());

class MarketFeedState {
  final List<MarketListing> items;
  final bool loading;
  final bool hasMore;
  final Object? error;
  const MarketFeedState({this.items = const [], this.loading = false, this.hasMore = true, this.error});
}

/// Feed loaded page by page (20 at a time) while scrolling.
class MarketFeedController extends StateNotifier<MarketFeedState> {
  MarketFeedController(this._repo, this._filter) : super(const MarketFeedState()) {
    loadMore();
  }

  final MarketRepository _repo;
  final MarketFilter _filter;

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    state = MarketFeedState(items: state.items, loading: true, hasMore: state.hasMore);
    try {
      final page = await _repo.search(_filter, offset: state.items.length);
      if (!mounted) return;
      state = MarketFeedState(items: [...state.items, ...page], hasMore: page.length >= kMarketPageSize);
    } catch (e) {
      if (!mounted) return;
      state = MarketFeedState(items: state.items, hasMore: state.hasMore, error: e);
    }
  }
}

final marketFeedProvider = StateNotifierProvider.autoDispose<MarketFeedController, MarketFeedState>((ref) {
  ref.watch(currentUserIdProvider);
  return MarketFeedController(ref.watch(marketRepositoryProvider), ref.watch(marketFilterProvider));
});

final marketVipProvider = FutureProvider.autoDispose.family<List<MarketListing>, MarketCategory?>((ref, c) {
  ref.watch(currentUserIdProvider);
  return ref.watch(marketRepositoryProvider).vip(category: c);
});

final marketListingProvider = FutureProvider.autoDispose.family<MarketListing?, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(marketRepositoryProvider).byId(id);
});

final marketSimilarProvider = FutureProvider.autoDispose.family<List<MarketListing>, String>((ref, id) {
  return ref.watch(marketRepositoryProvider).similar(id);
});

final myMarketListingsProvider = FutureProvider.autoDispose<List<MarketListing>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(marketRepositoryProvider).mine();
});

final marketFavoritesListProvider = FutureProvider.autoDispose<List<MarketListing>>((ref) {
  ref.watch(marketFavoriteIdsProvider); // refresh when a heart changes
  return ref.watch(marketRepositoryProvider).favorites();
});

/// Hearts: ids of my favourites; a tap changes it at once (optimistic).
class MarketFavoritesController extends StateNotifier<Set<String>> {
  MarketFavoritesController(this._repo) : super(const {}) {
    _repo.favoriteIds().then((s) {
      if (mounted) state = s;
    }).catchError((_) {});
  }

  final MarketRepository _repo;

  Future<void> toggle(String id) async {
    final on = !state.contains(id);
    final before = state;
    state = on ? {...state, id} : ({...state}..remove(id));
    try {
      await _repo.setFavorite(id, on);
    } catch (_) {
      state = before;
      rethrow;
    }
  }
}

final marketFavoriteIdsProvider = StateNotifierProvider<MarketFavoritesController, Set<String>>((ref) {
  ref.watch(currentUserIdProvider);
  return MarketFavoritesController(ref.watch(marketRepositoryProvider));
});

/// The admin's banner at the top of TIR Bazarı (computer view).
final marketHeroProvider = FutureProvider.autoDispose<MarketHero?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(marketRepositoryProvider).hero();
});

/// The 6 newest VIP ads for the VIP places beside the ads (computer view).
final marketVipLatestProvider = FutureProvider.autoDispose.family<List<MarketListing>, MarketCategory?>((ref, c) {
  ref.watch(currentUserIdProvider);
  return ref.watch(marketRepositoryProvider).vipLatest(category: c);
});

/// VIP prices (7 / 14 / 30 days); [activeOnly] false = the admin list.
final marketVipPlansProvider = FutureProvider.autoDispose.family<List<MarketVipPlan>, bool>((ref, activeOnly) {
  ref.watch(currentUserIdProvider);
  return ref.watch(marketRepositoryProvider).vipPlans(activeOnly: activeOnly);
});

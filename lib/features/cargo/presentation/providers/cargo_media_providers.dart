import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/cargo_model.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/cargo_media_repository.dart';
import '../../../market/domain/market_models.dart';
import '../../domain/cargo_vip.dart';

final cargoMediaRepositoryProvider = Provider<CargoMediaRepository>((ref) => CargoMediaRepository());

/// All the admin's load-type pictures (0058), read ONCE and kept for the
/// session (owner, 09.11.2026: scrolling back up never asks the server
/// again, so a card's picture never "re-opens"). Empty until 0058 is run.
/// An admin's change invalidates it (admin_cargo_pictures_page.dart).
final allCargoTemplatesProvider = FutureProvider<List<CargoTemplate>>((ref) async {
  try {
    return await ref.watch(cargoMediaRepositoryProvider).allTemplates();
  } catch (_) {
    return const [];
  }
});

/// The pictures of one load type, at once from the kept list (no loading
/// step when a card comes back into view). Same order as before.
final cargoTemplatesProvider = Provider.family<AsyncValue<List<CargoTemplate>>, String>((ref, category) =>
    ref.watch(allCargoTemplatesProvider).whenData((all) => [for (final t in all) if (t.category == category) t]));

/// Hearts: ids of my favourite loads; a tap changes it at once
/// (optimistic, put back if the server refuses).
class CargoFavoritesController extends StateNotifier<Set<String>> {
  CargoFavoritesController(this._repo) : super(const {}) {
    _repo.favoriteIds().then((s) {
      if (mounted) state = s;
    }).catchError((_) {});
  }

  final CargoMediaRepository _repo;

  Future<void> toggle(String id) async {
    final on = !state.contains(id);
    final before = state;
    state = on ? {...state, id} : ({...state}..remove(id));
    try {
      await _repo.setFavorite(id, on);
    } catch (_) {
      if (mounted) state = before;
      rethrow;
    }
  }
}

final cargoFavoriteIdsProvider = StateNotifierProvider<CargoFavoritesController, Set<String>>((ref) {
  ref.watch(currentUserIdProvider);
  return CargoFavoritesController(ref.watch(cargoMediaRepositoryProvider));
});

final cargoFavoritesListProvider = FutureProvider.autoDispose<List<CargoModel>>((ref) {
  ref.watch(cargoFavoriteIdsProvider); // refresh when a heart changes
  return ref.watch(cargoMediaRepositoryProvider).favorites();
});

/// Load İrəli çək / VIP / Premium packs (0067); [activeOnly] false = the
/// admin list.
final cargoPromoPlansProvider =
    FutureProvider.autoDispose.family<List<MarketPromoPlan>, (MarketPromoKind, bool)>((ref, k) {
  return ref.watch(cargoMediaRepositoryProvider).promoPlans(k.$1, activeOnly: k.$2);
});

/// Load VIP prices (0062); [activeOnly] false = the admin list.
final cargoVipPlansProvider = FutureProvider.autoDispose.family<List<CargoVipPlan>, bool>((ref, activeOnly) {
  return ref.watch(cargoMediaRepositoryProvider).vipPlans(activeOnly: activeOnly);
});

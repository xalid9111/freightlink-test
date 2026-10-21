import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../models/cargo_model.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/cargo_categories.dart';
import 'cargo_providers.dart';

/// Tile / big-small choice on the Loads page (works with the route filter).
final cargoCategoryFilterProvider = StateProvider<CargoCategoryFilter>((ref) => const CargoCategoryFilter());

/// Open loads of the chosen category, filtered on the server (0055,
/// indexed). Nothing chosen → the whole open marketplace. Until 0055 is
/// run the same rule is applied to the loaded list.
final categoryFeedProvider = FutureProvider<List<CargoModel>>((ref) async {
  final f = ref.watch(cargoCategoryFilterProvider);
  if (!f.isActive) return ref.watch(marketplaceProvider.future);
  ref.watch(currentUserIdProvider);
  try {
    return await ref
        .watch(cargoRepositoryProvider)
        .fetchByCategory(truckType: f.truckType, groupage: f.groupage, loadSize: f.size);
  } on AppException catch (e) {
    if (e.code != '42703' && e.code != 'PGRST204' && !CargoModel.sizeColumns.any(e.message.contains)) rethrow;
    final all = await ref.watch(marketplaceProvider.future);
    return all.where(f.matches).toList();
  }
});

/// Pictures of the "Böyük yüklər" / "Kiçik yüklər" cards (0055), set by an
/// admin: size → picture URL (null = the plain card).
class CargoSizeCardsRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<Map<String, String?>> fetch() async {
    final rows = await _c.from('cargo_size_cards').select('size, image_url').timeout(const Duration(seconds: 15));
    return {for (final r in rows as List) '${r['size']}': r['image_url'] as String?};
  }

  /// Admins only — checked on the server. [url] null removes the picture.
  Future<void> save(String size, String? url) =>
      _c.rpc('admin_set_cargo_size_card', params: {'p_size': size, 'p_image_url': url}).timeout(const Duration(seconds: 15));
}

final cargoSizeCardsRepositoryProvider = Provider<CargoSizeCardsRepository>((ref) => CargoSizeCardsRepository());

final cargoSizeCardsProvider = FutureProvider<Map<String, String?>>((ref) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.watch(cargoSizeCardsRepositoryProvider).fetch();
  } catch (_) {
    // 0055 not run yet or offline: plain cards.
    return const {};
  }
});

/// Same values for the size cards, also used in tests.
const kSizeCards = [
  (size: kLoadSizeBig, titleKey: 'cargo_size_big', subtitleKey: 'cargo_size_big_sub'),
  (size: kLoadSizeSmall, titleKey: 'cargo_size_small', subtitleKey: 'cargo_size_small_sub'),
];

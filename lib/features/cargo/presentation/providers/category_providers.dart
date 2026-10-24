import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  // Refreshed together with the marketplace (a load posted, edited,
  // deleted or switched off) — the chosen tile showed an old list.
  ref.watch(marketplaceProvider);
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../models/cargo_model.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/cargo_categories.dart';
import 'cargo_providers.dart';

/// Kept on this device, read before runApp (owner, 25.10.2026).
SharedPreferences? _prefs;

Future<void> loadCargoCategoryPrefs() async {
  try {
    _prefs = await SharedPreferences.getInstance();
  } catch (_) {
    _prefs = null;
  }
}

/// One key per account (and one for signed-out use): accounts never see
/// each other's choice.
String cargoCategoryPrefsKey(String? userId) => 'cargo_category_v1:${userId ?? 'guest'}';

/// Tile / big-small choice on the Loads page (works with the route filter).
/// The tile (or QRUPAJ) is remembered for the signed-in account and is
/// chosen again when the app opens; big / small is not kept.
class CargoCategoryController extends StateController<CargoCategoryFilter> {
  final String _key;
  CargoCategoryController(this._key) : super(_saved(_key));

  static CargoCategoryFilter _saved(String key) {
    try {
      return CargoCategoryFilter.fromSaved(_prefs?.getString(key));
    } catch (_) {
      return const CargoCategoryFilter();
    }
  }

  @override
  set state(CargoCategoryFilter value) {
    super.state = value;
    final prefs = _prefs;
    if (prefs == null || prefs.getString(_key) == value.savedKey) return;
    prefs.setString(_key, value.savedKey).catchError((_) => false);
  }
}

final cargoCategoryFilterProvider = StateNotifierProvider<CargoCategoryController, CargoCategoryFilter>(
    (ref) => CargoCategoryController(cargoCategoryPrefsKey(ref.watch(currentUserIdProvider))));

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

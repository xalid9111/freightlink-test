import '../../../models/cargo_model.dart';
import 'cargo_feed_first.dart';
import 'cargo_feed_pages.dart' show kCargoPageSize;

abstract class CargoRepository {
  /// Yüklər page by page (SQL 0109): the loads with a running VIP /
  /// Premium, one page of the other loads after [after], the counter.
  Future<List<CargoModel>> fetchFeedPromoted();
  Future<List<CargoModel>> fetchFeedPage({int limit = kCargoPageSize, CargoModel? after});
  Future<int> fetchFeedCount();

  /// The first, small part of the open-loads feed (owner, 09.11.2026):
  /// every promoted load + the [newest] newest loads (cargo_feed_first.dart).
  Future<CargoFeedPart> fetchMarketplaceFirst({int newest = kCargoFirstPage});

  Future<List<CargoModel>> fetchMarketplace({
    String? pickupCountry,
    String? destinationCountry,
    String? cargoType,
    String? truckType,
    double? minPrice,
    double? maxPrice,
    double? maxWeightKg,
  });

  /// Open loads of one category (Loads page tiles / big-small cards),
  /// filtered on the server (indexed, 0055).
  Future<List<CargoModel>> fetchByCategory({String? truckType, bool groupage = false, String? loadSize});

  Future<CargoModel> fetchById(String id);
  Future<CargoModel> create(CargoModel cargo);
  Future<void> update(CargoModel cargo);
  Future<void> delete(String id);

  /// Cargo currently loading/in transit for this carrier's destination
  /// country — used by the return-cargo AI feature (Phase 11/13).
  Future<List<CargoModel>> fetchReturnCandidates({required String fromCountry});
}

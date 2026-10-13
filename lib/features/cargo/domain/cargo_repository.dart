import '../../../models/cargo_model.dart';

abstract class CargoRepository {
  Future<List<CargoModel>> fetchMarketplace({
    String? pickupCountry,
    String? destinationCountry,
    String? cargoType,
    String? truckType,
    double? minPrice,
    double? maxPrice,
    double? maxWeightKg,
  });

  Future<CargoModel> fetchById(String id);
  Future<CargoModel> create(CargoModel cargo);
  Future<void> update(CargoModel cargo);
  Future<void> delete(String id);

  /// Cargo currently loading/in transit for this carrier's destination
  /// country — used by the return-cargo AI feature (Phase 11/13).
  Future<List<CargoModel>> fetchReturnCandidates({required String fromCountry});
}

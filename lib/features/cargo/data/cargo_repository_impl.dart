import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/cargo_model.dart';
import '../domain/cargo_repository.dart';

class CargoRepositoryImpl implements CargoRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  @override
  Future<List<CargoModel>> fetchMarketplace({
    String? pickupCountry,
    String? destinationCountry,
    String? cargoType,
    String? truckType,
    double? minPrice,
    double? maxPrice,
    double? maxWeightKg,
  }) async {
    try {
      var query = _client.from('cargo').select().eq('status', 'new');
      if (pickupCountry != null) query = query.eq('pickup_country', pickupCountry);
      if (destinationCountry != null) query = query.eq('destination_country', destinationCountry);
      if (cargoType != null) query = query.eq('cargo_type', cargoType);
      if (truckType != null) query = query.eq('truck_type', truckType);
      if (minPrice != null) query = query.gte('offered_price', minPrice);
      if (maxPrice != null) query = query.lte('offered_price', maxPrice);
      if (maxWeightKg != null) query = query.lte('weight_kg', maxWeightKg);

      final rows = await query.order('created_at', ascending: false);
      // Loads hidden by an admin are filtered by RLS (0012) for everyone
      // else; this also keeps the owner's own hidden loads out of the feed.
      return (rows as List).map((r) => CargoModel.fromJson(r)).where((c) => !c.isHidden).toList();
    } on PostgrestException catch (e) {
      throw AppException(e.message, code: e.code);
    }
  }

  @override
  Future<CargoModel> fetchById(String id) async {
    final row = await _client.from('cargo').select().eq('id', id).single();
    return CargoModel.fromJson(row);
  }

  @override
  Future<CargoModel> create(CargoModel cargo) async {
    // RLS requires owner_id = auth.uid() (migration 0002); an attempt to
    // post cargo under someone else's id is rejected at the database,
    // not just hidden by the UI.
    final row = await _client.from('cargo').insert(cargo.toInsertJson()).select().single();
    return CargoModel.fromJson(row);
  }

  @override
  Future<void> update(CargoModel cargo) async {
    await _client.from('cargo').update(cargo.toInsertJson()).eq('id', cargo.id);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('cargo').delete().eq('id', id);
  }

  @override
  Future<List<CargoModel>> fetchReturnCandidates({required String fromCountry}) async {
    // Cargo whose pickup country matches where the truck is about to
    // become free — the core "return cargo" query (brief §13).
    final rows = await _client
        .from('cargo')
        .select()
        .eq('status', 'new')
        .eq('pickup_country', fromCountry)
        .order('pickup_date', ascending: true);
    return (rows as List).map((r) => CargoModel.fromJson(r)).toList();
  }
}

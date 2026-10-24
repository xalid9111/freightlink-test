import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../models/cargo_model.dart';
import '../domain/cargo_categories.dart';
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
      // Switched off by the owner or past the loading date: not listed.
      final now = DateTime.now();
      return (rows as List).map((r) => CargoModel.fromJson(r)).where((c) => c.isListedOn(now)).toList();
    } on PostgrestException catch (e) {
      throw AppException(e.message, code: e.code);
    }
  }

  @override
  Future<List<CargoModel>> fetchByCategory({String? truckType, bool groupage = false, String? loadSize}) async {
    try {
      var query = _client.from('cargo').select().eq('status', 'new');
      // The code in any letter case and the other spellings typed under
      // "Digər" ("Tent", "soyuducu reff" …, owner 25.10.2026); the exact
      // rule is applied below (truckCategoryOf). Nothing stored changes.
      if (truckType != null) query = query.or(truckTypeOrFilter(truckType));
      if (groupage) query = query.eq('groupage', true);
      if (loadSize != null) query = query.eq('load_size', loadSize);
      final rows = await query.order('created_at', ascending: false);
      final now = DateTime.now();
      return (rows as List)
          .map((r) => CargoModel.fromJson(r))
          .where((c) => c.isListedOn(now))
          .where((c) => truckType == null || truckCategoryOf(c.truckType) == truckType)
          .toList();
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
    final row = await _withImage((image, images) => _withSize((size) => _withTerms((terms, choices) => _client
        .from('cargo')
        .insert(cargo.toInsertJson(withTerms: terms, withChoices: choices, withSize: size, withImage: image, withImages: images))
        .select()
        .single())));
    return CargoModel.fromJson(row);
  }

  @override
  Future<void> update(CargoModel cargo) async {
    await _withImage((image, images) => _withSize((size) => _withTerms((terms, choices) => _client
        .from('cargo')
        .update(cargo.toInsertJson(withTerms: terms, withChoices: choices, withSize: size, withImage: image, withImages: images))
        .eq('id', cargo.id))));
  }

  /// Pictures: the list needs 0060, the main picture 0058. Until they
  /// are run the load is saved with what the database has (only the main
  /// picture, or none).
  Future<T> _withImage<T>(Future<T> Function(bool image, bool images) run) async {
    try {
      return await run(true, true);
    } on PostgrestException catch (e) {
      if (isMissingImagesColumn(e.code, e.message)) {
        try {
          return await run(true, false);
        } on PostgrestException catch (e2) {
          if (!isMissingImageColumn(e2.code, e2.message)) rethrow;
          return run(false, false);
        }
      }
      if (!isMissingImageColumn(e.code, e.message)) rethrow;
      return run(false, false);
    }
  }

  /// Big / small and groupage need migration 0055; until it is run the
  /// load is saved without them.
  Future<T> _withSize<T>(Future<T> Function(bool size) run) async {
    try {
      return await run(true);
    } on PostgrestException catch (e) {
      if (!isMissingSizeColumn(e.code, e.message)) rethrow;
      return run(false);
    }
  }

  /// Payment terms need migrations 0046 / 0047. Until they are run, a
  /// save must not fail: the load is saved again without the columns the
  /// database does not have yet.
  Future<T> _withTerms<T>(Future<T> Function(bool terms, bool choices) run) async {
    try {
      return await run(true, true);
    } on PostgrestException catch (e) {
      if (isMissingChoiceColumn(e.code, e.message)) {
        try {
          return await run(true, false);
        } on PostgrestException catch (e2) {
          if (!isMissingTermsColumn(e2.code, e2.message)) rethrow;
          return run(false, false);
        }
      }
      if (!isMissingTermsColumn(e.code, e.message)) rethrow;
      return run(false, false);
    }
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
    final now = DateTime.now();
    return (rows as List).map((r) => CargoModel.fromJson(r)).where((c) => c.isListedOn(now)).toList();
  }
}

/// PostgREST "column not in the schema cache" (PGRST204) for one of the
/// 0046 columns, or Postgres "undefined column" (42703).
bool isMissingTermsColumn(String? code, String message) =>
    (code == 'PGRST204' || code == '42703') && CargoModel.termsColumns.any(message.contains);

/// Same for the 0055 columns.
bool isMissingSizeColumn(String? code, String message) =>
    (code == 'PGRST204' || code == '42703') && CargoModel.sizeColumns.any(message.contains);

/// Same for the 0060 picture list ("image_urls" — checked before
/// image_url, whose name it contains).
bool isMissingImagesColumn(String? code, String message) =>
    (code == 'PGRST204' || code == '42703') && CargoModel.imagesColumns.any(message.contains);

/// Same for the 0058 picture column.
bool isMissingImageColumn(String? code, String message) =>
    (code == 'PGRST204' || code == '42703') &&
    RegExp(r'image_url(?!s)').hasMatch(message);

/// Same for the 0047 columns.
bool isMissingChoiceColumn(String? code, String message) =>
    (code == 'PGRST204' || code == '42703') && CargoModel.choiceColumns.any(message.contains);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../core/constants/app_constants.dart';
import '../models/cargo_model.dart';
import '../models/shipment_model.dart';

/// Pairs a shipment with the cargo it's for, purely for display (the
/// Shipments screen needs the route/price, which live on `cargo`, not
/// `shipments`). Built with two queries (fetch shipments, then batch-
/// fetch the referenced cargo rows) rather than a Postgrest embedded
/// select — simpler and safer than guessing the exact FK-hint syntax
/// Postgrest would need for an unambiguous embed here, at the cost of
/// one extra round trip.
class ShipmentWithCargo {
  final ShipmentModel shipment;
  final CargoModel? cargo; // null only if the cargo row was somehow deleted
  const ShipmentWithCargo({required this.shipment, required this.cargo});
}

class ShipmentRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<ShipmentModel> createFromAcceptedOffer({
    required String cargoId,
    required String carrierId,
    required String acceptedOfferId,
    required double agreedPrice,
  }) async {
    final row = await _client.from('shipments').insert({
      'cargo_id': cargoId,
      'carrier_id': carrierId,
      'accepted_offer_id': acceptedOfferId,
      'agreed_price': agreedPrice,
    }).select().single();
    return ShipmentModel.fromJson(row);
  }

  /// Status-only update of the cargo row (cargo owner only — RLS policy
  /// cargo_owner_write, migration 0002). Used to take a cargo off the
  /// open marketplace (which lists status = 'new' only) once an offer is
  /// accepted, and to mirror the shipment reaching 'completed'.
  Future<void> setCargoStatus({required String cargoId, required String status}) async {
    assert(AppConstants.shipmentStatusFlow.contains(status), 'Unknown cargo status: $status');
    await _client.from('cargo').update({'status': status}).eq('id', cargoId);
  }

  Future<void> advanceStatus({required String shipmentId, required String newStatus, String? note}) async {
    assert(AppConstants.shipmentStatusFlow.contains(newStatus), 'Unknown shipment status: $newStatus');
    await _client.from('shipments').update({'status': newStatus}).eq('id', shipmentId);
    await _client.from('shipment_status').insert({
      'shipment_id': shipmentId,
      'status': newStatus,
      'note': note,
    });
  }

  Future<List<ShipmentModel>> fetchMine() async {
    final rows = await _client.from('shipments').select().order('created_at', ascending: false);
    return (rows as List).map((r) => ShipmentModel.fromJson(r)).toList();
  }

  Future<List<ShipmentWithCargo>> fetchMineWithCargo() async {
    final shipments = await fetchMine();
    if (shipments.isEmpty) return [];

    final cargoIds = shipments.map((s) => s.cargoId).toSet().toList();
    final cargoRows = await _client.from('cargo').select().inFilter('id', cargoIds);
    final cargoById = {
      for (final row in (cargoRows as List)) row['id'] as String: CargoModel.fromJson(row),
    };

    return shipments
        .map((s) => ShipmentWithCargo(shipment: s, cargo: cargoById[s.cargoId]))
        .toList();
  }
}

final shipmentRepositoryProvider = Provider<ShipmentRepository>((ref) => ShipmentRepository());

final myShipmentsProvider = FutureProvider<List<ShipmentWithCargo>>((ref) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(shipmentRepositoryProvider).fetchMineWithCargo();
});

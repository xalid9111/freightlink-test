import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../core/errors/app_exception.dart';
import '../models/offer_model.dart';

/// Not nested under features/ because offers are read/written from both
/// the cargo feature (owner accepting/rejecting) and a future carrier
/// feature (making the offer) — kept as a cross-feature repository per
/// the Phase 1 README's stated pattern.
///
/// One-active-offer rule (Phase 2 addendum, migration 0004): a carrier
/// may have at most one PENDING offer per cargo. This is enforced by a
/// partial unique index in Postgres — `submit()` below relies on that
/// index for correctness (including under concurrent requests) and
/// only translates the resulting database error into something the UI
/// can show; it does not re-implement the rule with a check-then-insert,
/// which would not be safe against a race.
class OfferRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  Future<List<OfferModel>> fetchForCargo(String cargoId) async {
    final rows = await _client.from('offers').select().eq('cargo_id', cargoId).order('created_at');
    return (rows as List).map((r) => OfferModel.fromJson(r)).toList();
  }

  /// All offers (any status) a carrier has ever made on a cargo —
  /// used by the UI to find "the" pending offer to update/withdraw,
  /// and to show offer history.
  Future<List<OfferModel>> fetchHistory({required String cargoId, required String carrierId}) async {
    final rows = await _client
        .from('offers')
        .select()
        .eq('cargo_id', cargoId)
        .eq('carrier_id', carrierId)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => OfferModel.fromJson(r)).toList();
  }

  /// Creates a new offer. If the carrier already has a pending offer on
  /// this cargo, the database's partial unique index
  /// (idx_offers_one_pending_per_carrier_cargo) rejects the insert with
  /// a unique_violation (Postgres code 23505) — caught here and turned
  /// into a clear AppException instead of a raw Postgrest error.
  Future<OfferModel> submit(OfferModel offer) async {
    try {
      final row = await _client.from('offers').insert(offer.toInsertJson()).select().single();
      return OfferModel.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const AppException(
          'Bu yük üçün artıq gözləyən təklifiniz var. Yeni təklif göndərmək '
          'əvəzinə mövcud təklifi yeniləyin və ya geri çəkin.',
          code: 'duplicate_pending_offer',
        );
      }
      throw AppException(e.message, code: e.code);
    }
  }

  /// Updates the price/message of the carrier's existing PENDING offer
  /// in place (does not create a new row) — this is what the UI should
  /// call instead of submit() when a pending offer already exists.
  Future<OfferModel> updatePendingOffer({
    required String offerId,
    required double newOfferedPrice,
    String? newMessage,
  }) async {
    final row = await _client
        .from('offers')
        .update({'offered_price': newOfferedPrice, 'message': newMessage})
        .eq('id', offerId)
        .eq('status', 'pending') // guards against updating a since-resolved offer
        .select()
        .single();
    return OfferModel.fromJson(row);
  }

  /// Cargo owner accepts/rejects/counters. Moving a row OUT of
  /// 'pending' is exactly what frees the carrier to submit again later.
  /// After the cargo owner accepts one offer, every OTHER still-pending
  /// offer on that cargo is closed as rejected, so competing carriers
  /// see a final answer instead of waiting forever. Allowed by RLS
  /// policy offers_owner_respond (migration 0002).
  Future<void> rejectOtherPending({required String cargoId, required String acceptedOfferId}) async {
    await _client
        .from('offers')
        .update({'status': 'rejected'})
        .eq('cargo_id', cargoId)
        .eq('status', 'pending')
        .neq('id', acceptedOfferId);
  }

  Future<void> respond({required String offerId, required String status}) async {
    assert(['accepted', 'rejected', 'countered'].contains(status));
    await _client.from('offers').update({'status': status}).eq('id', offerId);
  }

  /// Carrier withdraws their own pending offer. Kept as its own method
  /// name (rather than overloading respond()) since RLS scopes this to
  /// the offering carrier, not the cargo owner.
  Future<void> withdraw(String offerId) async {
    await _client.from('offers').update({'status': 'cancelled'}).eq('id', offerId).eq('status', 'pending');
  }

  /// Optional background job (Phase 12/17): sweep offers whose implicit
  /// validity window has passed and mark them 'expired' rather than
  /// leaving stale 'pending' rows blocking resubmission forever.
  Future<void> markExpired(String offerId) async {
    await _client.from('offers').update({'status': 'expired'}).eq('id', offerId).eq('status', 'pending');
  }
}

final offerRepositoryProvider = Provider<OfferRepository>((ref) => OfferRepository());

/// All offers on one cargo (cargo owner's view — RLS already scopes
/// this to either "cargo I own" or "offers I made", so a carrier
/// calling this for someone else's cargo just gets their own offer,
/// not everyone's).
final offersForCargoProvider = FutureProvider.family<List<OfferModel>, String>((ref, cargoId) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(offerRepositoryProvider).fetchForCargo(cargoId);
});

/// The signed-in carrier's own offer history on one cargo — used to
/// find "the" pending offer to show as editable, vs. past
/// rejected/withdrawn ones shown as read-only history.
class CarrierCargoKey extends Equatable {
  final String cargoId;
  final String carrierId;
  const CarrierCargoKey(this.cargoId, this.carrierId);

  @override
  List<Object?> get props => [cargoId, carrierId];
}

final myOfferHistoryProvider = FutureProvider.family<List<OfferModel>, CarrierCargoKey>((ref, key) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(offerRepositoryProvider).fetchHistory(cargoId: key.cargoId, carrierId: key.carrierId);
});

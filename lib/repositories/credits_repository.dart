import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../core/errors/app_exception.dart';

/// Contact-credit wallet access (see supabase/migrations/0006_monetization.sql).
/// Balances are never written from here — the only mutation path is
/// the unlock_contact() database function (SECURITY DEFINER), called
/// via unlockContact() below. This repository only ever reads, or asks
/// the database to do the one specific, atomic, server-validated thing.
class CreditsRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Null if the signed-in user has no carrier profile (e.g. a cargo
  /// owner) or no wallet row exists yet — callers should treat null as
  /// "don't show a balance", not as zero.
  Future<int?> fetchMyBalance() async {
    final carrierId = await _myCarrierId();
    if (carrierId == null) return null;
    final row = await _client
        .from('credit_wallets')
        .select('balance')
        .eq('carrier_id', carrierId)
        .maybeSingle();
    return row == null ? null : row['balance'] as int;
  }

  /// Spends one credit to unlock a cargo's contact details, via the
  /// unlock_contact(p_cargo_id) Postgres function — see that function
  /// for why this must happen server-side (atomicity under concurrent
  /// taps, and a client can't be trusted to decrement its own balance
  /// honestly). Returns the new balance. Throws AppException(code:
  /// 'insufficient_credits') if the carrier has none left — the UI is
  /// expected to route that into a "buy credits" prompt once a payment
  /// provider exists (see migration 0006's PAYMENT INTEGRATION POINT).
  Future<int> unlockContact(String cargoId) async {
    try {
      final rows = await _client.rpc('unlock_contact', params: {'p_cargo_id': cargoId});
      final row = (rows as List).first as Map<String, dynamic>;
      return row['new_balance'] as int;
    } on PostgrestException catch (e) {
      if (e.message.contains('insufficient_credits')) {
        throw const AppException(
          'Kifayət qədər kreditiniz yoxdur.',
          code: 'insufficient_credits',
        );
      }
      throw AppException(e.message, code: e.code);
    }
  }

  Future<String?> _myCarrierId() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client.from('carriers').select('id').eq('user_id', uid).maybeSingle();
    return row?['id'] as String?;
  }

  /// Has the signed-in carrier already unlocked this cargo's contact
  /// details? Checked before showing the "spend a credit" button, so a
  /// carrier who already paid never sees it again for the same cargo.
  Future<bool> isUnlocked(String cargoId) async {
    final carrierId = await _myCarrierId();
    if (carrierId == null) return false;
    final row = await _client
        .from('contact_unlocks')
        .select('id')
        .eq('carrier_id', carrierId)
        .eq('cargo_id', cargoId)
        .maybeSingle();
    return row != null;
  }

  /// Contact details of the poster of [cargoId], as shown on the load's
  /// detail page. Since migration 0019 public.users is no longer readable
  /// for other users; the server function get_cargo_contact() returns the
  /// poster's name/phone/e-mail only for a load the caller can see.
  /// Before 0019 is applied (RPC missing, PGRST202) the old users read is
  /// used, so this build can be deployed first.
  Future<Map<String, String?>> fetchCargoContact(String cargoId, String ownerId) async {
    Map<String, dynamic>? row;
    try {
      final res = await _client.rpc('get_cargo_contact', params: {'p_cargo': cargoId});
      row = res is Map ? Map<String, dynamic>.from(res) : null;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      row = await _client.from('users').select('full_name, phone, email').eq('id', ownerId).maybeSingle();
    }
    return {
      'full_name': row?['full_name'] as String?,
      'phone': row?['phone'] as String?,
      'email': row?['email'] as String?,
    };
  }
}

final creditsRepositoryProvider = Provider<CreditsRepository>((ref) => CreditsRepository());

/// FutureProvider (not a FutureBuilder re-created on every widget
/// rebuild — an easy-to-introduce anti-pattern) so the balance is
/// fetched once and cached until the provider is invalidated, e.g.
/// after unlockContact() succeeds.
final creditsBalanceProvider = FutureProvider<int?>((ref) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(creditsRepositoryProvider).fetchMyBalance();
});

final contactUnlockedProvider = FutureProvider.family<bool, String>((ref, cargoId) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(creditsRepositoryProvider).isUnlocked(cargoId);
});

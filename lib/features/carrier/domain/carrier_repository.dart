/// Small, focused contract: just enough carrier-identity resolution
/// for the cargo/offer/credits screens to know "am I a carrier, and
/// which carrier row is mine". Full carrier profile/truck management
/// (brief §6's "Add drivers", "Add trucks") is a later phase.
abstract class CarrierRepository {
  /// Null if the signed-in user has no carrier profile (e.g. they're a
  /// cargo owner, or — for any account created before migration 0007 —
  /// the auto-create trigger never ran for them; see that migration's
  /// manual backfill note).
  Future<String?> fetchMyCarrierId();

  /// Resolves a carriers.id back to the underlying auth/public.users id
  /// — needed wherever code has a carrier_id (offers, trucks) but needs
  /// the user_id instead (e.g. starting a conversation, which is keyed
  /// by user id on both sides — see public.conversations).
  Future<String?> fetchUserIdForCarrier(String carrierId);
}

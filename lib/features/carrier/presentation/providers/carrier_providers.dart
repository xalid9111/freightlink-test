import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/carrier_repository_impl.dart';
import '../../domain/carrier_repository.dart';

final carrierRepositoryProvider = Provider<CarrierRepository>((ref) => CarrierRepositoryImpl());

/// Watched wherever a screen needs to know "is the signed-in user a
/// carrier, and what's their carrier row id" — e.g. deciding whether to
/// show the offer-submission form vs. the offers-received list on
/// cargo detail. Re-evaluates when the signed-in account changes (via
/// currentUserIdProvider).
final myCarrierIdProvider = FutureProvider<String?>((ref) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(carrierRepositoryProvider).fetchMyCarrierId();
});

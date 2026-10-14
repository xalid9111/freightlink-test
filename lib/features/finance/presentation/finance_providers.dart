import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';

/// Server says whether the signed-in user is the finance owner (0037).
final isFinanceAdminProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return ref.watch(financeRepositoryProvider).isFinanceAdmin();
});

/// Card checkout for this user: LIVE → everybody, TEST → finance owner only.
final checkoutAvailabilityProvider = FutureProvider.autoDispose<CheckoutAvailability>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const CheckoutAvailability(available: false, mode: 'off');
  return ref.watch(financeRepositoryProvider).checkoutAvailability();
});

final financeSummaryProvider = FutureProvider.autoDispose.family<FinanceSummary, String>(
    (ref, mode) => ref.watch(financeRepositoryProvider).summary(mode));

final payoutAccountsProvider = FutureProvider.autoDispose<List<PayoutAccount>>((ref) => ref.watch(financeRepositoryProvider).accounts());

final paymentSettingsProvider = FutureProvider.autoDispose<PaymentSettingsData>((ref) => ref.watch(financeRepositoryProvider).settings());

class PaymentFilter {
  final String mode;
  final String? status;
  final DateTime? from, to;
  final String search;
  const PaymentFilter({required this.mode, this.status, this.from, this.to, this.search = ''});

  @override
  bool operator ==(Object other) =>
      other is PaymentFilter && other.mode == mode && other.status == status && other.from == from && other.to == to && other.search == search;
  @override
  int get hashCode => Object.hash(mode, status, from, to, search);
}

final financePaymentsProvider = FutureProvider.autoDispose.family<List<FinancePayment>, PaymentFilter>((ref, f) =>
    ref.watch(financeRepositoryProvider).payments(mode: f.mode, status: f.status, from: f.from, to: f.to, search: f.search));

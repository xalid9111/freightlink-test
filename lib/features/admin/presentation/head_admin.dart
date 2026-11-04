import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../finance/presentation/finance_providers.dart';
import '../data/admin_repository.dart';

/// "Baş admin" (owner, 04.11.2026): the owner's own admin account. No new
/// role: an admin (users.role) who is either the finance owner (0037,
/// server is_finance_admin()) or the Founder (0045, server founder_ids()).
/// Only he sees and opens Admin Panel and "Maliyyə və ödənişlər"; other
/// administrators see neither and a direct /admin link shows "Giriş
/// qadağandır". The server checks (is_admin(), _require_finance_admin())
/// are unchanged.
final isHeadAdminProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return false;
  final user = await ref.watch(authStateProvider.future);
  if (user == null || user.role != AppConstants.roleAdmin) return false;
  try {
    if (await ref.watch(isFinanceAdminProvider.future)) return true;
  } catch (_) {}
  try {
    return (await ref.watch(adminRepositoryProvider).founderIds()).contains(uid);
  } catch (_) {
    return false;
  }
});

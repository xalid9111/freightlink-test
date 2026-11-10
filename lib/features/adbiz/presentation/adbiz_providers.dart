import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';

/// Who I am in UTEP Reklam. null = the module is off for me (or SQL 0110 is
/// not run yet): Profil shows no Reklam entry at all.
final adbizMeProvider = FutureProvider<AdbizMe?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  try {
    return await ref.watch(adbizRepositoryProvider).me();
  } catch (_) {
    return null;
  }
});

/// Live: one person's days (newest first).
final adbizDaysProvider = StreamProvider.autoDispose.family<List<AdbizDay>, String>(
    (ref, userId) => ref.watch(adbizRepositoryProvider).watchDays(userId));

/// Live: one day's jobs (oldest first) — the same on every device.
final adbizEntriesProvider = StreamProvider.autoDispose.family<List<AdbizEntry>, String>(
    (ref, dayId) => ref.watch(adbizRepositoryProvider).watchEntries(dayId));

final adbizCompaniesProvider = FutureProvider.autoDispose<List<AdbizCompany>>(
    (ref) => ref.watch(adbizRepositoryProvider).companies());

typedef AdbizPeriodKey = ({String companyId, AdbizPeriod period, DateTime date});

final adbizReportProvider = FutureProvider.autoDispose.family<AdbizReport, AdbizPeriodKey>((ref, k) {
  final (from, to) = periodRange(k.period, k.date);
  return ref.watch(adbizRepositoryProvider).report(k.companyId, from, to);
});

final adbizExpensesProvider = FutureProvider.autoDispose.family<List<AdbizExpense>, AdbizPeriodKey>((ref, k) {
  final (from, to) = periodRange(k.period, k.date);
  return ref.watch(adbizRepositoryProvider).expenses(k.companyId, from, to);
});

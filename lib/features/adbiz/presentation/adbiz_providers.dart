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

/// Live: one day's expenses (rasxod). Before SQL 0111 there is no day_id:
/// the day simply has no expenses.
final adbizDayExpensesProvider = StreamProvider.autoDispose.family<List<AdbizExpense>, String>((ref, dayId) async* {
  try {
    yield* ref.watch(adbizRepositoryProvider).watchDayExpenses(dayId);
  } catch (_) {
    yield const <AdbizExpense>[];
  }
});

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

/// One company (the worker reads only his own; the owner his; the Baş admin
/// any) — its target switch and the owner's words (0113). null = unknown.
final adbizCompanyProvider = Provider.autoDispose.family<AdbizCompany?, String>((ref, id) =>
    (ref.watch(adbizCompaniesProvider).valueOrNull ?? const <AdbizCompany>[]).where((c) => c.id == id).firstOrNull);

/// The owner's task for one worker (0113); null = none / not readable.
final adbizMemberTaskProvider = FutureProvider.autoDispose.family<String?, String>((ref, userId) async {
  try {
    return await ref.watch(adbizRepositoryProvider).memberTaskOf(userId);
  } catch (_) {
    return null;
  }
});

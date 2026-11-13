import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/live_resync.dart';
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

/// How often a live list is read again from the server, whatever realtime
/// says (owner, 13.11.2026: a job saved on the server did not show because
/// the realtime message was late / lost). A device's own writes re-read at
/// once (adbizResync); this catches the other devices' changes.
const kAdbizResyncEvery = Duration(seconds: 20);

/// A live list (see core/realtime/live_resync.dart).
Stream<List<T>> adbizLive<T>(Ref ref, Stream<List<T>> Function() live, Future<List<T>> Function() read,
        {Duration every = kAdbizResyncEvery}) =>
    liveWithResync(ref, live, read, every: every);

/// Live: one person's days (newest first).
final adbizDaysProvider = StreamProvider.autoDispose.family<List<AdbizDay>, String>((ref, userId) {
  final repo = ref.watch(adbizRepositoryProvider);
  return adbizLive(ref, () => repo.watchDays(userId), () => repo.days(userId));
});

/// Live: one day's jobs (oldest first) — the same on every device.
final adbizEntriesProvider = StreamProvider.autoDispose.family<List<AdbizEntry>, String>((ref, dayId) {
  final repo = ref.watch(adbizRepositoryProvider);
  return adbizLive(ref, () => repo.watchEntries(dayId), () => repo.entries(dayId));
});

/// Live: one day's expenses (rasxod). Before SQL 0111 there is no day_id:
/// the day simply has no expenses.
final adbizDayExpensesProvider = StreamProvider.autoDispose.family<List<AdbizExpense>, String>((ref, dayId) {
  final repo = ref.watch(adbizRepositoryProvider);
  return adbizLive(ref, () => repo.watchDayExpenses(dayId), () async {
    try {
      return await repo.dayExpenses(dayId);
    } catch (_) {
      return const <AdbizExpense>[];
    }
  });
});

/// After a write on this device: read the day again at once (never wait for
/// realtime to show what was just saved).
void adbizResync(WidgetRef ref, AdbizDay day) {
  ref.invalidate(adbizEntriesProvider(day.id));
  ref.invalidate(adbizDayExpensesProvider(day.id));
  ref.invalidate(adbizDaysProvider(day.userId));
}

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

/// The month / year cards of a company's year (0115); an error = not ready.
final adbizPeriodsProvider = FutureProvider.autoDispose.family<AdbizPeriods, ({String companyId, int year})>(
    (ref, k) => ref.watch(adbizRepositoryProvider).periods(k.companyId, k.year));

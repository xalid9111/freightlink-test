import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../data/fleet_repository.dart';
import '../domain/fleet.dart';

final fleetRepositoryProvider = Provider<FleetRepository>((ref) => FleetRepository());

/// Everything "Maşınlarım" shows, read together (one place to refresh).
class FleetData {
  final List<FleetTruck> trucks;
  final List<FleetJob> jobs;
  final List<FleetExpense> expenses;
  const FleetData({this.trucks = const [], this.jobs = const [], this.expenses = const []});

  List<FleetJob> jobsOf(String truckId) => [
        for (final j in jobs)
          if (j.truckId == truckId) j
      ];
  List<FleetExpense> expensesOf(String truckId) => [
        for (final e in expenses)
          if (e.truckId == truckId) e
      ];
  FleetTruck? truck(String id) => trucks.where((t) => t.id == id).firstOrNull;

  /// The trucks I own (the driver's trucks are listed apart).
  List<FleetTruck> owned(String? uid) => [
        for (final t in trucks)
          if (t.isOwner(uid)) t
      ];
  List<FleetTruck> driven(String? uid) => [
        for (final t in trucks)
          if (!t.isOwner(uid) && t.driverId == uid) t
      ];
}

final fleetProvider = FutureProvider<FleetData>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const FleetData();
  final repo = ref.watch(fleetRepositoryProvider);
  final r = await Future.wait([repo.trucks(), repo.jobs(), repo.expenses()]);
  return FleetData(trucks: r[0] as List<FleetTruck>, jobs: r[1] as List<FleetJob>, expenses: r[2] as List<FleetExpense>);
});

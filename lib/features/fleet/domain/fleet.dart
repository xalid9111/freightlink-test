// "Maşınlarım" (owner, 20.11.2026, SQL 0130): a carrier's own trucks, their
// jobs and expenses. Profit = the jobs' agreed prices − the APPROVED
// expenses, per truck and per currency (never converted: AZN, USD, EUR, RUB
// and TRY stand apart). A driver's expense counts only after the owner
// approves it ("Təsdiq gözləyir" until then).

/// The currencies a job / an expense may use (owner, 20.11.2026).
const kFleetCurrencies = ['AZN', 'USD', 'EUR', 'RUB', 'TRY'];

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

class FleetTruck {
  final String id, ownerId, name;
  final String? plate, driverName, driverId;

  /// A registered driver asked and not answered yet (0131).
  final String? pendingDriverId;
  const FleetTruck(
      {required this.id, required this.ownerId, required this.name, this.plate, this.driverName, this.driverId, this.pendingDriverId});

  factory FleetTruck.fromJson(Map<String, dynamic> j) => FleetTruck(
        id: '${j['id']}',
        ownerId: '${j['owner_id']}',
        name: '${j['name'] ?? ''}',
        plate: j['plate'] as String?,
        driverName: j['driver_name'] as String?,
        driverId: j['driver_id'] as String?,
        pendingDriverId: j['pending_driver_id'] as String?,
      );

  /// "Sürücü təsdiqi gözləyir" (0131).
  bool get driverWaiting => pendingDriverId != null && driverId != pendingDriverId;

  bool isOwner(String? uid) => uid != null && uid == ownerId;
}

class FleetJob {
  final String id, truckId;
  final DateTime startAt;
  final String? from, to, note;
  final double? price; // null for a driver (he never sees prices)
  final String currency;
  final String status; // planned · active · done · cancelled
  const FleetJob({
    required this.id,
    required this.truckId,
    required this.startAt,
    this.from,
    this.to,
    this.note,
    this.price,
    this.currency = 'AZN',
    this.status = 'planned',
  });

  factory FleetJob.fromJson(Map<String, dynamic> j) => FleetJob(
        id: '${j['id']}',
        truckId: '${j['truck_id']}',
        startAt: _date(j['start_at'])?.toLocal() ?? DateTime.now(),
        from: j['from_place'] as String?,
        to: j['to_place'] as String?,
        note: j['note'] as String?,
        price: j['price'] == null ? null : _num(j['price']),
        currency: '${j['currency'] ?? 'AZN'}',
        status: '${j['status'] ?? 'planned'}',
      );

  /// Running now: started (by its status or by its time) and not finished.
  bool runningAt(DateTime now) => status == 'active' || (status == 'planned' && !startAt.isAfter(now));
  bool get open => status == 'planned' || status == 'active';

  /// "Bakı → Gəncə".
  String get route => [from, to].where((v) => (v ?? '').trim().isNotEmpty).join(' → ');
}

class FleetExpense {
  final String id, truckId, name, currency, status, createdBy;
  final double amount;
  final DateTime? createdAt;
  const FleetExpense({
    required this.id,
    required this.truckId,
    required this.name,
    required this.amount,
    this.currency = 'AZN',
    this.status = 'approved',
    this.createdBy = '',
    this.createdAt,
  });

  factory FleetExpense.fromJson(Map<String, dynamic> j) => FleetExpense(
        id: '${j['id']}',
        truckId: '${j['truck_id']}',
        name: '${j['name'] ?? ''}',
        amount: _num(j['amount']),
        currency: '${j['currency'] ?? 'AZN'}',
        status: '${j['status'] ?? 'approved'}',
        createdBy: '${j['created_by'] ?? ''}',
        createdAt: _date(j['created_at'])?.toLocal(),
      );

  bool get pending => status == 'pending';
  bool get approved => status == 'approved';
}

/// Sums per currency, in the order of [kFleetCurrencies] (only the ones used).
Map<String, double> sumByCurrency(Iterable<(String, double)> items) {
  final out = <String, double>{};
  for (final (c, v) in items) {
    out[c] = (out[c] ?? 0) + v;
  }
  return {
    for (final c in [...kFleetCurrencies, ...out.keys.where((k) => !kFleetCurrencies.contains(k))])
      if (out.containsKey(c)) c: out[c]!,
  };
}

/// The agreed prices of the jobs that count (not cancelled).
Map<String, double> fleetIncome(Iterable<FleetJob> jobs) => sumByCurrency([
      for (final j in jobs)
        if (j.status != 'cancelled' && j.price != null) (j.currency, j.price!)
    ]);

/// Only approved expenses count (owner, 20.11.2026).
Map<String, double> fleetSpent(Iterable<FleetExpense> expenses) => sumByCurrency([
      for (final e in expenses)
        if (e.approved) (e.currency, e.amount)
    ]);

/// A driver's expenses still waiting for the owner (not counted yet).
Map<String, double> fleetWaiting(Iterable<FleetExpense> expenses) => sumByCurrency([
      for (final e in expenses)
        if (e.pending) (e.currency, e.amount)
    ]);

/// Profit per currency = income − approved expenses.
Map<String, double> fleetProfit(Iterable<FleetJob> jobs, Iterable<FleetExpense> expenses) {
  final income = fleetIncome(jobs);
  final spent = fleetSpent(expenses);
  return sumByCurrency([
    for (final e in income.entries) (e.key, e.value),
    for (final e in spent.entries) (e.key, -e.value),
  ]);
}

/// A truck is "İşdədir" while one of its jobs runs, else "Boşdur".
bool fleetTruckBusy(String truckId, Iterable<FleetJob> jobs, DateTime now) => jobs.any((j) => j.truckId == truckId && j.runningAt(now));

/// The job a busy truck is on (the latest started one).
FleetJob? fleetCurrentJob(String truckId, Iterable<FleetJob> jobs, DateTime now) {
  final running = [
    for (final j in jobs)
      if (j.truckId == truckId && j.runningAt(now)) j
  ]..sort((a, b) => b.startAt.compareTo(a.startAt));
  return running.isEmpty ? null : running.first;
}

/// Open jobs from today on, soonest first ("Yaxın işlər", "Bugünkü plan").
List<FleetJob> fleetUpcoming(Iterable<FleetJob> jobs, DateTime now) {
  final dayStart = DateTime(now.year, now.month, now.day);
  return [
    for (final j in jobs)
      if (j.open && !j.startAt.isBefore(dayStart)) j
  ]..sort((a, b) => a.startAt.compareTo(b.startAt));
}

/// Today's jobs (local day), soonest first.
List<FleetJob> fleetToday(Iterable<FleetJob> jobs, DateTime now) => [
      for (final j in fleetUpcoming(jobs, now))
        if (j.startAt.year == now.year && j.startAt.month == now.month && j.startAt.day == now.day) j
    ];

/// "4 500", "5 500.5" — spaces between thousands, no ".00".
String fleetAmount(double v) {
  final neg = v < 0;
  final a = v.abs();
  final whole = a.truncate();
  final frac = ((a - whole) * 100).round();
  final digits = '$whole';
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  var s = b.toString();
  if (frac > 0) s += frac % 10 == 0 ? '.${frac ~/ 10}' : '.${frac.toString().padLeft(2, '0')}';
  return neg ? '-$s' : s;
}

/// "14:30".
String fleetTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A registered account offered as the driver (0131): name, picture, the
/// blue badge — never a phone or an e-mail.
class FleetPerson {
  final String id, name;
  final String? avatarUrl;
  final bool verified;
  const FleetPerson({required this.id, required this.name, this.avatarUrl, this.verified = false});

  factory FleetPerson.fromJson(Map<String, dynamic> j) => FleetPerson(
        id: '${j['id']}',
        name: '${j['full_name'] ?? ''}'.trim(),
        avatarUrl: j['avatar_url'] as String?,
        verified: j['is_verified'] == true,
      );

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => String.fromCharCode(p.runes.first).toUpperCase()).join();
  }
}

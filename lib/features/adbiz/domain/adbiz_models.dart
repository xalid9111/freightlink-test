// UTEP Reklam — ad business management (owner, 10.11.2026, SQL 0110).
// Plain data + the small sums the screens show; the server is the only
// source of the numbers (days, jobs, targets, expenses).

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _dn(Object? v) => v == null ? null : _d(v);
DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
DateTime _date(Object? v) {
  final p = DateTime.tryParse('$v');
  return p == null ? DateTime(2000) : DateTime(p.year, p.month, p.day);
}

/// What Profil shows (adbiz_me): null = the module is off for this account.
class AdbizMe {
  final bool chief;
  final String? companyId, companyName, role;
  final bool managesStaff;
  final double dailyTarget;
  const AdbizMe({
    this.chief = false,
    this.companyId,
    this.companyName,
    this.role,
    this.managesStaff = false,
    this.dailyTarget = 0,
  });

  factory AdbizMe.fromJson(Map<String, dynamic> j) => AdbizMe(
        chief: j['chief'] == true,
        companyId: j['company_id'] as String?,
        companyName: j['company_name'] as String?,
        role: j['role'] as String?,
        managesStaff: j['manages_staff'] == true,
        dailyTarget: _d(j['daily_target']),
      );

  bool get isMember => companyId != null;
  bool get isOwner => isMember && role == 'owner';
  bool get isWorker => isMember && role == 'worker';
}

class AdbizCompany {
  final String id, name;
  final double dailyTarget;
  final bool ownerManagesStaff, isActive;
  const AdbizCompany({
    required this.id,
    required this.name,
    this.dailyTarget = 0,
    this.ownerManagesStaff = false,
    this.isActive = true,
  });

  factory AdbizCompany.fromJson(Map<String, dynamic> j) => AdbizCompany(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        dailyTarget: _d(j['daily_target']),
        ownerManagesStaff: j['owner_manages_staff'] == true,
        isActive: j['is_active'] != false,
      );
}

class AdbizDay {
  final String id, companyId, userId, status;
  final DateTime workDate;
  final double target;
  final DateTime? openedAt, closedAt;
  const AdbizDay({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.workDate,
    this.status = 'open',
    this.target = 0,
    this.openedAt,
    this.closedAt,
  });

  factory AdbizDay.fromJson(Map<String, dynamic> j) => AdbizDay(
        id: j['id'] as String,
        companyId: j['company_id'] as String,
        userId: j['user_id'] as String,
        workDate: _date(j['work_date']),
        status: (j['status'] as String?) ?? 'open',
        target: _d(j['target']),
        openedAt: _t(j['opened_at']),
        closedAt: _t(j['closed_at']),
      );

  bool get isOpen => status == 'open';
}

class AdbizEntry {
  final String id, dayId, title;
  final double amount;
  final DateTime? createdAt;
  const AdbizEntry({required this.id, required this.dayId, required this.title, required this.amount, this.createdAt});

  factory AdbizEntry.fromJson(Map<String, dynamic> j) => AdbizEntry(
        id: j['id'] as String,
        dayId: j['day_id'] as String,
        title: (j['title'] as String?) ?? '',
        amount: _d(j['amount']),
        createdAt: _t(j['created_at']),
      );
}

class AdbizExpense {
  final String id, title;
  final DateTime spentOn;
  final double amount;
  const AdbizExpense({required this.id, required this.title, required this.spentOn, required this.amount});

  factory AdbizExpense.fromJson(Map<String, dynamic> j) => AdbizExpense(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        spentOn: _date(j['spent_on']),
        amount: _d(j['amount']),
      );
}

class AdbizWorkerSum {
  final String userId, name, role;
  final bool isActive;
  final double total;
  final int days;
  final double? personalTarget;
  const AdbizWorkerSum({
    required this.userId,
    required this.name,
    required this.role,
    this.isActive = true,
    this.total = 0,
    this.days = 0,
    this.personalTarget,
  });

  factory AdbizWorkerSum.fromJson(Map<String, dynamic> j) => AdbizWorkerSum(
        userId: j['user_id'] as String,
        name: (j['name'] as String?) ?? '',
        role: (j['role'] as String?) ?? 'worker',
        isActive: j['is_active'] != false,
        total: _d(j['total']),
        days: (j['days'] as num?)?.toInt() ?? 0,
        personalTarget: _dn(j['personal_target']),
      );
}

class AdbizReport {
  final double income, expenses, net;
  final int daysOpen, daysClosed;
  final List<AdbizWorkerSum> workers;
  final List<(DateTime, double)> byDay;
  const AdbizReport({
    this.income = 0,
    this.expenses = 0,
    this.net = 0,
    this.daysOpen = 0,
    this.daysClosed = 0,
    this.workers = const [],
    this.byDay = const [],
  });

  factory AdbizReport.fromJson(Map<String, dynamic> j) => AdbizReport(
        income: _d(j['income']),
        expenses: _d(j['expenses']),
        net: _d(j['net']),
        daysOpen: (j['days_open'] as num?)?.toInt() ?? 0,
        daysClosed: (j['days_closed'] as num?)?.toInt() ?? 0,
        workers: [
          for (final w in (j['workers'] as List? ?? const [])) AdbizWorkerSum.fromJson(Map<String, dynamic>.from(w as Map)),
        ],
        byDay: [
          for (final d in (j['by_day'] as List? ?? const []))
            (_date((d as Map)['date']), _d(d['income'])),
        ],
      );
}

class AdbizUserHit {
  final String id, name;
  final String? email, phone, companyId, companyName, role;
  final bool? isActive;
  const AdbizUserHit({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.companyId,
    this.companyName,
    this.role,
    this.isActive,
  });

  factory AdbizUserHit.fromJson(Map<String, dynamic> j) => AdbizUserHit(
        id: j['id'] as String,
        name: (j['full_name'] as String?) ?? '',
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        companyId: j['company_id'] as String?,
        companyName: j['company_name'] as String?,
        role: j['role'] as String?,
        isActive: j['is_active'] as bool?,
      );
}

/// The day's numbers (owner, 10.11.2026): collected = the sum of the jobs,
/// remaining never below 0, the bar full at the target — the target only
/// motivates, collecting more is fine (no upper limit), percent shows it.
class DayProgress {
  final double collected, target;
  const DayProgress(this.collected, this.target);

  factory DayProgress.of(Iterable<AdbizEntry> entries, double target) =>
      DayProgress(entries.fold<double>(0, (s, e) => s + e.amount), target);

  double get remaining => (target - collected) > 0 ? target - collected : 0;
  double get bar => target <= 0 ? (collected > 0 ? 1 : 0) : (collected / target).clamp(0, 1).toDouble();
  int get percent => target <= 0 ? 0 : (collected / target * 100).round();
  bool get reached => target > 0 && collected >= target;
}

/// Day / month / year of a date — the owner's report periods.
enum AdbizPeriod { day, month, year }

(DateTime, DateTime) periodRange(AdbizPeriod p, DateTime d) => switch (p) {
      AdbizPeriod.day => (DateTime(d.year, d.month, d.day), DateTime(d.year, d.month, d.day)),
      AdbizPeriod.month => (DateTime(d.year, d.month, 1), DateTime(d.year, d.month + 1, 0)),
      AdbizPeriod.year => (DateTime(d.year, 1, 1), DateTime(d.year, 12, 31)),
    };

/// The work day follows Baku (UTC+4, no summer time), like the server.
DateTime bakuToday([DateTime? now]) {
  final b = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 4));
  return DateTime(b.year, b.month, b.day);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A typed amount: "20", "20,5", "20.50", "20 AZN" → 20.5; null when not a
/// positive number.
double? parseAmount(String s) {
  final t = s.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll(',', '.');
  final v = double.tryParse(t);
  return v == null || v <= 0 ? null : (v * 100).roundToDouble() / 100;
}

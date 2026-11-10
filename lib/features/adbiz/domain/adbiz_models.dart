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

  /// The owner's words (0113): the caption shown instead of "Hədəfə qalan"
  /// and the task for every worker; null = none.
  final String? targetLabel, taskNote;

  /// The workers see the target, the bar and "Mənfi" (0113; on by default).
  final bool showTarget;

  /// SQL 0113 is run: the card tick, the words and the switch work.
  final bool v113;

  /// The owner's day-result messages (0114): below the target / at or over
  /// it; {qalan}, {gəlir}, {hədəf} become the day's numbers. null = the
  /// app's own words.
  final String? resultMissText, resultHitText;

  /// SQL 0114 is run: the result messages can be written.
  final bool v114;
  const AdbizCompany({
    required this.id,
    required this.name,
    this.dailyTarget = 0,
    this.ownerManagesStaff = false,
    this.isActive = true,
    this.targetLabel,
    this.taskNote,
    this.showTarget = true,
    this.v113 = false,
    this.resultMissText,
    this.resultHitText,
    this.v114 = false,
  });

  factory AdbizCompany.fromJson(Map<String, dynamic> j) => AdbizCompany(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        dailyTarget: _d(j['daily_target']),
        ownerManagesStaff: j['owner_manages_staff'] == true,
        isActive: j['is_active'] != false,
        targetLabel: _txt(j['target_label']),
        taskNote: _txt(j['task_note']),
        showTarget: j['show_target'] != false,
        v113: j.containsKey('show_target'),
        resultMissText: _txt(j['result_miss_text']),
        resultHitText: _txt(j['result_hit_text']),
        v114: j.containsKey('result_miss_text'),
      );
}

String? _txt(Object? v) {
  final t = '${v ?? ''}'.trim();
  return t.isEmpty ? null : t;
}

class AdbizDay {
  final String id, companyId, userId, status;
  final DateTime workDate;
  final double target;
  final DateTime? openedAt, closedAt;

  /// Who closed it; null on a closed day = closed automatically after 23:59
  /// (0112).
  final String? closedBy;
  const AdbizDay({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.workDate,
    this.status = 'open',
    this.target = 0,
    this.openedAt,
    this.closedAt,
    this.closedBy,
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
        closedBy: j['closed_by'] as String?,
      );

  bool get isOpen => status == 'open';

  /// Open for work on [today]: an open day of an earlier date counts as
  /// closed — every day ends at 23:59 Baku (owner, 10.11.2026, 0112).
  bool openOn(DateTime today) => isOpen && !workDate.isBefore(today);

  /// Closed by nobody = closed automatically after 23:59.
  bool closedAutomatically(DateTime today) => (!isOpen && closedBy == null) || (isOpen && workDate.isBefore(today));
}

class AdbizEntry {
  final String id, dayId, title;
  final double amount;
  final DateTime? createdAt;

  /// Paid by card (the tick, 0113); false = cash.
  final bool paidCard;
  const AdbizEntry({required this.id, required this.dayId, required this.title, required this.amount, this.createdAt, this.paidCard = false});

  factory AdbizEntry.fromJson(Map<String, dynamic> j) => AdbizEntry(
        id: j['id'] as String,
        dayId: j['day_id'] as String,
        title: (j['title'] as String?) ?? '',
        amount: _d(j['amount']),
        createdAt: _t(j['created_at']),
        paidCard: j['paid_card'] == true,
      );
}

/// The money of the jobs paid by card.
double cardTotal(Iterable<AdbizEntry> entries) =>
    (entries.where((e) => e.paidCard).fold<double>(0, (s, e) => s + e.amount) * 100).roundToDouble() / 100;

class AdbizExpense {
  final String id, title;
  final DateTime spentOn;
  final double amount;

  /// A worker's day expense (rasxod, 0111): its day and worker; null = a
  /// company expense the owner wrote.
  final String? dayId, userId;
  final DateTime? createdAt;
  const AdbizExpense({
    required this.id,
    required this.title,
    required this.spentOn,
    required this.amount,
    this.dayId,
    this.userId,
    this.createdAt,
  });

  factory AdbizExpense.fromJson(Map<String, dynamic> j) => AdbizExpense(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        spentOn: _date(j['spent_on']),
        amount: _d(j['amount']),
        dayId: j['day_id'] as String?,
        userId: j['user_id'] as String?,
        createdAt: _t(j['created_at']),
      );
}

class AdbizWorkerSum {
  final String userId, name, role;
  final bool isActive;
  final double total, card;
  final int days;
  final double? personalTarget;

  /// The owner's task for this worker (0113).
  final String? taskNote;
  const AdbizWorkerSum({
    required this.userId,
    required this.name,
    required this.role,
    this.isActive = true,
    this.total = 0,
    this.card = 0,
    this.days = 0,
    this.personalTarget,
    this.taskNote,
  });

  factory AdbizWorkerSum.fromJson(Map<String, dynamic> j) => AdbizWorkerSum(
        userId: j['user_id'] as String,
        name: (j['name'] as String?) ?? '',
        role: (j['role'] as String?) ?? 'worker',
        isActive: j['is_active'] != false,
        total: _d(j['total']),
        card: _d(j['card']),
        taskNote: _txt(j['task_note']),
        days: (j['days'] as num?)?.toInt() ?? 0,
        personalTarget: _dn(j['personal_target']),
      );
}

class AdbizReport {
  final double income, expenses, net;

  /// Jobs paid by card / in cash (0113; before it everything counts as cash).
  final double card;
  double get cash => income - card;
  final int daysOpen, daysClosed;
  final List<AdbizWorkerSum> workers;
  final List<(DateTime, double)> byDay;
  const AdbizReport({
    this.income = 0,
    this.expenses = 0,
    this.net = 0,
    this.card = 0,
    this.daysOpen = 0,
    this.daysClosed = 0,
    this.workers = const [],
    this.byDay = const [],
  });

  factory AdbizReport.fromJson(Map<String, dynamic> j) => AdbizReport(
        income: _d(j['income']),
        expenses: _d(j['expenses']),
        net: _d(j['net']),
        card: _d(j['card']),
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

/// The day's numbers (owner, 10.11.2026): collected = the sum of the jobs;
/// spent = the day's expenses (rasxod, 0111); the day's money left (net) =
/// collected − spent; what is left to the target and the bar follow the
/// money left (120 − 30 = 90 → 145 to 235, 38.3 %). Remaining never below
/// 0; the target only motivates — more is fine (no upper limit).
class DayProgress {
  final double collected, target, spent;
  const DayProgress(this.collected, this.target, [this.spent = 0]);

  factory DayProgress.of(Iterable<AdbizEntry> entries, double target, [Iterable<AdbizExpense> expenses = const []]) =>
      DayProgress(
        entries.fold<double>(0, (s, e) => s + e.amount),
        target,
        expenses.fold<double>(0, (s, e) => s + e.amount),
      );

  double get net => _r2(collected - spent);
  double get remaining => (target - net) > 0 ? _r2(target - net) : 0;
  double get bar => target <= 0 ? (net > 0 ? 1 : 0) : (net / target).clamp(0, 1).toDouble();

  /// Percent of the target, one decimal (38.3); never below 0.
  double get percentExact => target <= 0 || net <= 0 ? 0 : (net / target * 1000).round() / 10;
  int get percent => percentExact.round();
  String get percentLabel {
    final v = percentExact;
    return v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';
  }

  bool get reached => target > 0 && net >= target;

  static double _r2(double v) => (v * 100).roundToDouble() / 100;
}

/// One month / year card (0115): the net income and the closed days'
/// minus / plus against their own targets.
class AdbizPeriodSum {
  final int key;
  final double net, gap;
  const AdbizPeriodSum(this.key, this.net, this.gap);

  factory AdbizPeriodSum.fromJson(Map<String, dynamic> j) =>
      AdbizPeriodSum((j['key'] as num).toInt(), _d(j['net']), _d(j['gap']));
}

/// The cards of one year: its 12 months and every year with work.
class AdbizPeriods {
  final List<AdbizPeriodSum> months, years;
  const AdbizPeriods({this.months = const [], this.years = const []});

  factory AdbizPeriods.fromJson(Map<String, dynamic> j) => AdbizPeriods(
        months: [for (final m in (j['months'] as List? ?? const [])) AdbizPeriodSum.fromJson(Map<String, dynamic>.from(m as Map))],
        years: [for (final y in (j['years'] as List? ?? const [])) AdbizPeriodSum.fromJson(Map<String, dynamic>.from(y as Map))],
      );
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

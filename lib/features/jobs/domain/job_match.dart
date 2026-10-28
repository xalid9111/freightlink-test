import '../../../core/constants/countries.dart';
import 'job_models.dart';

/// SmartMatch (owner, 26.10.2026): explainable, deterministic rules — no
/// paid AI. The percentage only informs: nothing is ever hidden because of
/// it, and a missing document never blocks anybody.
///
/// Each line of the comparison is one of:
///   * [CheckState.yes]     green ✓ — fits / has it;
///   * [CheckState.no]      red ✗ — does not fit / does not have it;
///   * [CheckState.unknown] neutral — not given (neither adds nor takes
///                          points: it is left out of the percentage);
///   * [CheckState.ready]   the driver does not have it yet but is ready
///                          to obtain it (counted as ✗ for the points).
/// [MatchCheck.canHelp]: the employer can help to obtain it (information).
enum CheckState { yes, no, unknown, ready }

/// What a line is about; [code] is the specialty / skill code for
/// [specialty] and [skill] lines.
enum CheckKind { specialty, skill, experience, age, place, city, countries, salary, schedule }

class MatchCheck {
  final CheckKind kind;
  final CheckState state;
  final String? code;
  final ReqLevel? level;
  final bool canHelp;
  final int weight;
  const MatchCheck(this.kind, this.state, {this.code, this.level, this.canHelp = false, required this.weight});

  /// Points earned for this line.
  int get earned => state == CheckState.yes ? weight : 0;
}

class JobMatch {
  final List<MatchCheck> checks;
  const JobMatch(this.checks);

  /// 0–100 over the lines that are known; null when nothing can be compared.
  int? get percent {
    var possible = 0, earned = 0;
    for (final c in checks) {
      if (c.state == CheckState.unknown) continue;
      possible += c.weight;
      earned += c.earned;
    }
    return possible == 0 ? null : (earned * 100 / possible).round();
  }

  /// The specialty fits (or one side did not name any).
  bool get specialtyFits => !checks.any((c) => c.kind == CheckKind.specialty && c.state == CheckState.no);

  /// Shown under "Uyğun …": the specialty fits and at least 60 %.
  bool get good => specialtyFits && (percent ?? 0) >= 60;
}

/// Points per line.
const kWeightSpecialty = 40;
const kWeightMust = 10;
const kWeightNice = 4;
const kWeightExperience = 10;
const kWeightAge = 10;
const kWeightPlace = 10;
const kWeightCity = 5;
const kWeightCountries = 10;
const kWeightSalary = 10;
const kWeightSchedule = 5;

bool _same(String? a, String? b) => a != null && b != null && a.trim().toLowerCase() == b.trim().toLowerCase();

/// Countries: the same one, or "Avropa İttifaqı" and one of its members.
bool _country(String? a, String? b) => jobCountryFits(a, b, (x) => Countries.find(x)?.code);

/// Compares one driver with one vacancy. The same result is used both ways:
/// "Uyğun sürücülər" for the employer and "Mənə uyğun işlər" for the driver.
JobMatch matchJob(JobSeeker s, JobVacancy v) {
  final out = <MatchCheck>[];

  // 1) Specialty (REF for REF …): the most important line.
  if (v.specialties.isNotEmpty) {
    final common = v.specialties.where(s.specialties.contains).toList();
    out.add(MatchCheck(
      CheckKind.specialty,
      s.specialties.isEmpty ? CheckState.unknown : (common.isNotEmpty ? CheckState.yes : CheckState.no),
      code: common.isNotEmpty ? common.first : v.specialties.first,
      weight: kWeightSpecialty,
    ));
  }

  // 2) The employer's requirements, in catalogue order (must first).
  final order = [for (final k in kJobSkills) k.code];
  final codes = v.requirements.keys.toList()
    ..sort((a, b) {
      final m = (v.requirements[a] == ReqLevel.must ? 0 : 1) - (v.requirements[b] == ReqLevel.must ? 0 : 1);
      if (m != 0) return m;
      final ia = order.indexOf(a), ib = order.indexOf(b);
      return (ia < 0 ? 999 : ia) - (ib < 0 ? 999 : ib);
    });
  for (final code in codes) {
    final level = v.requirements[code]!;
    final has = s.skills[code];
    out.add(MatchCheck(
      CheckKind.skill,
      switch (has) {
        SkillState.yes => CheckState.yes,
        SkillState.no => CheckState.no,
        SkillState.ready => CheckState.ready,
        null => CheckState.unknown,
      },
      code: code,
      level: level,
      canHelp: v.canHelp.contains(code),
      weight: level == ReqLevel.must ? kWeightMust : kWeightNice,
    ));
  }

  // 3) Experience.
  if (v.minExperience != null && v.minExperience! > 0) {
    out.add(MatchCheck(
      CheckKind.experience,
      s.experienceYears == null
          ? CheckState.unknown
          : (s.experienceYears! >= v.minExperience! ? CheckState.yes : CheckState.no),
      weight: kWeightExperience,
    ));
  }

  // 3b) Age range (0072).
  if (v.ageMin != null || v.ageMax != null) {
    final a = s.age ?? (s.birthDate == null ? null : ageOn(s.birthDate!, DateTime.now()));
    out.add(MatchCheck(
      CheckKind.age,
      a == null ? CheckState.unknown : ((v.ageMin == null || a >= v.ageMin!) && (v.ageMax == null || a <= v.ageMax!) ? CheckState.yes : CheckState.no),
      weight: kWeightAge,
    ));
  }

  // 4) Country (his country, or a country he wants to work in), then city.
  if (v.country != null) {
    final known = s.country != null || s.countries.isNotEmpty;
    final fits = _country(s.country, v.country) || s.countries.any((c) => _country(c, v.country));
    out.add(MatchCheck(CheckKind.place, !known ? CheckState.unknown : (fits ? CheckState.yes : CheckState.no),
        weight: kWeightPlace));
    if (v.city != null && s.city != null && _same(s.country, v.country)) {
      out.add(MatchCheck(CheckKind.city, _same(s.city, v.city) ? CheckState.yes : CheckState.no, weight: kWeightCity));
    }
  }

  // 5) Countries / routes of the work.
  if (v.countries.isNotEmpty && s.countries.isNotEmpty) {
    final overlap = v.countries.any((c) => s.countries.any((d) => _country(c, d)));
    out.add(MatchCheck(CheckKind.countries, overlap ? CheckState.yes : CheckState.no, weight: kWeightCountries));
  }

  // 6) Salary: what he expects fits what is offered (same currency only).
  final offer = v.salaryMax ?? v.salaryMin;
  if (s.salaryMin != null && offer != null) {
    final sameCurrency = (s.currency ?? 'AZN') == (v.currency ?? 'AZN');
    out.add(MatchCheck(
      CheckKind.salary,
      !sameCurrency ? CheckState.unknown : (s.salaryMin! <= offer ? CheckState.yes : CheckState.no),
      weight: kWeightSalary,
    ));
  }

  // 7) Work schedule.
  // Several on either side (0073): one in common is enough.
  final vs = v.allSchedules, ss = s.allSchedules;
  if (vs.isNotEmpty && ss.isNotEmpty) {
    out.add(MatchCheck(CheckKind.schedule, vs.any(ss.contains) ? CheckState.yes : CheckState.no,
        weight: kWeightSchedule));
  }
  return JobMatch(out);
}

/// Order of a result list: specialty first, then the percentage, then the
/// newest. Nobody is left out ([only] = the "Uyğun …" tab).
List<T> rankMatches<T>(List<T> items, JobMatch Function(T) match, {bool only = false, DateTime? Function(T)? updated}) {
  final scored = [for (final (i, t) in items.indexed) (i: i, t: t, m: match(t))];
  final kept = only ? scored.where((e) => e.m.good).toList() : scored;
  kept.sort((a, b) {
    final s = (b.m.specialtyFits ? 1 : 0) - (a.m.specialtyFits ? 1 : 0);
    if (s != 0) return s;
    final p = (b.m.percent ?? -1) - (a.m.percent ?? -1);
    if (p != 0) return p;
    final ua = updated?.call(a.t), ub = updated?.call(b.t);
    if (ua != null && ub != null && ua != ub) return ub.compareTo(ua);
    return a.i - b.i;
  });
  return [for (final e in kept) e.t];
}

import 'job_match.dart';
import 'job_models.dart';

// İş Mərkəzi home page (owner, 28.10.2026, picture 1): "Aktiv elanlar" —
// vacancies and drivers looking for work in one list — and "Uyğun
// təkliflər" from the existing SmartMatch. Pure, unit-tested in
// test/job_center_home_test.dart.

enum JobFeedKind { all, vacancies, drivers }

/// One row of "Aktiv elanlar": a vacancy or a driver.
class JobFeedItem {
  final JobVacancy? vacancy;
  final JobSeeker? seeker;
  const JobFeedItem.vacancy(JobVacancy this.vacancy) : seeker = null;
  const JobFeedItem.seeker(JobSeeker this.seeker) : vacancy = null;

  bool get isVacancy => vacancy != null;
  String get id => isVacancy ? vacancy!.id : seeker!.userId;
  String get ownerId => isVacancy ? vacancy!.ownerId : seeker!.userId;
  DateTime? get updatedAt => isVacancy ? vacancy!.updatedAt : seeker!.updatedAt;
  List<String> get specialties => isVacancy ? vacancy!.specialties : seeker!.specialties;
  List<String> get countries => isVacancy ? vacancy!.countries : seeker!.countries;
  String? get country => isVacancy ? vacancy!.country : seeker!.country;

  /// Licence categories: required by the vacancy / the driver has them.
  List<String> get licences => isVacancy
      ? [for (final c in vacancy!.requirements.keys) if (c.startsWith('lic_')) c]
      : [for (final e in seeker!.skills.entries) if (e.key.startsWith('lic_') && e.value == SkillState.yes) e.key];

  int? get experience => isVacancy ? vacancy!.minExperience : seeker!.experienceYears;

  /// Route page: /jobs/v/:id (vacancy) or /jobs/d/:id (driver).
  String get route => isVacancy ? '/jobs/v/$id' : '/jobs/d/$id';
}

/// Highest category first (CE for a TIR driver); unknown codes after.
const kLicenceRank = ['lic_de', 'lic_d1e', 'lic_ce', 'lic_c1e', 'lic_d', 'lic_d1', 'lic_c', 'lic_c1', 'lic_b'];

String? topLicence(List<String> codes) {
  if (codes.isEmpty) return null;
  final sorted = [...codes]..sort((a, b) {
      int r(String c) => kLicenceRank.contains(c) ? kLicenceRank.indexOf(c) : kLicenceRank.length;
      return r(a).compareTo(r(b));
    });
  return sorted.first;
}

/// The filter of "Aktiv elanlar".
class JobFeedFilter {
  final JobFeedKind kind;
  final String? specialty;
  final String? licence;
  final String? country;
  const JobFeedFilter({this.kind = JobFeedKind.all, this.specialty, this.licence, this.country});

  int get count => (kind == JobFeedKind.all ? 0 : 1) + [specialty, licence, country].where((x) => x != null).length;

  bool fits(JobFeedItem it) {
    if (kind == JobFeedKind.vacancies && !it.isVacancy) return false;
    if (kind == JobFeedKind.drivers && it.isVacancy) return false;
    if (specialty != null && !it.specialties.contains(specialty)) return false;
    if (licence != null && !it.licences.contains(licence)) return false;
    if (country != null) {
      final c = country!.toLowerCase();
      if (!(it.countries.any((x) => x.toLowerCase() == c) || it.country?.toLowerCase() == c)) return false;
    }
    return true;
  }
}

/// Vacancies and drivers in one list, newest first.
List<JobFeedItem> buildJobFeed(List<JobVacancy> vacancies, List<JobSeeker> seekers, {JobFeedFilter filter = const JobFeedFilter()}) {
  final all = [
    for (final v in vacancies) if (v.isActive) JobFeedItem.vacancy(v),
    for (final s in seekers) if (s.isActive) JobFeedItem.seeker(s),
  ];
  final indexed = [for (final (i, it) in all.indexed) (i, it)]..sort((a, b) {
      final ua = a.$2.updatedAt, ub = b.$2.updatedAt;
      if (ua != null && ub != null && ua != ub) return ub.compareTo(ua);
      if (ua != null && ub == null) return -1;
      if (ua == null && ub != null) return 1;
      return a.$1.compareTo(b.$1);
    });
  return [for (final e in indexed) if (filter.fits(e.$2)) e.$2];
}

/// A suggestion of "Uyğun təkliflər": the item and how well it fits.
class JobSuggestion {
  final JobFeedItem item;
  final JobMatch match;
  const JobSuggestion(this.item, this.match);
}

/// SmartMatch for the home page: vacancies that fit my driver profile
/// (when it is on) and drivers that fit my active vacancies (the best of
/// them per driver). Only good matches (specialty fits, ≥ 60 %), mine are
/// left out; the best first, at most [limit].
List<JobSuggestion> jobSuggestions({
  required String? me,
  required JobSeeker? myProfile,
  required List<JobVacancy> myVacancies,
  required List<JobVacancy> vacancies,
  required List<JobSeeker> seekers,
  int limit = 4,
}) {
  final out = <JobSuggestion>[];
  if (myProfile != null && myProfile.isActive) {
    for (final v in vacancies) {
      if (v.ownerId == me || !v.isActive) continue;
      final m = matchJob(myProfile, v);
      if (m.good) out.add(JobSuggestion(JobFeedItem.vacancy(v), m));
    }
  }
  final mine = myVacancies.where((v) => v.isActive).toList();
  if (mine.isNotEmpty) {
    for (final s in seekers) {
      if (s.userId == me || !s.isActive) continue;
      JobMatch? best;
      for (final v in mine) {
        final m = matchJob(s, v);
        if (best == null || (m.percent ?? -1) > (best.percent ?? -1)) best = m;
      }
      if (best != null && best.good) out.add(JobSuggestion(JobFeedItem.seeker(s), best));
    }
  }
  out.sort((a, b) => (b.match.percent ?? 0).compareTo(a.match.percent ?? 0));
  return out.take(limit).toList();
}

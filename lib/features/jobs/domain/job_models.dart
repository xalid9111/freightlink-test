// İş Mərkəzi — SmartMatch (owner, 26.10.2026, migration 0069). Pure
// models, unit-tested in test/job_center_test.dart.

/// A driver's answer for one document / skill. A code that is missing from
/// the map means "not given" — never the same as [no].
enum SkillState { yes, no, ready }

/// How much an employer wants one document / skill.
enum ReqLevel { must, nice }

SkillState? skillStateFrom(Object? v) => switch (v) {
      'yes' => SkillState.yes,
      'no' => SkillState.no,
      'ready' => SkillState.ready,
      _ => null,
    };

ReqLevel? reqLevelFrom(Object? v) => switch (v) {
      'must' => ReqLevel.must,
      'nice' => ReqLevel.nice,
      _ => null,
    };

/// One entry of a catalogue (job_specialties / job_skills). [kind] is
/// 'license' | 'document' | 'skill' for skills, null for specialties.
class JobCatalogItem {
  final String code;
  final String name;
  final String? kind;
  const JobCatalogItem(this.code, this.name, [this.kind]);

  factory JobCatalogItem.fromJson(Map<String, dynamic> j) =>
      JobCatalogItem('${j['code']}', '${j['name'] ?? j['code']}', j['kind'] as String?);
}

/// The catalogues as seeded by 0069 (used until / unless the server list
/// loads; an admin can add more on the server later).
const kJobSpecialties = [
  JobCatalogItem('tent', 'Tent'),
  JobCatalogItem('ref', 'REF'),
  JobCatalogItem('tow', 'Evakuator'),
  JobCatalogItem('container', 'Konteyner'),
  JobCatalogItem('dump', 'Samosval'),
  JobCatalogItem('tanker', 'Sistern'),
  JobCatalogItem('car_carrier', 'Avtovoz'),
  JobCatalogItem('bus', 'Avtobus'),
  JobCatalogItem('excavator', 'Ekskavator'),
  JobCatalogItem('other', 'Digər'),
];

const kJobSkills = [
  JobCatalogItem('lic_b', 'B', 'license'),
  JobCatalogItem('lic_c1', 'C1', 'license'),
  JobCatalogItem('lic_c', 'C', 'license'),
  JobCatalogItem('lic_ce', 'CE', 'license'),
  JobCatalogItem('lic_d', 'D', 'license'),
  JobCatalogItem('tachograph', 'Taxoqraf kartı', 'document'),
  JobCatalogItem('cpc', 'Peşə sertifikatı', 'document'),
  JobCatalogItem('intl_exp', 'Beynəlxalq daşıma təcrübəsi', 'skill'),
  JobCatalogItem('tech', 'Nəqliyyatın texniki quruluşundan anlayış', 'skill'),
  JobCatalogItem('discipline', 'Nizam-intizam', 'skill'),
  JobCatalogItem('responsibility', 'Məsuliyyətli yanaşma', 'skill'),
];

const kJobSkillKinds = ['license', 'document', 'skill'];
const kJobSchedules = ['full_time', 'part_time', 'rotation', 'flexible'];
const kJobCurrencies = ['AZN', 'USD', 'EUR', 'RUB', 'TRY', 'GEL', 'KZT'];

List<String> _strings(Object? v) => [for (final x in (v as List? ?? const [])) if (x is String && x.isNotEmpty) x];
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
int? _int(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String? _text(Object? v) {
  final s = (v as String?)?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// A driver's work profile ("İş axtarıram"). From the safe list
/// (job_seekers_list: age, the phone only if shown) or my own row
/// (birth date, my phone).
class JobSeeker {
  final String userId;
  final String fullName;
  final String? avatarUrl;
  final int? age;
  final DateTime? birthDate;
  final String? country, city;
  final int? experienceYears;
  final List<String> specialties;
  final Map<String, SkillState> skills;
  final String? otherDocs;
  final List<String> countries;
  final String? routes;
  final double? salaryMin;
  final String? currency;
  final String? schedule;
  final String? note;
  final String? phone;
  final bool showPhone;
  final bool whatsapp;
  final bool isActive;
  final bool isHidden;
  final DateTime? updatedAt;

  const JobSeeker({
    required this.userId,
    required this.fullName,
    this.avatarUrl,
    this.age,
    this.birthDate,
    this.country,
    this.city,
    this.experienceYears,
    this.specialties = const [],
    this.skills = const {},
    this.otherDocs,
    this.countries = const [],
    this.routes,
    this.salaryMin,
    this.currency,
    this.schedule,
    this.note,
    this.phone,
    this.showPhone = false,
    this.whatsapp = false,
    this.isActive = true,
    this.isHidden = false,
    this.updatedAt,
  });

  factory JobSeeker.fromJson(Map<String, dynamic> j) {
    final birth = j['birth_date'] == null ? null : DateTime.tryParse('${j['birth_date']}');
    return JobSeeker(
      userId: '${j['user_id']}',
      fullName: '${j['full_name'] ?? ''}'.trim(),
      avatarUrl: j['avatar_url'] as String?,
      age: _int(j['age']) ?? (birth == null ? null : ageOn(birth, DateTime.now())),
      birthDate: birth,
      country: _text(j['country']),
      city: _text(j['city']),
      experienceYears: _int(j['experience_years']),
      specialties: _strings(j['specialties']),
      skills: {
        for (final e in ((j['skills'] as Map?) ?? const {}).entries)
          if (skillStateFrom(e.value) != null) '${e.key}': skillStateFrom(e.value)!,
      },
      otherDocs: _text(j['other_docs']),
      countries: _strings(j['countries']),
      routes: _text(j['routes']),
      salaryMin: _num(j['salary_min']),
      currency: _text(j['currency']),
      schedule: _text(j['schedule']),
      note: _text(j['note']),
      phone: _text(j['phone']),
      showPhone: j['show_phone'] == true,
      whatsapp: j['whatsapp'] == true,
      isActive: j['is_active'] != false,
      isHidden: j['is_hidden'] == true,
      updatedAt: j['updated_at'] == null ? null : DateTime.tryParse('${j['updated_at']}'),
    );
  }

  /// What I save for myself (is_hidden is never sent — only an admin).
  Map<String, dynamic> toRow() => {
        'user_id': userId,
        'full_name': fullName.trim(),
        'birth_date': birthDate == null
            ? null
            : '${birthDate!.year.toString().padLeft(4, '0')}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}',
        'country': country,
        'city': city,
        'experience_years': experienceYears,
        'specialties': specialties,
        'skills': {for (final e in skills.entries) e.key: e.value.name},
        'other_docs': otherDocs,
        'countries': countries,
        'routes': routes,
        'salary_min': salaryMin,
        'currency': salaryMin == null ? null : (currency ?? 'AZN'),
        'schedule': schedule,
        'note': note,
        'phone': phone,
        'show_phone': showPhone,
        'whatsapp': whatsapp,
        'is_active': isActive,
      };
}

int ageOn(DateTime birth, DateTime now) {
  var a = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) a--;
  return a;
}

/// An employer's vacancy ("İşçi axtarıram").
class JobVacancy {
  final String id;
  final String ownerId;
  final String? ownerName;
  final String? avatarUrl;
  final String companyName;
  final String? country, city;
  final List<String> specialties;
  final Map<String, ReqLevel> requirements;
  final Set<String> canHelp;
  final int? minExperience;
  final List<String> countries;
  final String? routes;
  final double? salaryMin, salaryMax;
  final String? currency;
  final String? schedule;
  final String? conditions;
  final String? phone;
  final bool showPhone;
  final bool whatsapp;
  final String status;
  final bool isHidden;
  final DateTime? updatedAt;

  const JobVacancy({
    this.id = '',
    required this.ownerId,
    this.ownerName,
    this.avatarUrl,
    required this.companyName,
    this.country,
    this.city,
    this.specialties = const [],
    this.requirements = const {},
    this.canHelp = const {},
    this.minExperience,
    this.countries = const [],
    this.routes,
    this.salaryMin,
    this.salaryMax,
    this.currency,
    this.schedule,
    this.conditions,
    this.phone,
    this.showPhone = false,
    this.whatsapp = false,
    this.status = 'active',
    this.isHidden = false,
    this.updatedAt,
  });

  bool get isActive => status == 'active';

  factory JobVacancy.fromJson(Map<String, dynamic> j) => JobVacancy(
        id: '${j['id']}',
        ownerId: '${j['owner_id']}',
        ownerName: _text(j['owner_name']),
        avatarUrl: j['avatar_url'] as String?,
        companyName: '${j['company_name'] ?? ''}'.trim(),
        country: _text(j['country']),
        city: _text(j['city']),
        specialties: _strings(j['specialties']),
        requirements: {
          for (final e in ((j['requirements'] as Map?) ?? const {}).entries)
            if (reqLevelFrom(e.value) != null) '${e.key}': reqLevelFrom(e.value)!,
        },
        canHelp: _strings(j['can_help']).toSet(),
        minExperience: _int(j['min_experience']),
        countries: _strings(j['countries']),
        routes: _text(j['routes']),
        salaryMin: _num(j['salary_min']),
        salaryMax: _num(j['salary_max']),
        currency: _text(j['currency']),
        schedule: _text(j['schedule']),
        conditions: _text(j['conditions']),
        phone: _text(j['phone']),
        showPhone: j['show_phone'] == true,
        whatsapp: j['whatsapp'] == true,
        status: (j['status'] as String?) ?? 'active',
        isHidden: j['is_hidden'] == true,
        updatedAt: j['updated_at'] == null ? null : DateTime.tryParse('${j['updated_at']}'),
      );

  /// What the owner saves (owner / is_hidden are kept by the server).
  Map<String, dynamic> toRow() => {
        'owner_id': ownerId,
        'company_name': companyName.trim(),
        'country': country,
        'city': city,
        'specialties': specialties,
        'requirements': {for (final e in requirements.entries) e.key: e.value.name},
        'can_help': [
          for (final c in canHelp)
            if (requirements.containsKey(c)) c
        ],
        'min_experience': minExperience,
        'countries': countries,
        'routes': routes,
        'salary_min': salaryMin,
        'salary_max': salaryMax,
        'currency': (salaryMin == null && salaryMax == null) ? null : (currency ?? 'AZN'),
        'schedule': schedule,
        'conditions': conditions,
        'phone': phone,
        'show_phone': showPhone,
        'whatsapp': whatsapp,
        'status': status,
      };
}

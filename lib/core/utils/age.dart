/// Age picked in a list (registration, Profil, İş Mərkəzi — owner,
/// 28.10.2026). Stored as a birth date: 1 January of (this year − age),
/// so the age shown is the one picked and grows by itself every year.
/// The server allows 16 – 100 (migration 0074).
const kAgeMin = 16;
const kAgeMax = 90;

List<int> get kAgeChoices => [for (var a = kAgeMin; a <= kAgeMax; a++) a];

DateTime birthDateForAge(int age, DateTime now) => DateTime(now.year - age, 1, 1);

int ageFromBirthDate(DateTime birth, DateTime now) {
  var a = now.year - birth.year;
  if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) a--;
  return a;
}

/// "1990-01-01" for the database.
String birthDateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// One account, several activities (migration 0039) — pure logic,
// unit-tested in test/activities_test.dart.

/// What a user does on FreightLink. Any combination can be on at once.
enum Activity { carrier, shipper, service, seller }

extension ActivityX on Activity {
  /// Value stored in users.activities.
  String get wire => name;

  /// Translation key of the button label.
  String get labelKey => 'act_$name';

  static Activity? parse(String? s) {
    for (final a in Activity.values) {
      if (a.name == s) return a;
    }
    return null;
  }
}

/// Activities from the database row. Before 0039 is applied (column
/// missing / null) they are derived from the old role, like the migration
/// fills them, so nothing a user could do before disappears.
Set<Activity> activitiesFrom(Object? stored, {String? role, bool hasService = false}) {
  if (stored is List) {
    return stored.map((x) => ActivityX.parse('$x')).whereType<Activity>().toSet();
  }
  return {
    if (role == 'carrier' || role == 'driver') Activity.carrier,
    if (role == 'cargo_owner') Activity.shipper,
    if (hasService) Activity.service,
  };
}

/// Tapping a button: on → off, off → on; the others stay as they are.
Set<Activity> toggleActivity(Set<Activity> current, Activity a) =>
    current.contains(a) ? ({...current}..remove(a)) : {...current, a};

/// Stable order for saving and showing (Daşıyıcı, Yük verən, Usta / Servis, Satış).
List<String> activitiesWire(Set<Activity> s) => [for (final a in Activity.values) if (s.contains(a)) a.wire];

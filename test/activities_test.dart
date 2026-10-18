// Profil: one account, any combination of activities (migration 0039).
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/auth/domain/activities.dart';

void main() {
  test('stored activities are read as they are (any combination)', () {
    expect(activitiesFrom(['carrier', 'shipper', 'service', 'seller']), Activity.values.toSet());
    expect(activitiesFrom(<String>[]), isEmpty);
    expect(activitiesFrom(['seller', 'unknown']), {Activity.seller});
  });

  test('before 0039 they come from the old role, nothing is lost', () {
    expect(activitiesFrom(null, role: 'carrier'), {Activity.carrier});
    expect(activitiesFrom(null, role: 'driver'), {Activity.carrier});
    expect(activitiesFrom(null, role: 'cargo_owner', hasService: true), {Activity.shipper, Activity.service});
    expect(activitiesFrom(null, role: 'admin'), isEmpty);
  });

  test('a tap turns one on / off and keeps the others', () {
    var s = <Activity>{};
    for (final a in Activity.values) {
      s = toggleActivity(s, a);
    }
    expect(s, Activity.values.toSet(), reason: 'all four at once');
    s = toggleActivity(s, Activity.carrier);
    expect(s, {Activity.shipper, Activity.service, Activity.seller});
    s = toggleActivity(s, Activity.carrier);
    expect(s.contains(Activity.carrier), isTrue);
  });

  test('saved in a stable order with the database values', () {
    expect(activitiesWire({Activity.seller, Activity.carrier}), ['carrier', 'seller']);
    expect(Activity.values.map((a) => a.wire), ['carrier', 'shipper', 'service', 'seller']);
    expect(Activity.values.map((a) => a.labelKey), ['act_carrier', 'act_shipper', 'act_service', 'act_seller']);
  });
}

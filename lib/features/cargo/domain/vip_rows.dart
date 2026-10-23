import '../../../models/cargo_model.dart';

/// VIP loads on the Loads page (owner, 23–24.10.2026, migration 0059).
///
/// * VIP first, then they take turns with normal loads, one by one:
///   VIP, load, VIP, load … When the VIP loads run out the normal loads
///   simply follow (never an empty card). Each load is shown once.
/// * The VIP order moves on by one place every [kVipRotateMinutes]
///   minutes ([rotation]), so every VIP comes to the front in turn —
///   none always stays at the back.
/// * Normal loads keep their order (newest first).
/// * The flow is cut into rows of [columns] (2 on a phone): always pairs
///   1-2, 3-4 …; only the very last card may stand alone, at the bottom.
///   The computer uses the same flow with wider rows.
const kVipRotateMinutes = 5;

/// 0059 interval setting (2 / 3 / 4 rows) — kept in the database, no
/// longer used by the Loads page since VIP and normal loads alternate.
const kVipEveryChoices = [2, 3, 4];
const kDefaultVipEvery = 3;

typedef LoadCell = ({int index, bool vip});

/// How far the VIP order has moved at [now] (every [kVipRotateMinutes]).
int vipRotation(DateTime now) => now.millisecondsSinceEpoch ~/ (kVipRotateMinutes * 60 * 1000);

/// The flow of cards in order: VIP, load, VIP, load …
List<LoadCell> buildLoadFlow(List<CargoModel> loads, {DateTime? now, int? rotation}) {
  final t = now ?? DateTime.now();
  final vip = <int>[];
  final normal = <int>[];
  for (var i = 0; i < loads.length; i++) {
    (loads[i].isVipAt(t) ? vip : normal).add(i);
  }
  if (vip.length > 1) {
    final r = (rotation ?? vipRotation(t)) % vip.length;
    vip.setAll(0, [...vip.sublist(r), ...vip.sublist(0, r)]);
  }
  final out = <LoadCell>[];
  for (var i = 0; i < vip.length || i < normal.length; i++) {
    if (i < vip.length) out.add((index: vip[i], vip: true));
    if (i < normal.length) out.add((index: normal[i], vip: false));
  }
  return out;
}

/// The flow cut into rows of [columns] (only the last row can be short).
List<List<LoadCell>> buildLoadRows(List<CargoModel> loads, {required int columns, DateTime? now, int? rotation}) {
  final cols = columns < 1 ? 1 : columns;
  final flow = buildLoadFlow(loads, now: now, rotation: rotation);
  return [for (var i = 0; i < flow.length; i += cols) flow.sublist(i, (i + cols).clamp(0, flow.length))];
}

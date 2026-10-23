import '../../../models/cargo_model.dart';

/// VIP loads on the Loads page (owner, 23–24.10.2026, migration 0059).
///
/// * One flow of cards, always filled pair by pair (rows of [columns]):
///   1-2, 3-4, 5-6 … — a row is never left half empty in the middle; only
///   the very last card can stand alone, at the bottom.
/// * Normal loads keep their order (newest first).
/// * After every [vipEvery] rows of normal loads (admin: 2 / 3 / 4,
///   default 3) the next VIP load joins the flow — ONE at a time, in their
///   own order (VIP 1, VIP 2, VIP 3 …), not in pairs.
/// * When the VIP loads run out none is added (never an empty card); VIP
///   loads left over follow at the end, so none is hidden. A VIP load is
///   shown only once.
/// * The same on the phone (2 per row) and the computer (as many as fit).
const kVipEveryChoices = [2, 3, 4];
const kDefaultVipEvery = 3;

typedef LoadCell = ({int index, bool vip});

/// The flow of cards in order.
List<LoadCell> buildLoadFlow(List<CargoModel> loads, {required int vipEvery, required int columns, DateTime? now}) {
  final t = now ?? DateTime.now();
  final every = kVipEveryChoices.contains(vipEvery) ? vipEvery : kDefaultVipEvery;
  final cols = columns < 1 ? 1 : columns;
  final vip = <int>[];
  final normal = <int>[];
  for (var i = 0; i < loads.length; i++) {
    (loads[i].isVipAt(t) ? vip : normal).add(i);
  }
  final out = <LoadCell>[];
  var v = 0;
  for (var n = 0; n < normal.length; n++) {
    out.add((index: normal[n], vip: false));
    // After every `every` rows' worth of normal loads: the next VIP.
    if ((n + 1) % (every * cols) == 0 && v < vip.length) out.add((index: vip[v++], vip: true));
  }
  while (v < vip.length) {
    out.add((index: vip[v++], vip: true));
  }
  return out;
}

/// The flow cut into rows of [columns] (only the last row can be short).
List<List<LoadCell>> buildLoadRows(List<CargoModel> loads, {required int vipEvery, required int columns, DateTime? now}) {
  final cols = columns < 1 ? 1 : columns;
  final flow = buildLoadFlow(loads, vipEvery: vipEvery, columns: cols, now: now);
  return [for (var i = 0; i < flow.length; i += cols) flow.sublist(i, (i + cols).clamp(0, flow.length))];
}

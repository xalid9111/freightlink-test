import '../../../models/cargo_model.dart';

/// VIP loads on the Loads page (owner, 23.10.2026, migration 0059).
///
/// * Normal loads keep their order (newest first) in rows of [columns].
/// * After every [vipEvery] normal rows (admin: 2 / 3 / 4, default 3) comes
///   one row of [vipColumns] (2) VIP loads side by side, in their own order
///   — the same on the phone and the computer.
/// * When the VIP loads run out no VIP row is shown (never an empty card);
///   VIP loads left over after the last normal row follow at the end, so
///   none is hidden. A VIP load is shown only once, in a VIP row.
const kVipEveryChoices = [2, 3, 4];
const kDefaultVipEvery = 3;

typedef LoadRow = ({bool vip, List<int> loads});

List<LoadRow> buildLoadRows(List<CargoModel> loads,
    {required int vipEvery, required int columns, int vipColumns = 2, DateTime? now}) {
  final t = now ?? DateTime.now();
  final every = kVipEveryChoices.contains(vipEvery) ? vipEvery : kDefaultVipEvery;
  final cols = columns < 1 ? 1 : columns;
  final vipCols = vipColumns < 1 ? 1 : vipColumns;
  final vip = <int>[];
  final normal = <int>[];
  for (var i = 0; i < loads.length; i++) {
    (loads[i].isVipAt(t) ? vip : normal).add(i);
  }
  final out = <LoadRow>[];
  var v = 0;
  void vipRow() {
    if (v >= vip.length) return;
    final end = (v + vipCols).clamp(0, vip.length);
    out.add((vip: true, loads: vip.sublist(v, end)));
    v = end;
  }

  var rows = 0;
  for (var i = 0; i < normal.length; i += cols) {
    out.add((vip: false, loads: normal.sublist(i, (i + cols).clamp(0, normal.length))));
    if (++rows % every == 0) vipRow();
  }
  while (v < vip.length) {
    vipRow();
  }
  return out;
}

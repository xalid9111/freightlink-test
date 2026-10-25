import '../../../models/cargo_model.dart';

/// VIP loads on the Loads page (owner, 23–24.10.2026, migration 0059).
///
/// * Chessboard order (owner, 24.10.2026): every row has one normal load
///   and one VIP, and they swap sides row by row:
///     load – VIP
///     VIP – load
///     load – VIP
///     VIP – load …
///   When one kind runs out the other simply fills the rows (never an
///   empty card). Each load is shown once.
/// * The VIP order moves on by one place every [kVipRotateMinutes]
///   minutes ([rotation]), so every VIP comes to the front in turn —
///   none always stays at the back.
/// * Normal loads: the latest lift first (posted, or İrəli çək / VIP /
///   Premium lift — CargoModel.liftedAt, 0067), like TIR Bazarı.
/// * Premium loads (0067) stand at the very top, before the chessboard
///   (they are VIP too, shown once); their order moves on like the VIPs,
///   as on TIR Bazarı (marketFeedWithPremium).
/// * Rows of [columns] (2 on a phone): always pairs; only the very last
///   card may stand alone, at the bottom. The computer uses the same
///   chessboard with wider rows.
const kVipRotateMinutes = 5;

/// 0059 interval setting (2 / 3 / 4 rows) — kept in the database, no
/// longer used by the Loads page (chessboard order instead).
const kVipEveryChoices = [2, 3, 4];
const kDefaultVipEvery = 3;

typedef LoadCell = ({int index, bool vip});

/// How far the VIP order has moved at [now] (every [kVipRotateMinutes]).
int vipRotation(DateTime now) => now.millisecondsSinceEpoch ~/ (kVipRotateMinutes * 60 * 1000);

/// The cards in order, chessboard by rows of [columns].
List<LoadCell> buildLoadFlow(List<CargoModel> loads, {int columns = 2, DateTime? now, int? rotation}) {
  final t = now ?? DateTime.now();
  final cols = columns < 1 ? 1 : columns;
  final premium = <int>[];
  final vip = <int>[];
  final normal = <int>[];
  for (var i = 0; i < loads.length; i++) {
    (loads[i].isPremiumAt(t) ? premium : (loads[i].isVipAt(t) ? vip : normal)).add(i);
  }
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  // Newest first; equal times keep the order they came in.
  void newestFirst(List<int> l, DateTime Function(CargoModel c) at) => l.sort((a, b) {
        final d = at(loads[b]).compareTo(at(loads[a]));
        return d != 0 ? d : a.compareTo(b);
      });
  newestFirst(premium, (c) => c.premiumSince ?? epoch);
  newestFirst(normal, (c) => c.liftedAt(t));
  final turn = rotation ?? vipRotation(t);
  for (final l in [vip, premium]) {
    if (l.length > 1) {
      final r = turn % l.length;
      l.setAll(0, [...l.sublist(r), ...l.sublist(0, r)]);
    }
  }
  final out = <LoadCell>[for (final i in premium) (index: i, vip: true)];
  var v = 0, n = 0;
  while (v < vip.length || n < normal.length) {
    // The chessboard starts after the Premium loads.
    final pos = out.length - premium.length;
    // Row r, place k: VIP where (r + k) is odd — load–VIP, then VIP–load …
    final wantVip = ((pos ~/ cols) + (pos % cols)).isOdd;
    final takeVip = wantVip ? v < vip.length : n >= normal.length;
    if (takeVip) {
      out.add((index: vip[v++], vip: true));
    } else {
      out.add((index: normal[n++], vip: false));
    }
  }
  return out;
}

/// The flow cut into rows of [columns] (only the last row can be short).
List<List<LoadCell>> buildLoadRows(List<CargoModel> loads, {required int columns, DateTime? now, int? rotation}) {
  final cols = columns < 1 ? 1 : columns;
  final flow = buildLoadFlow(loads, columns: cols, now: now, rotation: rotation);
  return [for (var i = 0; i < flow.length; i += cols) flow.sublist(i, (i + cols).clamp(0, flow.length))];
}

/// The Loads page VIP order for any list (owner, 24.10.2026: "TIR Bazarı-da
/// VIP-lər yüklərdəki kimi"): rows of [columns], a plain item and a VIP
/// swapping sides row by row — plain–VIP, VIP–plain, plain–VIP … — each
/// VIP shown once; when one kind runs out the other fills the rows. The VIP
/// order moves on by [rotation] places (every few minutes, see
/// `vipRotation` in features/cargo/domain/vip_rows.dart) so every VIP
/// comes to the front in turn. Plain items keep their order.
/// Same rule as `buildLoadFlow` (test/market_vip_test.dart compares them).
List<(T, bool)> vipChessboard<T>(List<T> plain, List<T> vip, {int columns = 2, int rotation = 0}) {
  final cols = columns < 1 ? 1 : columns;
  var v = [...vip];
  if (v.length > 1) {
    final r = rotation % v.length;
    v = [...v.sublist(r), ...v.sublist(0, r)];
  }
  final out = <(T, bool)>[];
  var iv = 0, ip = 0;
  while (iv < v.length || ip < plain.length) {
    final pos = out.length;
    final wantVip = ((pos ~/ cols) + (pos % cols)).isOdd;
    final takeVip = wantVip ? iv < v.length : ip >= plain.length;
    out.add(takeVip ? (v[iv++], true) : (plain[ip++], false));
  }
  return out;
}

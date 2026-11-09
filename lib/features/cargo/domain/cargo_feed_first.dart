import '../../../models/cargo_model.dart';
import 'vip_rows.dart';

/// Staged Yüklər feed (owner, 09.11.2026, "Turbo.az kimi"): the first rows
/// come from a small first answer, the rest follows in the background.
///
/// The first answer = every promoted load (VIP, Premium, İrəli çək) + the
/// [kCargoFirstPage] newest loads. Every load that can stand before the
/// newest ones in the chessboard (buildLoadFlow) is in it, so the rows
/// shown from it are EXACTLY the first rows of the full feed — same cards,
/// same VIP / Premium order and rotation. Only the rows that could still
/// change (a plain load older than the first page could belong there) are
/// held back until the full feed is here; then it replaces this answer.
const kCargoFirstPage = 24;

typedef CargoFeedPart = ({
  List<CargoModel> loads,
  // The full feed is in it (fewer loads than one page): show all rows.
  bool complete,
  // created_at of the oldest load of the newest page.
  DateTime? cutoff,
});

/// The filter the promoted query uses on the server, the same rule here.
const kCargoPromotedFilter = 'is_featured.eq.true,premium_until.not.is.null,bump_total.gt.0';

bool isPromotedRow(CargoModel c) => c.isFeatured || c.premiumUntil != null || (c.bumpTotal ?? 0) > 0;

/// Joins the two answers: newest-first like the full feed (the same input
/// order buildLoadFlow gets), each load once, only listed loads.
CargoFeedPart mergeFirstPart({
  required List<CargoModel> newest,
  required List<CargoModel> promoted,
  required DateTime now,
  int pageSize = kCargoFirstPage,
}) {
  final byId = <String, CargoModel>{};
  for (final c in [...newest, ...promoted]) {
    byId.putIfAbsent(c.id, () => c);
  }
  final all = byId.values.toList();
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  // Server order: created_at desc, nulls last; equal times keep their order.
  final pos = {for (var i = 0; i < all.length; i++) all[i].id: i};
  all.sort((a, b) {
    final ca = a.createdAt, cb = b.createdAt;
    if (ca == null && cb == null) return pos[a.id]!.compareTo(pos[b.id]!);
    if (ca == null) return 1;
    if (cb == null) return -1;
    final d = cb.compareTo(ca);
    return d != 0 ? d : pos[a.id]!.compareTo(pos[b.id]!);
  });
  final complete = newest.length < pageSize;
  DateTime? cutoff;
  if (!complete) {
    cutoff = newest.last.createdAt ?? epoch;
  }
  return (loads: [for (final c in all) if (c.isListedOn(now)) c], complete: complete, cutoff: cutoff);
}

/// The rows of [part] that are already final: all rows when complete,
/// otherwise the rows before the first plain load that a load older than
/// the first page could still come before.
List<List<LoadCell>> stableFirstRows(CargoFeedPart part, {required int columns, DateTime? now, int? rotation}) {
  final t = now ?? DateTime.now();
  final cols = columns < 1 ? 1 : columns;
  final flow = buildLoadFlow(part.loads, columns: cols, now: t, rotation: rotation);
  var keep = flow.length;
  if (!part.complete) {
    final cutoff = part.cutoff ?? DateTime.fromMillisecondsSinceEpoch(0);
    keep = 0;
    for (var i = 0; i < flow.length; i++) {
      final cell = flow[i];
      final c = part.loads[cell.index];
      // A normal (not VIP / Premium) load with no later lift than the page's
      // oldest: an unseen older load could stand before it → stop here.
      if (!cell.vip && !c.liftedAt(t).isAfter(cutoff)) break;
      keep = i + 1;
    }
    // Whole rows only (the full feed may fill a half row differently).
    keep -= keep % cols;
  }
  final cut = flow.sublist(0, keep);
  return [for (var i = 0; i < cut.length; i += cols) cut.sublist(i, (i + cols).clamp(0, cut.length))];
}

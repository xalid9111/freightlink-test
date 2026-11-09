import '../../../models/cargo_model.dart';
import 'vip_rows.dart';

/// Yüklər page by page from the server (owner, 09.11.2026, SQL 0109,
/// "Turbo.az kimi"): the phone no longer downloads every open load.
///
/// * [promoted] — every load with a running VIP / Premium (few; the
///   chessboard needs all of them), newest first, as the app always got
///   them (cargo_feed_promoted);
/// * [normal] — the other loads, a page at a time, in the order the app
///   always put them: latest lift first, then newest (cargo_feed_page);
/// * [count] — how many loads are listed (cargo_feed_count).
///
/// The rows are built with the same buildLoadFlow as before; only rows that
/// can no longer change are shown until the last page is here.
const kCargoPageSize = 20;

class CargoFeedState {
  final List<CargoModel> promoted;
  final List<CargoModel> normal;
  final int? count;
  // The last page has come (fewer than a page).
  final bool complete;
  final bool loadingMore;
  // The first answer is here.
  final bool ready;
  final Object? error;
  // SQL 0109 not run yet: the page uses the old full feed instead.
  final bool legacy;

  const CargoFeedState({
    this.promoted = const [],
    this.normal = const [],
    this.count,
    this.complete = false,
    this.loadingMore = false,
    this.ready = false,
    this.error,
    this.legacy = false,
  });

  /// The order the app always got the loads in: promoted, then the pages.
  List<CargoModel> get loads => [...promoted, ...normal];

  CargoFeedState copyWith({
    List<CargoModel>? promoted,
    List<CargoModel>? normal,
    int? count,
    bool? complete,
    bool? loadingMore,
    bool? ready,
    Object? error,
    bool clearError = false,
    bool? legacy,
  }) =>
      CargoFeedState(
        promoted: promoted ?? this.promoted,
        normal: normal ?? this.normal,
        count: count ?? this.count,
        complete: complete ?? this.complete,
        loadingMore: loadingMore ?? this.loadingMore,
        ready: ready ?? this.ready,
        error: clearError ? null : (error ?? this.error),
        legacy: legacy ?? this.legacy,
      );
}

/// Adds a page to the loads already here (each load once, server order).
List<CargoModel> appendPage(List<CargoModel> have, List<CargoModel> page) {
  final seen = {for (final c in have) c.id};
  return [...have, for (final c in page) if (seen.add(c.id)) c];
}

/// The rows of [loads] (promoted first, then the pages so far) that are
/// already final. While pages are still to come, the chessboard stops where
/// it would put a VIP only because the plain loads ran out (more of them
/// are on their way); whole rows only.
List<List<LoadCell>> pagedRows(List<CargoModel> loads, {required bool complete, required int columns, DateTime? now, int? rotation}) {
  final t = now ?? DateTime.now();
  final cols = columns < 1 ? 1 : columns;
  final flow = buildLoadFlow(loads, columns: cols, now: t, rotation: rotation);
  var keep = flow.length;
  if (!complete) {
    final premiumCount = [for (final c in loads) if (c.isPremiumAt(t)) c].length;
    keep = 0;
    for (var i = 0; i < flow.length; i++) {
      if (i >= premiumCount) {
        final pos = i - premiumCount;
        final wantVip = ((pos ~/ cols) + (pos % cols)).isOdd;
        // A VIP where a plain load belongs: the plain loads ran out here.
        if (flow[i].vip && !wantVip) break;
      }
      keep = i + 1;
    }
    keep -= keep % cols;
  }
  final cut = flow.sublist(0, keep);
  return [for (var i = 0; i < cut.length; i += cols) cut.sublist(i, (i + cols).clamp(0, cut.length))];
}

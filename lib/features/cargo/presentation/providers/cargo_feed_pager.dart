import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../models/cargo_model.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/cargo_feed_prefetch.dart';
import '../../domain/cargo_feed_pages.dart';
import '../../domain/cargo_repository.dart';
import 'cargo_providers.dart';

/// The SQL 0109 functions are not on the server yet (the owner runs the
/// SQL by hand): the Loads page then keeps the old full feed.
bool isMissingFeedFunction(Object e) {
  final code = e is AppException ? e.code : null;
  final text = '$e';
  return code == 'PGRST202' || code == '42883' || (text.contains('cargo_feed_') && text.contains('function'));
}

/// Yüklər page by page (owner, 09.11.2026, SQL 0109): the promoted loads,
/// the first page and the counter at once; the next page when the end of
/// the list comes near (the Loads page asks for it).
class CargoFeedPager extends StateNotifier<CargoFeedState> {
  CargoFeedPager(this._repo, {String? Function()? userId}) : super(const CargoFeedState()) {
    _start(userId);
  }

  final CargoRepository _repo;
  DateTime _failedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _start(String? Function()? userId) async {
    try {
      // The same requests already sent during start-up (main.dart), once.
      final pre = userId == null ? null : CargoFeedPrefetch.takePages(userId);
      final parts = await Future.wait<Object>([
        pre?.promoted ?? _repo.fetchFeedPromoted(),
        pre?.page ?? _repo.fetchFeedPage(),
        pre?.count ?? _repo.fetchFeedCount(),
      ]);
      if (!mounted) return;
      final page = parts[1] as List<CargoModel>;
      state = state.copyWith(
        promoted: parts[0] as List<CargoModel>,
        normal: page,
        count: parts[2] as int,
        complete: page.length < kCargoPageSize,
        ready: true,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = isMissingFeedFunction(e) ? state.copyWith(legacy: true, ready: true) : state.copyWith(error: e, ready: true);
    }
  }

  /// The next page (nothing when everything is here or one is on its way).
  /// A failed page is tried again a little later, never in a tight loop.
  Future<void> loadMore() async {
    final s = state;
    if (!s.ready || s.legacy || s.complete || s.loadingMore || s.normal.isEmpty) return;
    if (DateTime.now().difference(_failedAt) < const Duration(seconds: 3)) return;
    state = s.copyWith(loadingMore: true);
    try {
      final page = await _repo.fetchFeedPage(after: s.normal.last);
      if (!mounted) return;
      state = state.copyWith(normal: appendPage(state.normal, page), complete: page.length < kCargoPageSize, loadingMore: false);
    } catch (_) {
      if (!mounted) return;
      _failedAt = DateTime.now();
      state = state.copyWith(loadingMore: false);
      // Shown again in 3 s → the spinner at the end asks once more.
      Timer(const Duration(seconds: 3), () {
        if (mounted) state = state.copyWith();
      });
    }
  }
}

final cargoFeedPagerProvider = StateNotifierProvider<CargoFeedPager, CargoFeedState>((ref) {
  ref.watch(currentUserIdProvider); // a new account starts again
  return CargoFeedPager(ref.watch(cargoRepositoryProvider), userId: sessionUserId);
});

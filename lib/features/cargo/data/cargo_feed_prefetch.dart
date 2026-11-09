import '../../../models/cargo_model.dart';
import '../domain/cargo_repository.dart';

typedef CargoFeedStartParts = ({Future<List<CargoModel>> promoted, Future<List<CargoModel>> page, Future<int> count});

/// Faster first Yüklər page (owner, 08.11.2026): the Loads page's first
/// requests are sent while the app is still starting (main.dart, right
/// after Supabase is ready) instead of after the first frame. Since
/// 09.11.2026 (SQL 0109) these are the small page-by-page requests
/// (CargoFeedPager takes them once), never the whole feed.
///
/// It is used only for the account it was asked for and only once, shortly
/// after the start; any later refresh (pull, a new load) asks the server
/// again as before.
class CargoFeedPrefetch {
  CargoFeedPrefetch._();

  static const maxAge = Duration(seconds: 45);

  static CargoFeedStartParts? _pages;
  static String? _userId;
  static DateTime? _at;

  /// [userId] = the account the request is sent with (null: a visitor).
  /// Page by page (owner, 09.11.2026, SQL 0109): the promoted loads, the
  /// first page and the counter leave together — small answers, never the
  /// whole feed.
  static void start(CargoRepository repo, String? userId) {
    final parts = (promoted: repo.fetchFeedPromoted(), page: repo.fetchFeedPage(), count: repo.fetchFeedCount());
    // An error is shown by the page that uses it (the usual retry), never
    // reported as an "unhandled" one when no page asks for it.
    for (final f in <Future<Object>>[parts.promoted, parts.page, parts.count]) {
      f.then((_) {}, onError: (_) {});
    }
    _pages = parts;
    _userId = userId;
    _at = DateTime.now();
  }

  /// The started requests for [userId], once; null when there are none (not
  /// started, already taken, too old or asked for another account).
  static CargoFeedStartParts? takePages(String? Function() userId) {
    final p = _pages;
    if (p == null) return null;
    _pages = null;
    final fresh = _at != null && DateTime.now().difference(_at!) < maxAge;
    return fresh && userId() == _userId ? p : null;
  }

  /// Should the start-up send it? Only when the app opens on Yüklər (the
  /// bare address or /cargo), never for a deep link to another page.
  static bool opensOnLoads(Uri address) {
    final route = address.fragment.isNotEmpty ? address.fragment.split('?').first : '';
    return route.isEmpty || route == '/' || route == '/cargo';
  }
}

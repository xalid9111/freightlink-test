import '../../../models/cargo_model.dart';
import '../domain/cargo_feed_first.dart';
import '../domain/cargo_repository.dart';

/// Faster first Yüklər page (owner, 08.11.2026): the open-loads request is
/// sent while the app is still starting (main.dart, right after Supabase is
/// ready) instead of after the first frame. The marketplace provider takes
/// this answer once — the very same query (fetchMarketplace: same columns,
/// filters, order, limit), so the list, VIP / Premium order and filters are
/// unchanged; only its waiting time overlaps the start-up.
///
/// It is used only for the account it was asked for and only once, shortly
/// after the start; any later refresh (pull, a new load) asks the server
/// again as before.
class CargoFeedPrefetch {
  CargoFeedPrefetch._();

  static const maxAge = Duration(seconds: 45);

  static Future<List<CargoModel>>? _future;
  static Future<CargoFeedPart>? _first;
  static String? _userId;
  static DateTime? _at;

  /// [userId] = the account the request is sent with (null: a visitor).
  /// Staged (owner, 09.11.2026): the small first part and the full feed
  /// leave together; the first rows show as soon as the small one is here.
  static void start(CargoRepository repo, String? userId) {
    final first = repo.fetchMarketplaceFirst();
    final f = repo.fetchMarketplace();
    // An error is shown by the page that uses it (the usual retry), never
    // reported as an "unhandled" one when no page asks for it.
    first.then((_) {}, onError: (_) {});
    f.then((_) {}, onError: (_) {});
    _first = first;
    _future = f;
    _userId = userId;
    _at = DateTime.now();
  }

  /// The started first part for [userId], once (as [take]).
  static Future<CargoFeedPart>? takeFirst(String? Function() userId) {
    final f = _first;
    if (f == null) return null;
    _first = null;
    final fresh = _at != null && DateTime.now().difference(_at!) < maxAge;
    return fresh && userId() == _userId ? f : null;
  }

  /// The started request for [userId], once; null when there is none (not
  /// started, already taken, too old or asked for another account).
  static Future<List<CargoModel>>? take(String? Function() userId) {
    final f = _future;
    if (f == null) return null;
    _future = null;
    final fresh = _at != null && DateTime.now().difference(_at!) < maxAge;
    return fresh && userId() == _userId ? f : null;
  }

  /// Should the start-up send it? Only when the app opens on Yüklər (the
  /// bare address or /cargo), never for a deep link to another page.
  static bool opensOnLoads(Uri address) {
    final route = address.fragment.isNotEmpty ? address.fragment.split('?').first : '';
    return route.isEmpty || route == '/' || route == '/cargo';
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Adapts any Stream (here: Supabase's auth state stream) into the
/// Listenable that GoRouter's `refreshListenable` expects, so a login
/// or logout immediately re-evaluates every route's `redirect`.
/// Standard go_router pattern — see the package's own docs/examples.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

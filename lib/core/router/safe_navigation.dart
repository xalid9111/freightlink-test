import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Drops a repeated navigation to the same place that arrives right after
/// the first one. On iPhone Safari a quick double tap (or a tap that the
/// browser delivers twice) used to push the same page twice — going back
/// then showed the same page again ("ikiqat keçid").
class NavDebounce {
  NavDebounce({this.window = const Duration(milliseconds: 800)});
  final Duration window;
  String? _location;
  DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);

  /// True when navigating to [location] at [now] should happen.
  bool allow(String location, DateTime now) {
    if (location == _location && now.difference(_at) < window) return false;
    _location = location;
    _at = now;
    return true;
  }
}

final NavDebounce _pushGuard = NavDebounce();

extension PushOnce on BuildContext {
  /// Same as go_router's `push(location)`, but one tap = one page.
  Future<T?> pushOnce<T extends Object?>(String location, {Object? extra}) {
    if (!_pushGuard.allow(location, DateTime.now())) return Future<T?>.value(null);
    return GoRouter.of(this).push<T>(location, extra: extra);
  }
}

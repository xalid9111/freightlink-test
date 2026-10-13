import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/countries.dart';
import '../../../../models/cargo_model.dart';

/// Route filter on the Loads home screen: from-country → to-country
/// (ISO codes; null = any). Filtering is instant and client-side over the
/// already-loaded open marketplace.
class RouteFilter {
  final String? from;
  final String? to;
  const RouteFilter({this.from, this.to});

  bool get isActive => from != null || to != null;

  /// "AZ>RU", "AZ>*", "*>RU" — also the storage key for saved routes.
  String get key => '${from ?? '*'}>${to ?? '*'}';

  static RouteFilter? fromKey(String k) {
    final parts = k.split('>');
    if (parts.length != 2) return null;
    String? norm(String v) => v == '*' || v.isEmpty ? null : v;
    return RouteFilter(from: norm(parts[0]), to: norm(parts[1]));
  }

  static String _code(String country) => Countries.find(country)?.code ?? Countries.normalize(country);

  bool matches(CargoModel c) =>
      (from == null || _code(c.pickupCountry) == from) && (to == null || _code(c.destinationCountry) == to);
}

final routeFilterProvider = StateProvider<RouteFilter>((ref) => const RouteFilter());

/// "My routes": routes the user starred, kept on this device
/// (shared_preferences — localStorage on web), shown as one-tap chips.
class SavedRoutesNotifier extends Notifier<List<String>> {
  static const _prefsKey = 'saved_routes_v1';

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getStringList(_prefsKey) ?? const [];
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, state);
    } catch (_) {}
  }

  bool contains(String key) => state.contains(key);

  Future<void> add(String key) async {
    if (state.contains(key)) return;
    state = [...state, key];
    await _save();
  }

  Future<void> remove(String key) async {
    state = state.where((k) => k != key).toList();
    await _save();
  }
}

final savedRoutesProvider = NotifierProvider<SavedRoutesNotifier, List<String>>(SavedRoutesNotifier.new);

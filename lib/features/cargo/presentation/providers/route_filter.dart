import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/cities.dart';
import '../../../../core/constants/countries.dart';
import '../../../../models/cargo_model.dart';

/// Route filter on the Loads home screen: from → to, each a country (ISO
/// code; null = any) and, inside it, optionally one city or district
/// (owner, 24.10.2026; null = the whole country). Filtering is instant and
/// client-side over the already-loaded open marketplace.
class RouteFilter {
  final String? from;
  final String? to;
  /// City / district inside [from] / [to] (English catalogue name, or the
  /// name as stored on loads); null = the whole country.
  final String? fromCity;
  final String? toCity;
  const RouteFilter({this.from, this.to, this.fromCity, this.toCity});

  bool get isActive => from != null || to != null;

  /// From and to exchanged (⇅), cities included.
  RouteFilter get swapped => RouteFilter(from: to, to: from, fromCity: toCity, toCity: fromCity);

  /// "AZ>RU", "AZ>*", "*>RU", "AZ/Baku>RU" — also the storage key for
  /// saved routes (keys saved before cities existed stay valid).
  String get key => '${_part(from, fromCity)}>${_part(to, toCity)}';

  static String _part(String? code, String? city) =>
      code == null ? '*' : (city == null ? code : '$code/$city');

  static RouteFilter? fromKey(String k) {
    final parts = k.split('>');
    if (parts.length != 2) return null;
    (String?, String?) side(String v) {
      if (v == '*' || v.isEmpty) return (null, null);
      final i = v.indexOf('/');
      if (i < 0) return (v, null);
      final city = v.substring(i + 1);
      return (v.substring(0, i), city.isEmpty ? null : city);
    }

    final (from, fromCity) = side(parts[0]);
    final (to, toCity) = side(parts[1]);
    return RouteFilter(from: from, to: to, fromCity: fromCity, toCity: toCity);
  }

  static String _code(String country) => Countries.find(country)?.code ?? Countries.normalize(country);

  /// One city written in any language / spelling ("Bakı", "Baku").
  static String cityKey(String city) => Countries.normalize(Cities.find(city)?.en ?? city);

  static bool _side(String? code, String? city, String country, String loadCity) =>
      (code == null || _code(country) == code) && (city == null || cityKey(loadCity) == cityKey(city));

  bool matches(CargoModel c) =>
      _side(from, fromCity, c.pickupCountry, c.pickupCity) && _side(to, toCity, c.destinationCountry, c.destinationCity);
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

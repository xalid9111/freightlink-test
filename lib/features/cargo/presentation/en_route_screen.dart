import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../models/cargo_model.dart';
import '../../../services/geo_service.dart';
import '../domain/cargo_categories.dart';
import '../domain/en_route.dart';
import 'providers/cargo_providers.dart';
import 'widgets/cargo_card.dart';

/// "Yolüstü yük" (owner, 21.10.2026): the carrier picks where the truck
/// starts and where it goes; the app draws the real road route (OSRM) and
/// lists the small loads whose pickup AND delivery lie next to that road,
/// in the driving direction. No road route → nothing is shown (a country
/// match is never presented as "on the way").
class EnRouteScreen extends ConsumerStatefulWidget {
  const EnRouteScreen({super.key});

  @override
  ConsumerState<EnRouteScreen> createState() => _EnRouteScreenState();
}

/// Geocoded "city, country" → point, kept while the app runs.
final Map<String, LatLng?> _pointCache = {};

class _EnRouteScreenState extends ConsumerState<EnRouteScreen> {
  PickedPlace? _from, _to;
  int _radius = kEnRouteDefaultRadius;
  bool _busy = false;
  String? _messageKey;
  Map<String, String> _messageArgs = const {};
  List<EnRouteMatch<CargoModel>>? _found;
  int _skipped = 0;

  Future<void> _pick({required bool from}) async {
    final s = ref.read(stringsProvider);
    final picked = await showModalBottomSheet<PickedPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CityPickerSheet(
        languageCode: ref.read(currentLocaleProvider).languageCode,
        strings: s,
        title: s.t(from ? 'route_from' : 'route_to'),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
      _found = null;
      _messageKey = null;
    });
  }

  Future<LatLng?> _point(GeoService geo, String city, String country) async {
    final key = '${city.trim()}, ${country.trim()}'.toLowerCase();
    if (_pointCache.containsKey(key)) return _pointCache[key];
    // Nominatim asks for at most one request per second.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final p = await geo.geocode('$city, $country');
    if (p != null) _pointCache[key] = p;
    return p;
  }

  Future<void> _search() async {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    setState(() {
      _busy = true;
      _found = null;
      _messageKey = null;
      _skipped = 0;
    });
    final geo = ref.read(geoServiceProvider);
    try {
      final a = await _point(geo, from.city, from.country);
      final b = await _point(geo, to.city, to.country);
      if (a == null || b == null) return _show('enroute_no_route');
      final route = await geo.route(a, b);
      if (!route.isRoad) return _show('enroute_no_route');

      // Small loads from the one load pool (server-filtered, 0055).
      List<CargoModel> small;
      try {
        small = await ref.read(cargoRepositoryProvider).fetchByCategory(loadSize: kLoadSizeSmall);
      } on AppException {
        small = const [];
      }
      final withPoints = <({CargoModel load, LatLng pickup, LatLng drop})>[];
      var skipped = 0;
      for (final c in small) {
        final p = (c.pickupLatitude != null && c.pickupLongitude != null)
            ? LatLng(c.pickupLatitude!, c.pickupLongitude!)
            : await _point(geo, c.pickupCity, c.pickupCountry);
        final d = (c.destinationLatitude != null && c.destinationLongitude != null)
            ? LatLng(c.destinationLatitude!, c.destinationLongitude!)
            : await _point(geo, c.destinationCity, c.destinationCountry);
        if (p == null || d == null) {
          skipped++;
          continue;
        }
        withPoints.add((load: c, pickup: p, drop: d));
      }
      final found = findEnRoute<CargoModel>(route: route.points, loads: withPoints, maxOffKm: _radius.toDouble());
      if (!mounted) return;
      setState(() {
        _found = found;
        _skipped = skipped;
        _busy = false;
      });
    } catch (_) {
      _show('enroute_no_route');
    }
  }

  void _show(String key, [Map<String, String> args = const {}]) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _messageKey = key;
      _messageArgs = args;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final found = _found;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('enroute_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(s.t('enroute_sub'), style: TextStyle(color: AppColors.textSoft)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _placeButton(s, lang, from: true)),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(child: _placeButton(s, lang, from: false)),
          ]),
          const SizedBox(height: 12),
          Text(s.t('enroute_radius'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final r in kEnRouteRadii)
              ChoiceChip(
                key: ValueKey('enroute-r$r'),
                label: Text('$r km'),
                selected: _radius == r,
                onSelected: _busy ? null : (_) => setState(() => _radius = r),
              ),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('enroute-search'),
            onPressed: _busy || _from == null || _to == null ? null : _search,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.alt_route),
            label: Text(s.t('enroute_search')),
          ),
          const SizedBox(height: 8),
          Text(s.t('enroute_note'), style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
          if (_messageKey != null) ...[
            const SizedBox(height: 16),
            _Notice(text: s.t(_messageKey!, _messageArgs)),
          ],
          if (found != null) ...[
            const SizedBox(height: 16),
            Text(found.isEmpty ? s.t('enroute_none') : s.t('enroute_found', {'n': '${found.length}'}),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (_skipped > 0) ...[
              const SizedBox(height: 4),
              Text(s.t('enroute_skipped', {'n': '$_skipped'}), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
            ],
            const SizedBox(height: 10),
            for (final m in found) ...[
              CargoCard(
                cargo: m.load,
                strings: s,
                compact: true,
                onTap: () => context.pushOnce('/load/${m.load.id}'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
                child: Text(
                  s.t('enroute_off', {'a': m.pickupOffKm.round().toString(), 'b': m.dropOffKm.round().toString()}),
                  style: TextStyle(fontSize: 12, color: AppColors.route, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _placeButton(AppStrings s, String lang, {required bool from}) {
    final p = from ? _from : _to;
    return InkWell(
      key: ValueKey(from ? 'enroute-from' : 'enroute-to'),
      borderRadius: BorderRadius.circular(12),
      onTap: _busy ? null : () => _pick(from: from),
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p != null ? AppColors.accent : AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(s.t(from ? 'route_from' : 'route_to'), style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
          Text(p == null ? s.t('enroute_pick_city') : '${p.flag} ${p.cityLabel(lang)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w400, color: AppColors.text)),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.urgentBg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.info_outline, color: AppColors.urgentFg),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: AppColors.urgentFg))),
      ]),
    );
  }
}

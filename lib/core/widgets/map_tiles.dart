import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../autofix/autofix.dart';

/// Map pictures ("tiles") for every map in the app.
///
/// OpenStreetMap first, as before. On some computers / networks its tiles
/// do not load and the map stayed empty; then the app switches — once,
/// for this visit — to a second tile server (CARTO, same OpenStreetMap
/// data, similar look) and notes it in Admin → AutoFix.
class MapTiles {
  MapTiles._();

  static const osm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const backup = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  static const userAgent = 'az.freightlink.app';

  /// True after OpenStreetMap failed on this device.
  static final ValueNotifier<bool> useBackup = ValueNotifier(false);
  static final TileFailureCounter _osmFailures = TileFailureCounter();

  static void onTileError(TileImage tile, Object error, StackTrace? stack) {
    if (useBackup.value) return;
    if (_osmFailures.add(DateTime.now())) {
      useBackup.value = true;
      AutoFix.instance.capture('Map tiles: tile.openstreetmap.org failed, switched to backup ($error)', stack,
          source: 'map.tiles', forceKind: 'network');
    }
  }
}

/// Switch to the backup after [threshold] failed tiles within [window]
/// (a map screen asks for 12–40 tiles at once, so a blocked server fails
/// many quickly; one lost tile on a weak connection does not switch).
class TileFailureCounter {
  final int threshold;
  final Duration window;
  final List<DateTime> _times = [];
  TileFailureCounter({this.threshold = 4, this.window = const Duration(seconds: 20)});

  /// Records a failure at [now]; true when the threshold is reached.
  bool add(DateTime now) {
    _times
      ..add(now)
      ..removeWhere((t) => now.difference(t) > window);
    return _times.length >= threshold;
  }
}

/// The app's tile layer: OpenStreetMap, or the backup when it fails here.
class AppTileLayer extends StatelessWidget {
  const AppTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MapTiles.useBackup,
      builder: (context, backup, _) => TileLayer(
        key: ValueKey(backup),
        urlTemplate: backup ? MapTiles.backup : MapTiles.osm,
        subdomains: const ['a', 'b', 'c', 'd'],
        userAgentPackageName: MapTiles.userAgent,
        errorTileCallback: backup ? null : MapTiles.onTileError,
      ),
    );
  }
}

/// Map credit line: OpenStreetMap, plus CARTO while its tiles are shown.
class AppMapAttribution extends StatelessWidget {
  const AppMapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MapTiles.useBackup,
      builder: (context, backup, _) => RichAttributionWidget(
        key: ValueKey(backup),
        attributions: [
          const TextSourceAttribution('OpenStreetMap contributors'),
          if (backup) const TextSourceAttribution('CARTO'),
        ],
      ),
    );
  }
}

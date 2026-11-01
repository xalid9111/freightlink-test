import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../services/here_wego.dart';
import '../../../../services/navigation_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../services/presentation/services_providers.dart' show userLocationProvider;

/// A location inside a chat message. Locations travel as plain text
/// containing a map link — e.g. "📍 https://maps.google.com/?q=40.4,49.8"
/// sent by the 📎 → "My location" option, or a Google Maps / Waze /
/// Apple Maps link pasted from WhatsApp or anywhere else — so no
/// database change is needed. The bubble recognizes the link and shows
/// a location card with a "navigate" choice.
class ChatLocation {
  final String url;
  final double? lat;
  final double? lng;

  /// The start of a route link (Google Maps "dir" link, saddr= / origin=),
  /// when the link has one — used by HERE WeGo Pro.
  final double? fromLat;
  final double? fromLng;
  const ChatLocation({required this.url, this.lat, this.lng, this.fromLat, this.fromLng});

  bool get hasCoords => lat != null && lng != null;
  bool get hasOrigin => fromLat != null && fromLng != null;

  static final _urlRe = RegExp(r'https?://[^\s]+', caseSensitive: false);
  static final _hostRe = RegExp(
    r'(maps\.google\.|google\.[a-z.]+/maps|goo\.gl/maps|maps\.app\.goo\.gl|waze\.com|maps\.apple\.com|yandex\.[a-z]+/maps)',
    caseSensitive: false,
  );
  static final _qRe = RegExp(
    r'[?&](?:q|query|ll|destination|daddr|sll)=(-?\d{1,3}\.\d+)(?:,|%2C)\s*(-?\d{1,3}\.\d+)',
    caseSensitive: false,
  );
  static final _atRe = RegExp(r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)');
  static final _fromRe = RegExp(
    r'[?&](?:saddr|origin)=(-?\d{1,3}\.\d+)(?:,|%2C)\s*(-?\d{1,3}\.\d+)',
    caseSensitive: false,
  );
  // "…/maps/dir/40.1,49.2/40.4,49.8/@…": the stops of a Google route link.
  static final _dirStopRe = RegExp(r'/(-?\d{1,3}\.\d+),\+?(-?\d{1,3}\.\d+)(?=/|$|\?)');

  static bool _ok(double? lat, double? lng) => lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180;

  /// The first map link in [text], or null if there is none.
  static ChatLocation? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    for (final m in _urlRe.allMatches(text)) {
      final url = m.group(0)!;
      if (!_hostRe.hasMatch(url)) continue;
      double? fromLat, fromLng;
      final f = _fromRe.firstMatch(url);
      if (f != null && _ok(double.tryParse(f.group(1)!), double.tryParse(f.group(2)!))) {
        fromLat = double.parse(f.group(1)!);
        fromLng = double.parse(f.group(2)!);
      }
      // A Google route link: the last stop is the destination, the first
      // one (when there are two or more) the start.
      final dirAt = url.indexOf('/dir/');
      if (dirAt >= 0 && _qRe.firstMatch(url) == null) {
        final path = url.substring(dirAt, url.contains('/@') ? url.indexOf('/@') : url.length);
        final stops = [
          for (final d in _dirStopRe.allMatches(path))
            if (_ok(double.tryParse(d.group(1)!), double.tryParse(d.group(2)!))) (double.parse(d.group(1)!), double.parse(d.group(2)!)),
        ];
        if (stops.isNotEmpty) {
          if (stops.length >= 2 && fromLat == null) (fromLat, fromLng) = stops.first;
          return ChatLocation(url: url, lat: stops.last.$1, lng: stops.last.$2, fromLat: fromLat, fromLng: fromLng);
        }
      }
      final c = _qRe.firstMatch(url) ?? _atRe.firstMatch(url);
      if (c != null) {
        final lat = double.tryParse(c.group(1)!);
        final lng = double.tryParse(c.group(2)!);
        if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
          return ChatLocation(url: url, lat: lat, lng: lng, fromLat: fromLat, fromLng: fromLng);
        }
      }
      // Short links (maps.app.goo.gl/...) carry no coordinates; they can
      // still be opened as-is.
      return ChatLocation(url: url);
    }
    return null;
  }

  /// Message text for sharing a point.
  static String messageFor(double lat, double lng) => '📍 https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
}

/// Lets the driver pick the navigation app (Google Maps, Waze, Sygic,
/// Apple Maps on iPhone) for a point.
Future<void> showNavigationPicker(BuildContext context, AppStrings strings, ChatLocation loc) async {
  String label(NavApp a) => switch (a) {
        NavApp.googleMaps => strings.t('nav_sheet_google'),
        NavApp.appleMaps => strings.t('nav_sheet_apple'),
        NavApp.waze => strings.t('nav_sheet_waze'),
        NavApp.sygic => 'Sygic',
      };
  IconData icon(NavApp a) => switch (a) {
        NavApp.googleMaps => Icons.map_outlined,
        NavApp.appleMaps => Icons.map,
        NavApp.waze => Icons.navigation_outlined,
        NavApp.sygic => Icons.directions_car_outlined,
      };

  // HERE WeGo Pro: the start (GPS, when the link has none) and the
  // truck's measurements are fetched while the list is open, so the tap
  // opens HERE at once.
  final here = _HerePrep.start(context, loc);

  await showModalBottomSheet<void>(
    context: context,
    // Over the bottom bar, so the last rows are never hidden.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(strings.t('nav_sheet_title'), style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (loc.hasCoords)
              for (final app in navigationService.availableApps())
                ListTile(
                  leading: Icon(icon(app), color: AppColors.accent),
                  title: Text(label(app)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await navigationService.startNavigation(app, lat: loc.lat!, lng: loc.lng!);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(strings.t('chat_nav_app_missing', {'app': label(app)}))),
                      );
                    }
                  },
                ),
            ListTile(
              key: const ValueKey('nav-here'),
              leading: Icon(Icons.local_shipping_outlined, color: AppColors.accent),
              title: const Text('HERE WeGo Pro'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final msg = await here.open((link) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    duration: const Duration(seconds: 10),
                    content: Text(strings.t('nav_here_ready')),
                    action: SnackBarAction(
                      label: strings.t('nav_here_open'),
                      onPressed: () => launchUrl(link, mode: LaunchMode.externalApplication),
                    ),
                  ));
                });
                if (msg != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t(msg))));
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.open_in_new, color: AppColors.textSoft),
              title: Text(strings.t('chat_location_open_link')),
              onTap: () {
                Navigator.of(ctx).pop();
                launchUrl(Uri.parse(loc.url), mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(title: Text(strings.t('nav_sheet_cancel')), onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    ),
  );
}

/// Gets HERE WeGo Pro ready: the start point (from the link, else the
/// device's own position) and the user's truck measurements. iPhone Safari
/// opens a link only right after a tap, so when everything is ready HERE
/// opens at once; otherwise, once ready, a "Marşrut hazırdır — HERE-də aç"
/// note gives the tap that opens it.
class _HerePrep {
  final ChatLocation loc;
  ProviderContainer? _c;
  LatLng? _from;
  TruckDims? _truck;
  bool _truckDone = false;
  Future<void>? _truckLoad;
  _HerePrep(this.loc);

  static _HerePrep start(BuildContext context, ChatLocation loc) {
    final p = _HerePrep(loc);
    if (!loc.hasCoords) return p;
    try {
      p._c = ProviderScope.containerOf(context, listen: false);
    } catch (_) {}
    final c = p._c;
    // The link's own start, else a position the app already knows (no
    // permission question just for opening the list).
    p._from = loc.hasOrigin ? LatLng(loc.fromLat!, loc.fromLng!) : c?.read(userLocationProvider).point;
    final uid = c?.read(currentUserIdProvider);
    p._truckLoad = (uid == null ? Future<TruckDims?>.value(null) : myTruckDims(SupabaseConfig.client, uid))
        .then((t) => p._truck = t)
        .catchError((_) => null)
        .whenComplete(() => p._truckDone = true);
    return p;
  }

  Uri _link() => hereWeGoRouteLink(fromLat: _from!.latitude, fromLng: _from!.longitude, toLat: loc.lat!, toLng: loc.lng!, truck: _truck);

  /// Opens HERE now when ready (returns null), or calls [onReady] with the
  /// link once ready; a message key when it cannot be opened.
  Future<String?> open(void Function(Uri link) onReady) async {
    if (!loc.hasCoords) return 'nav_here_no_dest';
    if (_from != null && _truckDone) {
      launchUrl(_link(), mode: LaunchMode.externalApplication);
      return null;
    }
    await _truckLoad;
    if (_from == null) {
      final c = _c;
      _from = c == null ? null : await c.read(userLocationProvider.notifier).locate(allowApprox: false);
    }
    if (_from == null) return 'nav_here_no_start';
    onReady(_link());
    return null;
  }
}

/// Location card shown inside a chat bubble.
class LocationCard extends StatelessWidget {
  final ChatLocation location;
  final bool isMine;
  final AppStrings strings;
  const LocationCard({super.key, required this.location, required this.isMine, required this.strings});

  @override
  Widget build(BuildContext context) {
    final fg = isMine ? ChatColors.text : AppColors.text;
    final sub = isMine ? ChatColors.text.withValues(alpha: 0.8) : AppColors.textSoft;
    return InkWell(
      onTap: () => showNavigationPicker(context, strings, location),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (isMine ? Colors.black : AppColors.hero).withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.routeSoft, shape: BoxShape.circle),
              child: Icon(Icons.location_on, color: AppColors.route),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.t('chat_location'), style: TextStyle(color: fg, fontWeight: FontWeight.w400)),
                  Text(
                    location.hasCoords
                        ? '${location.lat!.toStringAsFixed(5)}, ${location.lng!.toStringAsFixed(5)}'
                        : strings.t('chat_location_open_link'),
                    style: TextStyle(color: sub, fontSize: 11.5),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.navigation, size: 14, color: fg),
                      const SizedBox(width: 4),
                      Text(strings.t('chat_location_navigate'),
                          style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

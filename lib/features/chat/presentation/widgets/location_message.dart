import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/navigation_service.dart';

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
  const ChatLocation({required this.url, this.lat, this.lng});

  bool get hasCoords => lat != null && lng != null;

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

  /// The first map link in [text], or null if there is none.
  static ChatLocation? parse(String? text) {
    if (text == null || text.isEmpty) return null;
    for (final m in _urlRe.allMatches(text)) {
      final url = m.group(0)!;
      if (!_hostRe.hasMatch(url)) continue;
      final c = _qRe.firstMatch(url) ?? _atRe.firstMatch(url);
      if (c != null) {
        final lat = double.tryParse(c.group(1)!);
        final lng = double.tryParse(c.group(2)!);
        if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
          return ChatLocation(url: url, lat: lat, lng: lng);
        }
      }
      // Short links (maps.app.goo.gl/...) carry no coordinates; they can
      // still be opened as-is.
      return ChatLocation(url: url);
    }
    return null;
  }

  /// Message text for sharing a point.
  static String messageFor(double lat, double lng) =>
      '📍 https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
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

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
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
  );
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

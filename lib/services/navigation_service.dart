import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';

/// Opens an EXTERNAL navigation app for a pickup/destination point
/// (brief §10). This deliberately does not build any in-app routing —
/// it hands off to Google Maps / Apple Maps / Waze via their documented
/// URL schemes, which needs no API key or external account.
///
/// Not yet wired to a screen: there is no cargo-detail screen to put a
/// real "Start Navigation" button on yet (that's a later phase). Per
/// "do not fake functionality merely for visual demonstration," this
/// service is implemented and ready to call, not bolted onto an
/// unrelated screen just to have something clickable.
enum NavApp { googleMaps, appleMaps, waze, sygic }

class NavigationService {
  const NavigationService();

  /// Which apps make sense to offer on this platform. Apple Maps only
  /// makes sense on iOS; Google Maps and Waze work as web fallbacks
  /// everywhere (their https:// links open the app if installed, or
  /// the website/store page otherwise).
  ///
  /// Uses `defaultTargetPlatform` (package:flutter/foundation.dart),
  /// NOT dart:io's `Platform` class — dart:io fails to even COMPILE in
  /// code built for Flutter Web (this project's primary target right
  /// now), regardless of any kIsWeb runtime guard around it, because
  /// the failure happens at compile time during library resolution,
  /// not at runtime.
  List<NavApp> availableApps() {
    final apps = <NavApp>[NavApp.googleMaps, NavApp.waze, NavApp.sygic];
    // On the web, defaultTargetPlatform reflects the browser's OS, so
    // iPhone Safari also gets Apple Maps (maps.apple.com opens Maps).
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      apps.add(NavApp.appleMaps);
    }
    return apps;
  }

  Uri _uriFor(NavApp app, {required double lat, required double lng, String? label}) {
    switch (app) {
      case NavApp.googleMaps:
        // Universal link: opens the Google Maps app if installed (iOS
        // and Android both intercept this URL), falls back to the web
        // version otherwise. No API key required for this link form.
        return Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      case NavApp.appleMaps:
        final q = label != null ? '&q=${Uri.encodeComponent(label)}' : '';
        return Uri.parse('https://maps.apple.com/?daddr=$lat,$lng$q');
      case NavApp.waze:
        // Waze's web "directions" page. On iPhone the old waze.com/ul link
        // made Safari jump to the waze:// scheme, which fails with "address
        // is invalid" when opened from the home-screen app or without Waze.
        // This https page opens the Waze app when it is installed and
        // otherwise shows the route on Waze's web map — never an error.
        return Uri.parse('https://www.waze.com/live-map/directions?to=ll.${lat.toStringAsFixed(6)}%2C${lng.toStringAsFixed(6)}&navigate=yes');
      case NavApp.sygic:
        // Sygic's documented app scheme (longitude FIRST). Works when the
        // Sygic app is installed; otherwise launch returns false.
        return Uri.parse('com.sygic.aura://coordinate%7C$lng%7C$lat%7Cdrive');
    }
  }

  /// Launches the chosen app. Returns false if nothing could handle the
  /// link (e.g. no browser/map app at all) so the caller can show a
  /// fallback message instead of failing silently.
  Future<bool> startNavigation(
    NavApp app, {
    required double lat,
    required double lng,
    String? label,
  }) {
    final uri = _uriFor(app, lat: lat, lng: lng, label: label);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

const navigationService = NavigationService();

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/services/navigation_service.dart';

/// Owner, 01.11.2026: Waze and Sygic did not open from Mesajlar / TIRPark /
/// Servislər. Their own app links are opened first, in the same tab.
void main() {
  const s = NavigationService();
  test('Waze: the app link; Sygic: none (universal link instead)', () {
    expect(s.appLinkFor(NavApp.waze, lat: 40.4093, lng: 49.8671), 'waze://?ll=40.409300,49.867100&navigate=yes');
    expect(s.appLinkFor(NavApp.sygic, lat: 40.4093, lng: 49.8671), isNull, reason: 'the old scheme was refused by Safari');
    expect(s.appLinkFor(NavApp.googleMaps, lat: 1, lng: 2), isNull);
    expect(s.appLinkFor(NavApp.appleMaps, lat: 1, lng: 2), isNull);
  });

  test('web links: Waze map when the app does not open; Sygic universal link; Google / Apple unchanged', () {
    expect(s.webLinkFor(NavApp.waze, lat: 40.4093, lng: 49.8671).toString(),
        'https://www.waze.com/live-map/directions?to=ll.40.409300%2C49.867100&navigate=yes');
    expect(s.webLinkFor(NavApp.sygic, lat: 40.4093, lng: 49.8671).toString(), 'https://go.sygic.com/directions?to=40.409300,49.867100',
        reason: 'Sygic universal link: opens the installed app');
    expect(s.webLinkFor(NavApp.googleMaps, lat: 1, lng: 2).toString(), 'https://www.google.com/maps/dir/?api=1&destination=1.0,2.0');
    expect(s.webLinkFor(NavApp.appleMaps, lat: 1, lng: 2).toString(), 'https://maps.apple.com/?daddr=1.0,2.0');
  });

  test('wired: the web build opens the app link in the same tab and watches if the page was left', () {
    final web = File('lib/services/app_link_web.dart').readAsStringSync();
    expect(web, contains('web.window.location.href = link;'));
    expect(web, contains("addEventListener('blur', onLeave)"));
    final svc = File('lib/services/navigation_service.dart').readAsStringSync();
    expect(svc, contains("import 'app_link_stub.dart' if (dart.library.js_interop) 'app_link_web.dart' as app_link;"));
    expect(svc, contains('if (appLink != null && await app_link.openAppLink(appLink)) return true;'));
  });
}

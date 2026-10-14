// GPS result → what the Services map says. Pure logic (no Flutter widgets),
// unit-tested in test/gps_logic_test.dart.
import 'dart:async';

import 'package:geolocator/geolocator.dart';

enum GpsState { idle, locating, ok, denied, unavailable, systemOff }

/// State after asking for the position failed with [error].
/// [permissionNow] = the browser / app permission read right after the
/// failure (null if it could not be read).
///
/// "Permission denied" while the permission itself is granted means the
/// device's own location service is off (e.g. Windows → Privacy →
/// Location): the user DID allow it, so we must not say "not allowed".
GpsState gpsStateForError(Object error, LocationPermission? permissionNow) {
  final granted = permissionNow == LocationPermission.whileInUse || permissionNow == LocationPermission.always;
  if (error is PermissionDeniedException) return granted ? GpsState.systemOff : GpsState.denied;
  if (error is PositionUpdateException || error is LocationServiceDisabledException) {
    return granted ? GpsState.systemOff : GpsState.unavailable;
  }
  if (error is TimeoutException) return GpsState.unavailable; // slow / indoors
  final s = error.toString().toLowerCase();
  if (s.contains('denied') || s.contains('permission')) return granted ? GpsState.systemOff : GpsState.denied;
  return GpsState.unavailable;
}

/// Text shown in the banner for a GPS problem (null = no banner).
String? gpsMessageKey(GpsState s) => switch (s) {
      GpsState.denied => 'svc_gps_denied',
      GpsState.unavailable => 'svc_gps_unavailable',
      GpsState.systemOff => 'svc_gps_system_off',
      _ => null,
    };

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/service_models.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/services_repository.dart';
import 'gps_logic.dart';

export 'gps_logic.dart' show GpsState, gpsMessageKey;

/// Default centre when GPS is not available (Baku).
const kDefaultServiceCenter = LatLng(40.4093, 49.8671);

final serviceCategoriesProvider = FutureProvider<List<ServiceCategory>>((ref) {
  return ref.watch(servicesRepositoryProvider).categories();
});

final allServiceCategoriesProvider = FutureProvider<List<ServiceCategory>>((ref) {
  return ref.watch(servicesRepositoryProvider).categories(includeInactive: true);
});

/// The signed-in user's own service profile (null = none yet).
final myServiceProvider = FutureProvider<ServiceProvider?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return ref.watch(servicesRepositoryProvider).mine(uid);
});

final serviceByIdProvider = FutureProvider.family<ServiceProvider?, String>((ref, id) {
  return ref.watch(servicesRepositoryProvider).byId(id);
});

final serviceReviewsProvider = FutureProvider.family<List<ServiceReview>, String>((ref, id) {
  return ref.watch(servicesRepositoryProvider).reviews(id);
});

final serviceNearbyProvider = FutureProvider.autoDispose.family<List<ServiceProvider>, ServiceQuery>((ref, q) {
  return ref.watch(servicesRepositoryProvider).nearby(q);
});

/// Service kind chosen at registration ("Usta / Servis" → individual /
/// center), kept in the auth metadata until a profile is created.
String? pendingServiceKind() {
  final meta = SupabaseConfig.client.auth.currentUser?.userMetadata;
  final k = meta?['service_kind'];
  return (k == 'individual' || k == 'center') ? k as String : null;
}

// ---- GPS -----------------------------------------------------------------

class UserLocation {
  final GpsState state;
  final LatLng? point;
  const UserLocation(this.state, this.point);
}

/// The device position, asked only when the Services tab needs it (the
/// browser shows its own permission prompt). Never stored on the server.
class UserLocationController extends StateNotifier<UserLocation> {
  UserLocationController() : super(const UserLocation(GpsState.idle, null));

  /// [allowApprox] false = only a real GPS / browser position (e.g. when
  /// the position is saved as the service's address pin).
  Future<LatLng?> locate({bool allowApprox = true}) async {
    if (state.state == GpsState.locating) return state.point;
    state = UserLocation(GpsState.locating, state.point);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        state = UserLocation(GpsState.denied, state.point);
        return null;
      }
      // Web: asking for the position shows the browser's own prompt.
      // Geolocator.requestPermission() on web reports EVERY failure (also
      // "position not found", e.g. location off in Windows) as "denied",
      // so the user saw "not allowed" right after allowing it.
      if (!kIsWeb && perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          state = UserLocation(GpsState.denied, state.point);
          return null;
        }
      }
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        ).timeout(const Duration(seconds: 20));
      } on PermissionDeniedException {
        rethrow;
      } catch (_) {
        // Computers without GPS: one more try with the network position.
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 10)),
        ).timeout(const Duration(seconds: 15));
      }
      final p = LatLng(pos.latitude, pos.longitude);
      state = UserLocation(GpsState.ok, p);
      return p;
    } catch (e) {
      LocationPermission? now;
      try {
        now = await Geolocator.checkPermission();
      } catch (_) {}
      final failed = gpsStateForError(e, now);
      // Computers often have no GPS / Wi-Fi position: open the map at the
      // city of the internet connection instead (not after a real "Block").
      if (allowApprox && kIsWeb && failed != GpsState.denied) {
        final approx = await _approxByIp();
        if (approx != null) {
          state = UserLocation(GpsState.approximate, approx);
          return approx;
        }
      }
      state = UserLocation(failed, state.point);
    }
    return null;
  }

  static Future<LatLng?> _approxByIp() async {
    for (final url in ipGeoUrls) {
      try {
        final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
        if (r.statusCode != 200) continue;
        final p = parseIpGeo(jsonDecode(r.body));
        if (p != null) return LatLng(p.$1, p.$2);
      } catch (_) {}
    }
    return null;
  }
}

final userLocationProvider = StateNotifierProvider<UserLocationController, UserLocation>((ref) => UserLocationController());

// ---- look & labels -----------------------------------------------------------

Color serviceMarkerColor(ServiceMarkerType t) => switch (t) {
      ServiceMarkerType.mobile => AppColors.accent,
      ServiceMarkerType.center => AppColors.blue,
      ServiceMarkerType.tow => const Color(0xFFFACC15),
    };

IconData serviceMarkerIcon(ServiceMarkerType t) => switch (t) {
      ServiceMarkerType.mobile => Icons.handyman,
      ServiceMarkerType.center => Icons.car_repair,
      ServiceMarkerType.tow => Icons.car_crash,
    };

String serviceMarkerLabelKey(ServiceMarkerType t) => switch (t) {
      ServiceMarkerType.mobile => 'svc_type_mobile',
      ServiceMarkerType.center => 'svc_type_center',
      ServiceMarkerType.tow => 'svc_type_tow',
    };

IconData serviceCategoryIcon(String icon) => switch (icon) {
      'truck' => Icons.local_shipping,
      'engine' => Icons.settings,
      'electrical' => Icons.electrical_services,
      'tyre' => Icons.tire_repair,
      'battery' => Icons.battery_charging_full,
      'tow' => Icons.car_crash,
      'reefer' => Icons.ac_unit,
      'roadside' => Icons.support,
      'ads' => Icons.campaign,
      'tarp' => Icons.roofing,
      _ => Icons.build,
    };

String fmtKm(double km) => km < 1 ? '${(km * 1000).round()} m' : (km >= 100 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km');

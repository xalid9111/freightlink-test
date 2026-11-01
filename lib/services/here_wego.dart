import 'package:supabase_flutter/supabase_flutter.dart';

/// HERE WeGo Pro (owner, 01.11.2026): a route handed to HERE with the
/// official, documented share link only (HERE Deeplinking API):
///
///   https://share.here.com/r/<LAT,LNG>/<LAT,LNG>?m=tr&vdh=&vdl=&vdw=
///
/// `m=tr` = truck route (HERE WeGo Pro); `vdh` height, `vdl` length,
/// `vdw` width — all in centimetres; `vw` total weight in kg. The share
/// link opens the HERE WeGo app when installed, otherwise HERE's web page;
/// a Pro licence or payment, if HERE asks for one, is handled by HERE.
/// Nothing is invented: a value the user's truck does not have is left out.
class TruckDims {
  final double? heightM, widthM, lengthM;
  const TruckDims({this.heightM, this.widthM, this.lengthM});

  bool get isEmpty => heightM == null && widthM == null && lengthM == null;

  static double? _m(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return d != null && d > 0 && d < 100 ? d : null;
  }

  factory TruckDims.fromRow(Map<String, dynamic> r) => TruckDims(heightM: _m(r['height_m']), widthM: _m(r['width_m']), lengthM: _m(r['length_m']));
}

String _pt(double lat, double lng) => '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// The HERE WeGo Pro truck route link from [fromLat],[fromLng] to
/// [toLat],[toLng] with the truck's own measurements (if any).
Uri hereWeGoRouteLink({
  required double fromLat,
  required double fromLng,
  required double toLat,
  required double toLng,
  TruckDims? truck,
}) {
  final q = <String>['m=tr'];
  int cm(double m) => (m * 100).round();
  if (truck?.heightM != null) q.add('vdh=${cm(truck!.heightM!)}');
  if (truck?.lengthM != null) q.add('vdl=${cm(truck!.lengthM!)}');
  if (truck?.widthM != null) q.add('vdw=${cm(truck!.widthM!)}');
  return Uri.parse('https://share.here.com/r/${_pt(fromLat, fromLng)}/${_pt(toLat, toLng)}?${q.join('&')}');
}

/// The signed-in user's truck measurements from the existing `trucks`
/// table (the truck they drive, else their company's first truck). Read
/// only; null when there is none or nothing is filled in.
Future<TruckDims?> myTruckDims(SupabaseClient c, String uid) async {
  try {
    const cols = 'height_m,width_m,length_m';
    const t = Duration(seconds: 6);
    final driver = await c.from('drivers').select('id').eq('user_id', uid).maybeSingle().timeout(t);
    if (driver != null) {
      final rows = await c.from('trucks').select(cols).eq('driver_id', driver['id'] as String).limit(1).timeout(t);
      if (rows.isNotEmpty) {
        final d = TruckDims.fromRow(rows.first);
        if (!d.isEmpty) return d;
      }
    }
    final carrier = await c.from('carriers').select('id').eq('user_id', uid).maybeSingle().timeout(t);
    if (carrier == null) return null;
    final rows = await c.from('trucks').select(cols).eq('carrier_id', carrier['id'] as String).order('created_at').limit(1).timeout(t);
    if (rows.isEmpty) return null;
    final d = TruckDims.fromRow(rows.first);
    return d.isEmpty ? null : d;
  } catch (_) {
    return null;
  }
}

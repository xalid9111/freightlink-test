import 'dart:math' as math;

/// TIRPark (owner, 31.10.2026, migration 0077): a TIR park on the map.
/// Added by drivers, approved by an admin; until then only its author
/// (and admins) see it.
class TirPark {
  final String id;
  final String name;
  final double lat, lng;
  final String? city;
  final List<String> amenities;
  final String? note;
  final String status; // pending | approved | rejected | hidden
  final List<String> photoUrls;
  final double ratingAvg;
  final int ratingCount;
  final String? createdBy;
  final DateTime? createdAt;
  // Managed parks and booking (0079); empty for parks without a manager.
  final String? managerId;
  final String? managerStatus; // pending | approved | rejected
  final String? phone;
  final String? address;
  final int? capacity;
  final int? bookable;
  final double? price;
  final String? priceUnit; // hour | day
  final String currency;
  final String? hours;
  final bool bookingOpen;

  const TirPark({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.city,
    this.amenities = const [],
    this.note,
    this.status = 'pending',
    this.photoUrls = const [],
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.createdBy,
    this.createdAt,
    this.managerId,
    this.managerStatus,
    this.phone,
    this.address,
    this.capacity,
    this.bookable,
    this.price,
    this.priceUnit,
    this.currency = 'AZN',
    this.hours,
    this.bookingOpen = false,
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';

  /// Open for booking: the server's tir_park_bookable (0079) + days only
  /// (owner, 03.11.2026: a park priced per hour waits for a day price).
  bool get canBook =>
      isApproved && managerStatus == 'approved' && bookingOpen && (price ?? 0) > 0 && priceUnit == 'day' && (bookable ?? 0) > 0;

  /// A park with an approved manager: its card and page carry the booking
  /// line ("Boş yerlər: n" / "Rezervasiya bağlıdır" / "Boş yer yoxdur").
  bool get isManaged => isApproved && managerStatus == 'approved';

  factory TirPark.fromJson(Map<String, dynamic> j) {
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    List<String> l(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
    return TirPark(
      id: '${j['id']}',
      name: (j['name'] as String?) ?? '',
      lat: d(j['lat']),
      lng: d(j['lng']),
      city: j['city'] as String?,
      amenities: l(j['amenities']),
      note: j['note'] as String?,
      status: (j['status'] as String?) ?? 'pending',
      photoUrls: l(j['photo_urls']),
      ratingAvg: d(j['rating_avg']),
      ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      createdBy: j['created_by'] as String?,
      createdAt: DateTime.tryParse('${j['created_at']}'),
      managerId: j['manager_id'] as String?,
      managerStatus: j['manager_status'] as String?,
      phone: j['phone'] as String?,
      address: j['address'] as String?,
      capacity: j['capacity'] == null ? null : int.tryParse('${j['capacity']}'),
      bookable: j['bookable'] == null ? null : int.tryParse('${j['bookable']}'),
      price: j['price'] == null ? null : d(j['price']),
      priceUnit: j['price_unit'] as String?,
      currency: (j['currency'] as String?) ?? 'AZN',
      hours: j['hours'] as String?,
      bookingOpen: j['booking_open'] == true,
    );
  }
}

/// A space booking in a TIR park (0079).
class TirParkBooking {
  final String id, bookingNo, parkId;
  final int trucks, units;
  final String unit; // hour | day
  final DateTime startAt, endAt;
  final double amount;
  final String currency;
  /// pending_payment · payment_review ("Ödəniş yoxlanılır", 0080) ·
  /// confirmed · checked_in · completed · cancelled · expired
  /// (refund_pending / refunded are reserved, never set today).
  final String status;
  final DateTime? holdUntil;
  final String? paidMode; // test | live
  final String? code; // the driver's own bookings only
  final String? driver; // the manager's list
  final DateTime? checkedInAt, checkedOutAt;
  /// Direct transfer (0080): the receipt picture and the manager's note
  /// when he did not find the money.
  final String? receiptPath;
  final String? rejectNote;
  /// 'driver' · 'payment_rejected' (0081: "Rədd et" ends the booking) · …
  final String? cancelReason;
  /// The truck's state number, e.g. 99-ZB-911 (0082; old bookings: null).
  final String? plate;

  const TirParkBooking({
    required this.id,
    required this.bookingNo,
    required this.parkId,
    required this.trucks,
    required this.units,
    required this.unit,
    required this.startAt,
    required this.endAt,
    required this.amount,
    this.currency = 'AZN',
    required this.status,
    this.holdUntil,
    this.paidMode,
    this.code,
    this.driver,
    this.checkedInAt,
    this.checkedOutAt,
    this.receiptPath,
    this.rejectNote,
    this.cancelReason,
    this.plate,
  });

  /// A payment hold whose time is over counts as expired (the server frees it).
  /// A receipt the park did not accept shows as "Ödəniş rədd edildi" (0081).
  String get shownStatus => status == 'pending_payment' && holdUntil != null && holdUntil!.isBefore(DateTime.now())
      ? 'expired'
      : (status == 'cancelled' && cancelReason == 'payment_rejected' ? 'payment_rejected' : status);

  factory TirParkBooking.fromJson(Map<String, dynamic> j) {
    DateTime? t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
    return TirParkBooking(
      id: '${j['id']}',
      bookingNo: '${j['booking_no'] ?? ''}',
      parkId: '${j['park_id'] ?? ''}',
      trucks: int.tryParse('${j['trucks']}') ?? 1,
      units: int.tryParse('${j['units']}') ?? 1,
      unit: (j['unit'] as String?) ?? 'hour',
      startAt: t(j['start_at']) ?? DateTime.now(),
      endAt: t(j['end_at']) ?? DateTime.now(),
      amount: j['amount'] is num ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}') ?? 0,
      currency: (j['currency'] as String?) ?? 'AZN',
      status: (j['status'] as String?) ?? 'pending_payment',
      holdUntil: t(j['hold_until']),
      paidMode: j['paid_mode'] as String?,
      code: j['code'] as String?,
      driver: j['driver'] as String?,
      checkedInAt: t(j['checked_in_at']),
      checkedOutAt: t(j['checked_out_at']),
      receiptPath: j['receipt_path'] as String?,
      rejectNote: j['reject_note'] as String?,
      cancelReason: j['cancel_reason'] as String?,
      plate: j['plate'] as String?,
    );
  }
}

/// The booking line of a park card right now (0081): open for booking and
/// how many TIRs it can take now. Never any payment details.
class TirParkBookingNow {
  final bool open;
  final int free;
  const TirParkBookingNow({required this.open, required this.free});

  factory TirParkBookingNow.fromJson(Map<String, dynamic> j) =>
      TirParkBookingNow(open: j['open'] == true, free: int.tryParse('${j['free'] ?? 0}') ?? 0);
}

/// The same tidying as the server's _tir_park_plate (0082): "99 zb.911" →
/// "99-ZB-911"; null when it does not look like a state number.
String? tidyTruckPlate(String raw) {
  var v = raw.trim().toUpperCase();
  v = v.replaceAll(RegExp(r'[\s._/]+'), '-').replaceAll(RegExp(r'-{2,}'), '-');
  v = v.replaceAll(RegExp(r'^-+|-+$'), '');
  if (v.length < 3 || v.length > 15) return null;
  if (!RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]$', unicode: true).hasMatch(v)) return null;
  if (!RegExp(r'[0-9]').hasMatch(v)) return null;
  return v;
}

/// Price units the server bills (the same rounding up as 0079): started
/// hours / days count whole.
int tirParkUnits(DateTime from, DateTime to, String unit) {
  final secs = to.difference(from).inSeconds;
  if (secs <= 0) return 0;
  final per = unit == 'hour' ? 3600 : 86400;
  return math.max(1, (secs / per).ceil());
}

/// What a park offers (the server accepts only these, 0077), in the order
/// shown on the card and in the form.
const kTirParkAmenities = ['secure', '24_7', 'food', 'shower', 'wc', 'fuel', 'wifi', 'repair', 'lighting', 'camera', 'free', 'paid'];

/// Straight-line distance in kilometres.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double x) => x * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// "2.5 km" / "850 m".
String distanceLabel(double km) => km < 1 ? '${(km * 1000).round()} m' : (km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km');

/// Parks within [radiusKm] of (lat, lng), nearest first; [query] matches
/// the name or the city (any letter case); [needs] = amenities a park must
/// all have.
List<(TirPark, double)> nearbyParks(List<TirPark> all, double lat, double lng,
    {double radiusKm = 100, String query = '', Set<String> needs = const {}}) {
  final q = query.trim().toLowerCase();
  final out = <(TirPark, double)>[];
  for (final p in all) {
    if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !(p.city ?? '').toLowerCase().contains(q)) continue;
    if (needs.isNotEmpty && !needs.every(p.amenities.contains)) continue;
    final d = distanceKm(lat, lng, p.lat, p.lng);
    if (q.isEmpty && d > radiusKm) continue;
    out.add((p, d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// A park found near the place chosen for a new one (tir_parks_near).
class NearbyPark {
  final String id, name, status;
  final int distanceM;
  const NearbyPark({required this.id, required this.name, required this.status, required this.distanceM});
  factory NearbyPark.fromJson(Map<String, dynamic> j) => NearbyPark(
        id: '${j['id']}',
        name: '${j['name']}',
        status: '${j['status']}',
        distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
      );
}

/// Closer than this to an existing park = the same park (the server
/// refuses it too, 'duplicate_nearby').
const kTirParkDuplicateM = 60;

/// A comment on a park (0078): 1…5 stars and an optional text; one per
/// user and park.
class TirParkReview {
  final String id, userId;
  final int rating;
  final String? comment;
  final String? name, avatarUrl;
  final DateTime? createdAt;
  const TirParkReview({required this.id, required this.userId, required this.rating, this.comment, this.name, this.avatarUrl, this.createdAt});

  factory TirParkReview.fromJson(Map<String, dynamic> j) => TirParkReview(
        id: '${j['id']}',
        userId: '${j['user_id']}',
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        comment: j['comment'] as String?,
        name: j['name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}

/// At most this many pictures per park (the server checks the same).
const kTirParkMaxPhotos = 10;

/// The park's own payment details (0080): the manager enters them; a driver
/// sees them only for his own booking, after booking.
class TirParkPayDetails {
  final String holder;
  final String? bank, account, card, note;
  // For a booking: what to pay.
  final double? amount;
  final String currency;
  final String? bookingNo;
  final DateTime? holdUntil;

  const TirParkPayDetails({
    required this.holder,
    this.bank,
    this.account,
    this.card,
    this.note,
    this.amount,
    this.currency = 'AZN',
    this.bookingNo,
    this.holdUntil,
  });

  factory TirParkPayDetails.fromJson(Map<String, dynamic> j) => TirParkPayDetails(
        holder: '${j['holder'] ?? ''}',
        bank: j['bank'] as String?,
        account: j['account'] as String?,
        card: j['card'] as String?,
        note: j['note'] as String?,
        amount: j['amount'] == null ? null : double.tryParse('${j['amount']}'),
        currency: (j['currency'] as String?) ?? 'AZN',
        bookingNo: j['booking_no'] as String?,
        holdUntil: j['hold_until'] == null ? null : DateTime.tryParse('${j['hold_until']}')?.toLocal(),
      );
}

// ---- Owner panel, stage 1 (owner, 03.11.2026, 0086) -------------------------

/// "Park işlədirəm": the request with only the park's name.
class TirParkOwnerRequest {
  final String id, parkName, status; // pending | approved | rejected
  final String? parkId, note;
  const TirParkOwnerRequest({required this.id, required this.parkName, required this.status, this.parkId, this.note});

  bool get needsSetup => status == 'approved' && parkId == null;

  factory TirParkOwnerRequest.fromJson(Map<String, dynamic> j) => TirParkOwnerRequest(
        id: '${j['id']}',
        parkName: '${j['park_name'] ?? ''}',
        status: (j['status'] as String?) ?? 'pending',
        parkId: j['park_id'] as String?,
        note: j['note'] as String?,
      );
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
DateTime? _time(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// The money a car has run up: price per 24 h × hours / 24, from the end of
/// its paid booking (if any) — the same as the server's _tir_park_stay_amount.
/// 3 AZN: 5 h = 0.63, 1 day 4 h = 3.50, 2 days = 6.00.
double tirParkStayAmount(double rate, DateTime from, DateTime? paidUntil, DateTime to) {
  final start = paidUntil != null && paidUntil.isAfter(from) ? paidUntil : from;
  final secs = to.difference(start).inSeconds;
  if (secs <= 0 || rate <= 0) return 0;
  return (rate * secs / 86400 * 100).round() / 100;
}

/// A car in the park (by its plate).
class TirParkStay {
  final String id, plate, currency;
  final DateTime enteredAt;
  final double rate;
  final DateTime? paidUntil;
  final String? bookingNo, by;
  const TirParkStay({
    required this.id,
    required this.plate,
    required this.enteredAt,
    required this.rate,
    this.paidUntil,
    this.bookingNo,
    this.by,
    this.currency = 'AZN',
  });

  double amountAt(DateTime now) => tirParkStayAmount(rate, enteredAt, paidUntil, now);

  factory TirParkStay.fromJson(Map<String, dynamic> j) => TirParkStay(
        id: '${j['id']}',
        plate: '${j['plate'] ?? ''}',
        enteredAt: _time(j['entered_at']) ?? DateTime.now(),
        rate: _num(j['rate']),
        paidUntil: _time(j['paid_until']),
        bookingNo: j['booking_no'] as String?,
        by: j['by'] as String?,
        currency: (j['currency'] as String?) ?? 'AZN',
      );
}

/// A paid booking expected today that has not come yet.
class TirParkExpected {
  final String id, plate, status;
  final String? bookingNo;
  final int trucks;
  final DateTime startAt, endAt;
  const TirParkExpected(
      {required this.id, required this.plate, required this.status, this.bookingNo, this.trucks = 1, required this.startAt, required this.endAt});

  factory TirParkExpected.fromJson(Map<String, dynamic> j) => TirParkExpected(
        id: '${j['id']}',
        plate: '${j['plate'] ?? ''}',
        status: (j['status'] as String?) ?? 'confirmed',
        bookingNo: j['booking_no'] as String?,
        trucks: int.tryParse('${j['trucks']}') ?? 1,
        startAt: _time(j['start_at']) ?? DateTime.now(),
        endAt: _time(j['end_at']) ?? DateTime.now(),
      );
}

class TirParkParked {
  final List<TirParkStay> inPark;
  final List<TirParkExpected> expected;
  const TirParkParked({this.inPark = const [], this.expected = const []});

  factory TirParkParked.fromJson(Map<String, dynamic> j) => TirParkParked(
        inPark: [for (final r in (j['in'] as List? ?? const [])) TirParkStay.fromJson(Map<String, dynamic>.from(r as Map))],
        expected: [for (final r in (j['expected'] as List? ?? const [])) TirParkExpected.fromJson(Map<String, dynamic>.from(r as Map))],
      );
}

/// The owner's numbers: "Bu gün" = money actually taken today; "accruing" =
/// what the cars still in the park have run up (not taken yet).
class TirParkSummary {
  final int capacity, inPark, reserved, free;
  final double todayPaid, accruing;
  final String currency;
  final bool open;
  const TirParkSummary({
    this.capacity = 0,
    this.inPark = 0,
    this.reserved = 0,
    this.free = 0,
    this.todayPaid = 0,
    this.accruing = 0,
    this.currency = 'AZN',
    this.open = false,
  });

  factory TirParkSummary.fromJson(Map<String, dynamic> j) => TirParkSummary(
        capacity: int.tryParse('${j['capacity']}') ?? 0,
        inPark: int.tryParse('${j['in_park']}') ?? 0,
        reserved: int.tryParse('${j['reserved']}') ?? 0,
        free: int.tryParse('${j['free']}') ?? 0,
        todayPaid: _num(j['today_paid']),
        accruing: _num(j['accruing']),
        currency: (j['currency'] as String?) ?? 'AZN',
        open: j['open'] == true,
      );
}

/// One line of "Parkın gedişatı": in · out · booking · paid.
class TirParkFeedItem {
  final String kind, plate;
  final DateTime at;
  final double? amount;
  final String? by;
  const TirParkFeedItem({required this.kind, required this.plate, required this.at, this.amount, this.by});

  factory TirParkFeedItem.fromJson(Map<String, dynamic> j) => TirParkFeedItem(
        kind: (j['kind'] as String?) ?? 'in',
        plate: '${j['plate'] ?? ''}',
        at: _time(j['at']) ?? DateTime.now(),
        amount: j['amount'] == null ? null : _num(j['amount']),
        by: j['by'] as String?,
      );
}

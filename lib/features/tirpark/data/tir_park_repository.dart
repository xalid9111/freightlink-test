import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/tir_park.dart';

/// Migration 0077 not run yet in Supabase.
class TirParkNotReady implements Exception {
  const TirParkNotReady();
}

/// The server refused a park: 'duplicate_nearby', 'too_many', 'blocked'…
class TirParkRefused implements Exception {
  final String reason;
  const TirParkRefused(this.reason);
}

/// TIR parks (0077). Approved ones for everybody signed in, plus one's own
/// pending ones (RLS); admins see all. Writes go through the server
/// functions (checked there).
class TirParkRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  static const _timeout = Duration(seconds: 15);
  // '*': the booking fields of 0079 come with it once that SQL runs; before
  // that the map keeps working with the 0077 / 0078 columns.
  static const _cols = '*';

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01' || e.code == 'PGRST202' || e.code == '42883') throw const TirParkNotReady();
      for (final r in [
        'duplicate_nearby', 'too_many_attempts', 'too_many', 'blocked', 'admin_only', 'not_allowed', 'invalid_url',
        // 0079: booking and managing.
        'no_space', 'not_bookable', 'invalid_time', 'own_park', 'already_managed', 'already_used', 'not_valid', 'not_in_time',
        'not_checked_in', 'not_cancellable', 'not_paid', 'invalid_argument', 'not_found',
        // 0080: direct transfer.
        'not_payable', 'not_in_review', 'invalid_path',
        // 0082: the truck's plate.
        'invalid_plate',
      ]) {
        if (e.message.contains(r)) throw TirParkRefused(r);
      }
      rethrow;
    }
  }

  /// Parks on the map (bounded so a phone never downloads a huge table).
  Future<List<TirPark>> parks() => _run(() async {
        final rows = await _c
            .from('tir_parks')
            .select(_cols)
            .inFilter('status', ['approved', 'pending'])
            .order('created_at', ascending: false)
            .limit(3000)
            .timeout(_timeout);
        return [for (final r in rows as List) TirPark.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// Admin list: every state, pending first.
  Future<List<TirPark>> adminParks() => _run(() async {
        final rows = await _c.from('tir_parks').select(_cols).order('created_at', ascending: false).limit(3000).timeout(_timeout);
        final list = [for (final r in rows as List) TirPark.fromJson(Map<String, dynamic>.from(r as Map))];
        list.sort((a, b) => (a.isPending ? 0 : 1).compareTo(b.isPending ? 0 : 1));
        return list;
      });

  Future<List<NearbyPark>> near(double lat, double lng, {int radiusM = 500}) => _run(() async {
        final res = await _c.rpc('tir_parks_near', params: {'p_lat': lat, 'p_lng': lng, 'p_radius_m': radiusM}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) NearbyPark.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<String> add({required String name, required double lat, required double lng, String? city, List<String> amenities = const [], String? note}) =>
      _run(() async {
        final id = await _c.rpc('tir_park_add', params: {
          'p_name': name,
          'p_lat': lat,
          'p_lng': lng,
          'p_city': city,
          'p_amenities': amenities,
          'p_note': note,
        }).timeout(_timeout);
        return '$id';
      });

  /// Comments of a park, newest first (0078).
  Future<List<TirParkReview>> reviews(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_reviews_list', params: {'p_park': parkId}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) TirParkReview.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// Writes or changes my comment on the park (one per user and park).
  Future<void> saveReview(String parkId, int rating, String? comment) => _run(() async {
        final me = _c.auth.currentUser?.id;
        if (me == null) throw StateError('not signed in');
        final text = (comment ?? '').trim().isEmpty ? null : comment!.trim();
        final mine = await _c.from('tir_park_reviews').select('id').eq('park_id', parkId).eq('user_id', me).maybeSingle().timeout(_timeout);
        if (mine == null) {
          await _c.from('tir_park_reviews').insert({'park_id': parkId, 'rating': rating, 'comment': text}).timeout(_timeout);
        } else {
          await _c.from('tir_park_reviews').update({'rating': rating, 'comment': text}).eq('id', mine['id']).timeout(_timeout);
        }
      });

  /// My comment (or, for an admin, any comment).
  Future<void> deleteReview(String id) => _run(() => _c.from('tir_park_reviews').delete().eq('id', id).timeout(_timeout));

  /// A picture into my own folder of the profile-media bucket (0031);
  /// returns its public link.
  Future<String> uploadPhoto(String parkId, Uint8List bytes, {String? contentType}) => _run(() async {
        final me = _c.auth.currentUser?.id;
        if (me == null) throw StateError('not signed in');
        final ext = switch (contentType) { 'image/png' => 'png', 'image/gif' => 'gif', 'image/webp' => 'webp', _ => 'jpg' };
        final path = '$me/tirpark/$parkId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _c.storage.from('profile-media').uploadBinary(path, bytes,
            fileOptions: FileOptions(upsert: true, contentType: contentType ?? 'image/jpeg'));
        return _c.storage.from('profile-media').getPublicUrl(path);
      });

  /// The park's pictures, in order (author or admin; 0078).
  Future<void> setPhotos(String parkId, List<String> urls) =>
      _run(() => _c.rpc('tir_park_set_photos', params: {'p_park': parkId, 'p_urls': urls}).timeout(_timeout));

  Future<void> setStatus(String id, String status) =>
      _run(() => _c.rpc('admin_tir_park_set_status', params: {'p_id': id, 'p_status': status}).timeout(_timeout));

  // ---- Managing a park and booking (0079) ---------------------------------
  /// Apply to manage a new park ([parkId] null) or an approved one nobody
  /// manages yet. Waits for an admin.
  Future<String> manageApply({
    String? parkId,
    required String name,
    double? lat,
    double? lng,
    String? city,
    String? address,
    required String phone,
    List<String> amenities = const [],
    required int capacity,
    required int bookable,
    required double price,
    required String unit,
    String? hours,
    String? note,
  }) =>
      _run(() async {
        final id = await _c.rpc('tir_park_manage_apply', params: {
          'p_park': parkId,
          'p_name': name,
          'p_lat': lat,
          'p_lng': lng,
          'p_city': city,
          'p_address': address,
          'p_phone': phone,
          'p_amenities': amenities,
          'p_capacity': capacity,
          'p_bookable': bookable,
          'p_price': price,
          'p_unit': unit,
          'p_hours': hours,
          'p_note': note,
        }).timeout(_timeout);
        return '$id';
      });

  /// My parks (applications and the ones I manage).
  Future<List<TirPark>> myManaged() => _run(() async {
        final res = await _c.rpc('tir_park_my_managed').timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) TirPark.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<void> managerUpdate(String parkId,
          {required int capacity,
          required int bookable,
          required double price,
          required String unit,
          String? hours,
          required String phone,
          required bool open}) =>
      _run(() => _c.rpc('tir_park_manager_update', params: {
            'p_park': parkId,
            'p_capacity': capacity,
            'p_bookable': bookable,
            'p_price': price,
            'p_unit': unit,
            'p_hours': hours,
            'p_phone': phone,
            'p_booking_open': open,
          }).timeout(_timeout));

  /// The park's bookings for its manager (no codes).
  Future<List<TirParkBooking>> managerBookings(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_manager_bookings', params: {'p_park': parkId}).timeout(_timeout);
        return [
          for (final r in (res as List? ?? const [])) TirParkBooking.fromJson({...Map<String, dynamic>.from(r as Map), 'park_id': parkId}),
        ];
      });

  /// Entry: the code is checked on the server. Returns the booking, or
  /// throws [TirParkRefused] ('invalid_code', 'already_used', …).
  Future<TirParkBooking> checkIn(String parkId, String code) => _run(() async {
        final res = Map<String, dynamic>.from(
            await _c.rpc('tir_park_booking_check_in', params: {'p_park': parkId, 'p_code': code}).timeout(_timeout) as Map);
        if (res['error'] != null) throw TirParkRefused('${res['error']}');
        return TirParkBooking.fromJson(res);
      });

  Future<void> checkOut(String bookingId) =>
      _run(() => _c.rpc('tir_park_booking_check_out', params: {'p_booking': bookingId}).timeout(_timeout));

  /// Free places for a time (bookable parks).
  Future<int> freePlaces(String parkId, DateTime from, DateTime to) => _run(() async {
        final res = await _c.rpc('tir_park_availability', params: {
          'p_park': parkId,
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
        }).timeout(_timeout);
        return ((res as Map)['free'] as num?)?.toInt() ?? 0;
      });

  /// Books (the space is held 15 minutes for the payment).
  /// Open / free places now for the managed parks of the list (0081).
  Future<Map<String, TirParkBookingNow>> bookingNow(List<String> parkIds) => _run(() async {
        if (parkIds.isEmpty) return const <String, TirParkBookingNow>{};
        final res = await _c.rpc('tir_parks_booking_now', params: {'p_ids': parkIds.take(500).toList()}).timeout(_timeout);
        return {
          for (final r in (res as List? ?? const []))
            '${(r as Map)['park_id']}': TirParkBookingNow.fromJson(Map<String, dynamic>.from(r)),
        };
      });

  Future<TirParkBooking> book(String parkId, DateTime from, DateTime to, int trucks, String plate) => _run(() async {
        final res = await _c.rpc('tir_park_booking_create', params: {
          'p_park': parkId,
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
          'p_trucks': trucks,
          'p_plate': plate,
        }).timeout(_timeout);
        return TirParkBooking.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<void> cancelBooking(String bookingId) =>
      _run(() => _c.rpc('tir_park_booking_cancel', params: {'p_booking': bookingId}).timeout(_timeout));

  /// My bookings (with my codes), newest first.
  Future<List<TirParkBooking>> myBookings() => _run(() async {
        final me = _c.auth.currentUser?.id;
        if (me == null) return const <TirParkBooking>[];
        final rows = await _c.from('tir_park_bookings').select().eq('user_id', me).order('created_at', ascending: false).limit(100).timeout(_timeout);
        return [for (final r in rows as List) TirParkBooking.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  // ---- Direct bank transfer to the park (0080) ------------------------------
  /// The manager's own details (null = not entered yet).
  Future<TirParkPayDetails?> payDetails(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_get_pay_details', params: {'p_park': parkId}).timeout(_timeout);
        return res == null ? null : TirParkPayDetails.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<void> setPayDetails(String parkId,
          {required String holder, String? bank, String? account, String? card, String? note}) =>
      _run(() => _c.rpc('tir_park_set_pay_details', params: {
            'p_park': parkId,
            'p_holder': holder,
            'p_bank': bank,
            'p_account': account,
            'p_card': card,
            'p_note': note,
          }).timeout(_timeout));

  /// Where the driver pays for his booking (his own booking only).
  Future<TirParkPayDetails?> bookingPayDetails(String bookingId) => _run(() async {
        final res = await _c.rpc('tir_park_booking_pay_details', params: {'p_booking': bookingId}).timeout(_timeout);
        return res == null ? null : TirParkPayDetails.fromJson(Map<String, dynamic>.from(res as Map));
      });

  /// The receipt picture into the private bucket (own folder), then the
  /// booking becomes "Ödəniş yoxlanılır".
  Future<void> uploadReceipt(String bookingId, Uint8List bytes, {String? contentType}) => _run(() async {
        final me = _c.auth.currentUser?.id;
        if (me == null) throw StateError('not signed in');
        final ext = switch (contentType) { 'image/png' => 'png', 'image/webp' => 'webp', 'image/heic' => 'heic', _ => 'jpg' };
        final path = '$me/$bookingId/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _c.storage.from('tirpark-receipts').uploadBinary(path, bytes,
            fileOptions: FileOptions(upsert: false, contentType: contentType ?? 'image/jpeg'));
        await _c.rpc('tir_park_booking_receipt', params: {'p_booking': bookingId, 'p_path': path}).timeout(_timeout);
      });

  /// A short-lived link to look at a receipt (driver, the park's manager, admin).
  Future<String> receiptUrl(String path) => _c.storage.from('tirpark-receipts').createSignedUrl(path, 60 * 30);

  Future<void> confirmPayment(String bookingId) =>
      _run(() => _c.rpc('tir_park_booking_confirm_payment', params: {'p_booking': bookingId}).timeout(_timeout));

  Future<void> rejectPayment(String bookingId, String? note) =>
      _run(() => _c.rpc('tir_park_booking_reject_payment', params: {'p_booking': bookingId, 'p_note': note}).timeout(_timeout));

  // Admin.
  Future<void> adminManagerSet(String parkId, String status) =>
      _run(() => _c.rpc('admin_tir_park_manager_set', params: {'p_park': parkId, 'p_status': status}).timeout(_timeout));

  Future<List<TirParkBooking>> adminBookings(String parkId) => _run(() async {
        final rows = await _c.from('tir_park_bookings').select().eq('park_id', parkId).order('start_at', ascending: false).limit(200).timeout(_timeout);
        return [for (final r in rows as List) TirParkBooking.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<void> adminBookingSet(String bookingId, String status) =>
      _run(() => _c.rpc('admin_tir_park_booking_set_status', params: {'p_booking': bookingId, 'p_status': status}).timeout(_timeout));
}

final tirParkRepositoryProvider = Provider<TirParkRepository>((ref) => TirParkRepository());

final tirParksProvider = FutureProvider.autoDispose<List<TirPark>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tirParkRepositoryProvider).parks();
});

/// "Boş yerlər: n" on the park cards. Before 0081 runs (or offline) the
/// cards simply show no booking line.
final tirParkBookingNowProvider = FutureProvider.autoDispose<Map<String, TirParkBookingNow>>((ref) async {
  final parks = await ref.watch(tirParksProvider.future);
  final ids = [for (final p in parks) if (p.isManaged) p.id];
  try {
    return await ref.watch(tirParkRepositoryProvider).bookingNow(ids);
  } catch (_) {
    return const <String, TirParkBookingNow>{};
  }
});

final adminTirParksProvider = FutureProvider.autoDispose<List<TirPark>>((ref) => ref.watch(tirParkRepositoryProvider).adminParks());

final tirParkReviewsProvider = FutureProvider.autoDispose.family<List<TirParkReview>, String>(
    (ref, parkId) => ref.watch(tirParkRepositoryProvider).reviews(parkId));

final myManagedParksProvider = FutureProvider.autoDispose<List<TirPark>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tirParkRepositoryProvider).myManaged();
});

final myParkBookingsProvider = FutureProvider.autoDispose<List<TirParkBooking>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tirParkRepositoryProvider).myBookings();
});

final managerBookingsProvider =
    FutureProvider.autoDispose.family<List<TirParkBooking>, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).managerBookings(parkId));

final adminParkBookingsProvider =
    FutureProvider.autoDispose.family<List<TirParkBooking>, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).adminBookings(parkId));

final parkPayDetailsProvider =
    FutureProvider.autoDispose.family<TirParkPayDetails?, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).payDetails(parkId));

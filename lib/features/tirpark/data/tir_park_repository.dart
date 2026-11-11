import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/osm_truck_park.dart';
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
        // 0086: owner panel.
        'already_applied', 'already_in', 'already_out', 'payment_in_review', 'already_reviewed',
        // 0087: workers.
        'invalid_code', 'name_required', 'already_worker',
        // 0092: one plate per truck.
        'duplicate_plate', 'plates_count',
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

  /// OSM truck parking inside one map area (0117, "Xəritə məlumatı"): read
  /// from our own table, never from an outside API. Before 0117 runs: none.
  Future<List<OsmTruckPark>> osmInBounds(OsmBounds b) async {
    try {
      final res = await _c.rpc('osm_truck_parks_in_bounds', params: {
        'p_south': b.south,
        'p_west': b.west,
        'p_north': b.north,
        'p_east': b.east,
      }).timeout(_timeout);
      final items = (res is Map ? res['items'] : null) as List? ?? const [];
      return [for (final r in items) OsmTruckPark.fromJson(Map<String, dynamic>.from(r as Map))];
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883' || e.code == 'PGRST205' || e.code == '42P01') return const [];
      rethrow;
    }
  }

  /// Admins: hide / show one OSM object (logged on the server).
  Future<void> adminOsmSetHidden(String sourceId, bool hidden) => _run(
      () => _c.rpc('admin_osm_park_set_hidden', params: {'p_source_id': sourceId, 'p_hidden': hidden}).timeout(_timeout));

  /// Admins: totals per country and the last import.
  Future<Map<String, dynamic>> adminOsmStatus() => _run(() async {
        final res = await _c.rpc('admin_osm_parks_status').timeout(_timeout);
        return Map<String, dynamic>.from(res as Map);
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
  // ---- Owner panel, stage 1 (0086) ----------------------------------------
  /// My latest "Park işlədirəm" request (null = none).
  Future<TirParkOwnerRequest?> myOwnerRequest() => _run(() async {
        final me = _c.auth.currentUser?.id;
        if (me == null) return null;
        final row = await _c
            .from('tir_park_owner_requests')
            .select()
            .eq('user_id', me)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle()
            .timeout(_timeout);
        return row == null ? null : TirParkOwnerRequest.fromJson(Map<String, dynamic>.from(row));
      });

  Future<void> ownerApply(String name) => _run(() => _c.rpc('tir_park_owner_apply', params: {'p_name': name}).timeout(_timeout));

  Future<String> ownerSetup(
          {required String requestId, String? parkId, double? lat, double? lng, String? city, required int capacity, required double price, required String phone}) =>
      _run(() async {
        final id = await _c.rpc('tir_park_owner_setup', params: {
          'p_request': requestId,
          'p_park': parkId,
          'p_lat': lat,
          'p_lng': lng,
          'p_city': city,
          'p_capacity': capacity,
          'p_price': price,
          'p_phone': phone,
        }).timeout(_timeout);
        return '$id';
      });

  Future<TirParkStay> stayEnter(String parkId, String plate) => _run(() async {
        final res = await _c.rpc('tir_park_stay_enter', params: {'p_park': parkId, 'p_plate': plate}).timeout(_timeout);
        return TirParkStay.fromJson(Map<String, dynamic>.from(res as Map));
      });

  /// The car leaves; returns the amount taken.
  Future<double> stayExit(String stayId) => _run(() async {
        final res = await _c.rpc('tir_park_stay_exit', params: {'p_stay': stayId}).timeout(_timeout);
        final a = (res as Map)['amount'];
        return a is num ? a.toDouble() : double.tryParse('$a') ?? 0;
      });

  Future<TirParkParked> parked(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_parked', params: {'p_park': parkId}).timeout(_timeout);
        return TirParkParked.fromJson(Map<String, dynamic>.from(res as Map));
      });

  /// Günlük · Aylıq · İllik income (0094) — the owner's only.
  Future<TirParkIncome> ownerIncome(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_owner_income', params: {'p_park': parkId}).timeout(_timeout);
        return TirParkIncome.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<TirParkSummary> ownerSummary(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_owner_summary', params: {'p_park': parkId}).timeout(_timeout);
        return TirParkSummary.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<List<TirParkFeedItem>> ownerFeed(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_owner_feed', params: {'p_park': parkId, 'p_limit': 30}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) TirParkFeedItem.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  // ---- Workers (0087) ------------------------------------------------------
  Future<TirParkInvite> inviteCreate(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_invite_create', params: {'p_park': parkId}).timeout(_timeout);
        return TirParkInvite.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<void> inviteCancel(String inviteId) => _run(() => _c.rpc('tir_park_invite_cancel', params: {'p_invite': inviteId}).timeout(_timeout));

  /// The park's name for a code (throws [TirParkRefused] 'invalid_code').
  Future<String> invitePreview(String code) => _run(() async {
        final res = Map<String, dynamic>.from(await _c.rpc('tir_park_invite_preview', params: {'p_code': code}).timeout(_timeout) as Map);
        if (res['error'] != null) throw TirParkRefused('${res['error']}');
        return '${res['park_name'] ?? ''}';
      });

  /// Sends my request with my name and surname (0088): I wait for the owner.
  Future<String> inviteAccept(String code, String name) => _run(() async {
        final res = Map<String, dynamic>.from(
            await _c.rpc('tir_park_invite_accept', params: {'p_code': code, 'p_name': name}).timeout(_timeout) as Map);
        if (res['error'] != null) throw TirParkRefused('${res['error']}');
        return '${res['park_name'] ?? ''}';
      });

  Future<void> workerApprove(String parkId, String userId) =>
      _run(() => _c.rpc('tir_park_worker_approve', params: {'p_park': parkId, 'p_user': userId}).timeout(_timeout));

  Future<void> workerReject(String parkId, String userId) =>
      _run(() => _c.rpc('tir_park_worker_reject', params: {'p_park': parkId, 'p_user': userId}).timeout(_timeout));

  /// Workers waiting for my approval (0088); 0 before that SQL.
  Future<int> ownerPendingWorkers() async {
    try {
      final res = await _c.rpc('tir_park_owner_pending_workers').timeout(_timeout);
      return res is num ? res.toInt() : int.tryParse('$res') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// The owner names (or un-names) the park's admin (0089).
  Future<void> workerSetAdmin(String parkId, String userId, bool on) => _run(() => _c
      .rpc('tir_park_worker_set_admin', params: {'p_park': parkId, 'p_user': userId, 'p_on': on}).timeout(_timeout));

  Future<void> workerRemove(String parkId, String userId) =>
      _run(() => _c.rpc('tir_park_worker_remove', params: {'p_park': parkId, 'p_user': userId}).timeout(_timeout));

  Future<TirParkWorkers> workers(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_workers_list', params: {'p_park': parkId}).timeout(_timeout);
        return TirParkWorkers.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<List<TirParkWorkPlace>> myWork() => _run(() async {
        final res = await _c.rpc('tir_park_my_work').timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) TirParkWorkPlace.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<List<TirParkFeedItem>> workerActivity(String parkId) => _run(() async {
        final res = await _c.rpc('tir_park_worker_activity', params: {'p_park': parkId, 'p_limit': 30}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) TirParkFeedItem.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<List<TirParkReportDay>> ownerReport(String parkId, {int days = 30}) => _run(() async {
        final res = await _c.rpc('tir_park_owner_report', params: {'p_park': parkId, 'p_days': days}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) TirParkReportDay.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<List<Map<String, dynamic>>> adminOwnerRequests() => _run(() async {
        final res = await _c.rpc('admin_tir_park_owner_requests').timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
      });

  Future<void> adminOwnerRequestSet(String id, String status, {String? note}) => _run(
      () => _c.rpc('admin_tir_park_owner_request_set', params: {'p_id': id, 'p_status': status, 'p_note': note}).timeout(_timeout));

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
  /// Receipts waiting for me as a park manager (0085); 0 before that SQL.
  Future<int> managerPending() async {
    try {
      final res = await _c.rpc('tir_park_manager_pending').timeout(_timeout);
      return res is num ? res.toInt() : int.tryParse('$res') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Open / free places now for the managed parks of the list (0081).
  Future<Map<String, TirParkBookingNow>> bookingNow(List<String> parkIds) => _run(() async {
        if (parkIds.isEmpty) return const <String, TirParkBookingNow>{};
        final res = await _c.rpc('tir_parks_booking_now', params: {'p_ids': parkIds.take(500).toList()}).timeout(_timeout);
        return {
          for (final r in (res as List? ?? const []))
            '${(r as Map)['park_id']}': TirParkBookingNow.fromJson(Map<String, dynamic>.from(r)),
        };
      });

  /// [plates] = one plate per truck (0092); the first is [plate]. One
  /// truck uses the 5-argument function (works before and after 0092);
  /// several use the 6-argument one, and fall back to the old one while
  /// 0092 is not run yet in Supabase.
  Future<TirParkBooking> book(String parkId, DateTime from, DateTime to, int trucks, String plate, {List<String> plates = const []}) =>
      _run(() async {
        final params = <String, dynamic>{
          'p_park': parkId,
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
          'p_trucks': trucks,
          'p_plate': plate,
        };
        Object? res;
        if (trucks > 1 && plates.length == trucks) {
          try {
            res = await _c.rpc('tir_park_booking_create', params: {...params, 'p_plates': plates}).timeout(_timeout);
          } on PostgrestException catch (e) {
            if (e.code != 'PGRST202' && e.code != '42883') rethrow;
            res = null;
          }
        }
        res ??= await _c.rpc('tir_park_booking_create', params: params).timeout(_timeout);
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

/// OSM objects of one map area; kept 10 minutes so panning back and forth
/// never asks the server again.
final osmTruckParksProvider = FutureProvider.autoDispose.family<List<OsmTruckPark>, OsmBounds>((ref, b) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  try {
    return await ref.watch(tirParkRepositoryProvider).osmInBounds(b);
  } catch (_) {
    link.close();
    rethrow;
  }
});

final adminOsmStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(tirParkRepositoryProvider).adminOsmStatus());

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

final myOwnerRequestProvider = FutureProvider.autoDispose<TirParkOwnerRequest?>((ref) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.watch(tirParkRepositoryProvider).myOwnerRequest();
  } on TirParkNotReady {
    return null;
  }
});

final tirParkParkedProvider =
    FutureProvider.autoDispose.family<TirParkParked, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).parked(parkId));

final tirParkSummaryProvider =
    FutureProvider.autoDispose.family<TirParkSummary, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).ownerSummary(parkId));

final tirParkIncomeProvider =
    FutureProvider.autoDispose.family<TirParkIncome, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).ownerIncome(parkId));

final tirParkFeedProvider =
    FutureProvider.autoDispose.family<List<TirParkFeedItem>, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).ownerFeed(parkId));

final tirParkWorkersProvider =
    FutureProvider.autoDispose.family<TirParkWorkers, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).workers(parkId));

/// Workers waiting for the owner's approval (Profil count, 0088).
final tirParkPendingWorkersProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tirParkRepositoryProvider).ownerPendingWorkers();
});

final tirParkActivityProvider = FutureProvider.autoDispose
    .family<List<TirParkFeedItem>, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).workerActivity(parkId));

final tirParkReportProvider = FutureProvider.autoDispose
    .family<List<TirParkReportDay>, String>((ref, parkId) => ref.watch(tirParkRepositoryProvider).ownerReport(parkId));

/// Parks I work at (0087); empty before that SQL.
final myWorkParksProvider = FutureProvider.autoDispose<List<TirParkWorkPlace>>((ref) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.watch(tirParkRepositoryProvider).myWork();
  } on TirParkNotReady {
    return const [];
  }
});

final adminOwnerRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(tirParkRepositoryProvider).adminOwnerRequests());

/// The red count on Profil → "TIR parkı idarə edirəm" (0085).
final tirParkManagerPendingProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tirParkRepositoryProvider).managerPending();
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

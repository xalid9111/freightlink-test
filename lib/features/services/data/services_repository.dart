import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/service_models.dart';

const _timeout = Duration(seconds: 20);

/// Columns API clients may read from service_providers. `admin_note` is
/// deliberately absent: since migration 0018 it is not readable through
/// the table (column privilege), so `select()` / `select('*')` would be
/// refused. The owner and admins get the note via [_attachNotes].
const _cols = 'id,owner_id,kind,name,specialty,description,categories,country,city,address,'
    'lat,lng,is_mobile,service_radius_km,phone,whatsapp,working_hours,is_24h,is_active,'
    'status,is_verified,is_pro,added_by_admin,photos,rating_avg,rating_count,created_at,updated_at';

/// Search parameters for the services map.
class ServiceQuery {
  final double lat;
  final double lng;
  final double radiusKm;
  final String? category;
  final double minRating;
  final bool onlyActive;
  final String? kind;
  final String? text;

  const ServiceQuery({
    required this.lat,
    required this.lng,
    this.radiusKm = 100,
    this.category,
    this.minRating = 0,
    this.onlyActive = false,
    this.kind,
    this.text,
  });

  ServiceQuery copyWith({
    double? lat,
    double? lng,
    double? radiusKm,
    String? Function()? category,
    double? minRating,
    bool? onlyActive,
    String? Function()? kind,
    String? Function()? text,
  }) =>
      ServiceQuery(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        radiusKm: radiusKm ?? this.radiusKm,
        category: category != null ? category() : this.category,
        minRating: minRating ?? this.minRating,
        onlyActive: onlyActive ?? this.onlyActive,
        kind: kind != null ? kind() : this.kind,
        text: text != null ? text() : this.text,
      );

  @override
  bool operator ==(Object o) =>
      o is ServiceQuery &&
      o.lat == lat &&
      o.lng == lng &&
      o.radiusKm == radiusKm &&
      o.category == category &&
      o.minRating == minRating &&
      o.onlyActive == onlyActive &&
      o.kind == kind &&
      o.text == text;

  @override
  int get hashCode => Object.hash(lat, lng, radiusKm, category, minRating, onlyActive, kind, text);
}

/// Services module data (migration 0017). Owners write their own row
/// (moderation fields are enforced by a database trigger); everything
/// admin-only goes through server functions that check is_admin().
class ServicesRepository {
  final SupabaseClient _c = SupabaseConfig.client;

  // ---- everyone ---------------------------------------------------------

  Future<List<ServiceCategory>> categories({bool includeInactive = false}) async {
    var q = _c.from('service_categories').select();
    if (!includeInactive) q = q.eq('is_active', true);
    final rows = await q.order('sort_order').timeout(_timeout);
    return (rows as List).map((r) => ServiceCategory.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<ServiceProvider>> nearby(ServiceQuery q) async {
    final res = await _c.rpc('nearby_services', params: {
      'p_lat': q.lat,
      'p_lng': q.lng,
      'p_radius_km': q.radiusKm,
      'p_category': q.category,
      'p_min_rating': q.minRating,
      'p_only_active': q.onlyActive,
      'p_kind': q.kind,
      'p_query': (q.text ?? '').trim().isEmpty ? null : q.text!.trim(),
      'p_limit': 300,
    }).timeout(_timeout);
    final list = res is List ? res : const [];
    return list.map((r) => ServiceProvider.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Universal search: active, approved services anywhere (not limited to
  /// the map radius). [pattern] is an `ilike` pattern for name / city /
  /// address / speciality / country (see dbPattern); [categoryIds] adds
  /// services of matching categories. Exact matching and ranking happen in
  /// the app (service_search_logic.dart). RLS hides blocked owners.
  Future<List<ServiceProvider>> search({String? pattern, List<String> categoryIds = const [], int limit = 200}) async {
    final ors = <String>[
      if (pattern != null)
        for (final col in const ['name', 'city', 'address', 'specialty', 'country']) '$col.ilike.%$pattern%',
      if (categoryIds.isNotEmpty) 'categories.ov.{${categoryIds.join(',')}}',
    ];
    if (ors.isEmpty) return const [];
    final rows = await _c
        .from('service_providers')
        .select(_cols)
        .eq('status', 'approved')
        .eq('is_active', true)
        .or(ors.join(','))
        .order('name')
        .limit(limit)
        .timeout(_timeout);
    return (rows as List).map((r) => ServiceProvider.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<ServiceProvider?> byId(String id) async {
    final row = await _c.from('service_providers').select(_cols).eq('id', id).maybeSingle().timeout(_timeout);
    if (row == null) return null;
    // Only the owner gets their moderation note on the detail screen.
    if (row['owner_id'] != null && row['owner_id'] == _c.auth.currentUser?.id) {
      await _attachNotes([row]);
    }
    return ServiceProvider.fromJson(row);
  }

  Future<ServiceProvider?> mine(String uid) async {
    final row = await _c.from('service_providers').select(_cols).eq('owner_id', uid).maybeSingle().timeout(_timeout);
    if (row == null) return null;
    await _attachNotes([row]);
    return ServiceProvider.fromJson(row);
  }

  /// Adds `admin_note` to [rows] for the profiles the caller may see it on
  /// (own profile, or any profile for an admin) via the
  /// service_provider_notes() RPC from migration 0018.
  /// Before 0018 is applied that RPC does not exist (PGRST202); the note is
  /// then still a normal column, so it is read directly instead.
  Future<void> _attachNotes(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final ids = rows.map((r) => r['id'] as String).toList();
    List notes;
    try {
      notes = await _c.rpc('service_provider_notes', params: {'p_ids': ids}).timeout(_timeout) as List;
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      notes = await _c.from('service_providers').select('id,admin_note').inFilter('id', ids).timeout(_timeout);
    }
    final byId = {for (final n in notes) (n as Map)['id'] as String: n['admin_note'] as String?};
    for (final r in rows) {
      r['admin_note'] = byId[r['id']];
    }
  }

  Future<List<ServiceReview>> reviews(String providerId) async {
    final rows = await _c
        .from('service_reviews')
        .select()
        .eq('provider_id', providerId)
        .order('created_at', ascending: false)
        .limit(100)
        .timeout(_timeout);
    return (rows as List).map((r) => ServiceReview.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<void> saveReview({required String providerId, required String uid, required int rating, String? comment}) async {
    await _c.from('service_reviews').upsert({
      'provider_id': providerId,
      'user_id': uid,
      'rating': rating,
      'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
    }, onConflict: 'provider_id,user_id').timeout(_timeout);
  }

  Future<void> deleteReview(String reviewId) async {
    await _c.from('service_reviews').delete().eq('id', reviewId).timeout(_timeout);
  }

  Future<void> claim(String providerId, {String? message, String? phone}) async {
    await _c.from('service_claims').insert({
      'provider_id': providerId,
      'message': (message ?? '').trim().isEmpty ? null : message!.trim(),
      'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
    }).timeout(_timeout);
  }

  Future<List<ServiceClaim>> myClaims(String uid) async {
    final rows = await _c.from('service_claims').select().eq('user_id', uid).order('created_at', ascending: false).timeout(_timeout);
    return (rows as List).map((r) => ServiceClaim.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<void> report(String providerId, String reason, String? details) async {
    await _c.from('reports').insert({
      'target_type': 'service',
      'target_id': providerId,
      'reason': reason,
      'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
    }).timeout(_timeout);
  }

  // ---- owner -------------------------------------------------------------

  Future<ServiceProvider> create(ServiceProvider p, String uid) async {
    final row = await _c
        .from('service_providers')
        .insert({...p.toWriteJson(), 'owner_id': uid})
        .select(_cols)
        .single()
        .timeout(_timeout);
    return ServiceProvider.fromJson(row); // a new profile has no admin note
  }

  Future<ServiceProvider> update(String id, Map<String, dynamic> patch) async {
    final row = await _c.from('service_providers').update(patch).eq('id', id).select(_cols).single().timeout(_timeout);
    await _attachNotes([row]);
    return ServiceProvider.fromJson(row);
  }

  Future<void> delete(String id) async {
    await _c.from('service_providers').delete().eq('id', id).timeout(_timeout);
  }

  /// Uploads a photo into service-photos/<providerId>/… and returns its public URL.
  Future<String> uploadPhoto(String providerId, Uint8List bytes, String ext) async {
    final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
    final path = '$providerId/${DateTime.now().millisecondsSinceEpoch}.$e';
    await _c.storage
        .from('service-photos')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _c.storage.from('service-photos').getPublicUrl(path);
  }

  Future<void> removePhotoFile(String url) async {
    const marker = '/service-photos/';
    final i = url.indexOf(marker);
    if (i < 0) return;
    final path = Uri.decodeComponent(url.substring(i + marker.length).split('?').first);
    try {
      await _c.storage.from('service-photos').remove([path]).timeout(_timeout);
    } catch (_) {
      // The row no longer references it; a leftover file is harmless.
    }
  }

  // ---- admin -------------------------------------------------------------

  Future<List<ServiceProvider>> adminList({String? status, String? text}) async {
    var q = _c.from('service_providers').select(_cols);
    if (status != null) q = q.eq('status', status);
    final t = (text ?? '').trim();
    if (t.isNotEmpty) q = q.or('name.ilike.%$t%,city.ilike.%$t%,phone.ilike.%$t%');
    final rows = await q.order('created_at', ascending: false).limit(500).timeout(_timeout);
    final list = (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    await _attachNotes(list); // one request for the whole page (max 500)
    return list.map(ServiceProvider.fromJson).toList();
  }

  Future<ServiceProvider> adminSave(String? id, Map<String, dynamic> data) async {
    final row = await _c.rpc('admin_save_service', params: {'p_id': id, 'p_data': data}).timeout(_timeout);
    final m = row is List ? row.first : row;
    return ServiceProvider.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<void> adminSetStatus(String id, String status, {String? note}) async {
    await _c.rpc('admin_set_service_status', params: {'p_id': id, 'p_status': status, 'p_note': note}).timeout(_timeout);
  }

  Future<void> adminSetVerified(String id, bool verified) async {
    await _c.rpc('admin_set_service_verified', params: {'p_id': id, 'p_verified': verified}).timeout(_timeout);
  }

  /// Admin: PRO service on / off (0028).
  Future<void> adminSetPro(String id, bool pro) async {
    await _c.rpc('admin_set_service_pro', params: {'p_id': id, 'p_pro': pro}).timeout(_timeout);
  }

  Future<void> adminDelete(String id, {String? reason}) async {
    await _c.rpc('admin_delete_service', params: {'p_id': id, 'p_reason': reason}).timeout(_timeout);
  }

  Future<List<ServiceClaim>> adminClaims({bool onlyPending = true}) async {
    var q = _c.from('service_claims').select();
    if (onlyPending) q = q.eq('status', 'pending');
    final rows = await q.order('created_at', ascending: false).limit(300).timeout(_timeout);
    return (rows as List).map((r) => ServiceClaim.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<void> adminResolveClaim(String claimId, bool approve, {String? note}) async {
    await _c.rpc('admin_resolve_service_claim', params: {'p_claim': claimId, 'p_approve': approve, 'p_note': note}).timeout(_timeout);
  }

  Future<List<Map<String, dynamic>>> adminServiceReports() async {
    final rows = await _c
        .from('reports')
        .select()
        .eq('target_type', 'service')
        .order('created_at', ascending: false)
        .limit(300)
        .timeout(_timeout);
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> adminSaveCategory(String id, Map<String, dynamic> data) async {
    await _c.rpc('admin_save_service_category', params: {'p_id': id, 'p_data': data}).timeout(_timeout);
  }

  Future<Map<String, int>> adminCounts() async {
    final res = await _c.rpc('admin_service_counts').timeout(_timeout);
    if (res is! Map) return const {};
    return res.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
  }
}

final servicesRepositoryProvider = Provider<ServicesRepository>((ref) => ServicesRepository());

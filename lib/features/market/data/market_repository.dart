import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/constants/cities.dart';
import '../domain/market_models.dart';

const _timeout = Duration(seconds: 20);
const kMarketPageSize = 20;

/// TIR Bazarı data (migration 0040). The database decides who sees what
/// (RLS) and protects moderation / VIP / views; this only reads & writes.
class MarketRepository {
  final SupabaseClient _c = SupabaseConfig.client;

  String? get _me => _c.auth.currentUser?.id;

  List<MarketListing> _list(Object? res) =>
      (res is List ? res : const []).map((r) => MarketListing.fromJson(Map<String, dynamic>.from(r as Map))).toList();

  /// Feed page: active ads, VIP first, newest first.
  Future<List<MarketListing>> search(MarketFilter f, {int offset = 0, int limit = kMarketPageSize}) async {
    final params = f.toParams(limit: limit, offset: offset);
    // Cities are stored by their English catalogue name (like loads):
    // "Bakı" / "Баку" typed in any language finds "Baku".
    for (final k in ['p_city', 'p_q']) {
      final v = params[k] as String?;
      if (v != null) params[k] = Cities.find(v)?.en ?? v;
    }
    final res = await _c.rpc('market_search', params: params).timeout(_timeout);
    return _list(res);
  }

  /// VIP ads for the top of the page.
  Future<List<MarketListing>> vip({MarketCategory? category, int limit = 6}) async {
    final res = await _c
        .rpc('market_search', params: MarketFilter(category: category).toParams(limit: limit)..['p_vip_only'] = true)
        .timeout(_timeout);
    return _list(res);
  }

  Future<List<MarketListing>> similar(String id, {int limit = 10}) async {
    final res = await _c.rpc('market_similar', params: {'p_id': id, 'p_limit': limit}).timeout(_timeout);
    return _list(res);
  }

  Future<MarketListing?> byId(String id) async {
    final row = await _c.from('market_listings').select().eq('id', id).maybeSingle().timeout(_timeout);
    return row == null ? null : MarketListing.fromJson(row);
  }

  Future<List<MarketListing>> mine() async {
    final me = _me;
    if (me == null) return const [];
    final rows = await _c.from('market_listings').select().eq('owner_id', me).order('updated_at', ascending: false).timeout(_timeout);
    return _list(rows);
  }

  /// Saves a draft (new or existing); [publish] sends it to the admin.
  Future<MarketListing> save(MarketDraft d, {String? id, required bool publish, MarketStatus? current}) async {
    final data = d.toJson();
    if (publish) {
      // draft / rejected / inactive → pending. An active ad goes back to
      // the admin by itself when edited (database trigger).
      if (current == null || current == MarketStatus.draft || current == MarketStatus.rejected || current == MarketStatus.inactive) {
        data['status'] = 'pending';
      }
    } else if (current == null) {
      data['status'] = 'draft';
    } else if (current == MarketStatus.pending || current == MarketStatus.rejected) {
      data['status'] = 'draft';
    }
    final row = id == null
        ? await _c.from('market_listings').insert({...data, 'owner_id': _me}).select().single().timeout(_timeout)
        : await _c.from('market_listings').update(data).eq('id', id).select().single().timeout(_timeout);
    return MarketListing.fromJson(row);
  }

  Future<void> markSold(String id) async {
    await _c.from('market_listings').update({'status': 'sold'}).eq('id', id).timeout(_timeout);
  }

  Future<void> delete(MarketListing l) async {
    await _c.from('market_listings').delete().eq('id', l.id).timeout(_timeout);
    for (final url in l.photos) {
      await removePhoto(url);
    }
  }

  /// Real views: one per person per day (the owner's own not counted).
  Future<int?> recordView(String id) async {
    final res = await _c.rpc('market_record_view', params: {'p_id': id}).timeout(_timeout);
    return res is num ? res.toInt() : null;
  }

  // ---- favourites ----------------------------------------------------------

  Future<Set<String>> favoriteIds() async {
    if (_me == null) return const {};
    final rows = await _c.from('market_favorites').select('listing_id').timeout(_timeout);
    return {for (final r in rows as List) '${r['listing_id']}'};
  }

  Future<List<MarketListing>> favorites() async {
    final ids = await favoriteIds();
    if (ids.isEmpty) return const [];
    final rows = await _c.from('market_listings').select().inFilter('id', ids.toList()).timeout(_timeout);
    return _list(rows);
  }

  Future<void> setFavorite(String id, bool on) async {
    final me = _me;
    if (me == null) return;
    if (on) {
      await _c.from('market_favorites').upsert({'user_id': me, 'listing_id': id}).timeout(_timeout);
    } else {
      await _c.from('market_favorites').delete().eq('user_id', me).eq('listing_id', id).timeout(_timeout);
    }
  }

  // ---- photos (public bucket, folder = my user id) -------------------------

  Future<String> uploadPhoto(Uint8List bytes, String ext) async {
    final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
    final path = '$_me/${DateTime.now().microsecondsSinceEpoch}.$e';
    await _c.storage
        .from('market-photos')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _c.storage.from('market-photos').getPublicUrl(path);
  }

  Future<void> removePhoto(String url) async {
    const marker = '/market-photos/';
    final i = url.indexOf(marker);
    if (i < 0) return;
    final path = Uri.decodeComponent(url.substring(i + marker.length).split('?').first);
    try {
      await _c.storage.from('market-photos').remove([path]).timeout(_timeout);
    } catch (_) {
      // The ad no longer references it; a leftover file is harmless.
    }
  }

  Future<void> report(String id, String reason, String? details) async {
    await _c.from('reports').insert({
      'target_type': 'market_listing',
      'target_id': id,
      'reason': reason,
      'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
    }).timeout(_timeout);
  }

  // ---- admin (server checks is_admin) --------------------------------------

  Future<List<MarketListing>> adminList({MarketStatus? status}) async {
    var q = _c.from('market_listings').select();
    if (status != null) q = q.eq('status', status.name);
    final rows = await q.order('updated_at', ascending: false).limit(300).timeout(_timeout);
    return _list(rows);
  }

  Future<void> adminSetStatus(String id, MarketStatus status, {String? note}) async {
    await _c.rpc('admin_market_set_status', params: {'p_id': id, 'p_status': status.name, 'p_note': note}).timeout(_timeout);
  }

  Future<void> adminSetVip(String id, bool vip, {int? days}) async {
    await _c.rpc('admin_market_set_vip', params: {'p_id': id, 'p_vip': vip, 'p_days': days}).timeout(_timeout);
  }

  Future<void> adminDelete(String id, {String? reason}) async {
    await _c.rpc('admin_market_delete', params: {'p_id': id, 'p_reason': reason}).timeout(_timeout);
  }
}

final marketRepositoryProvider = Provider<MarketRepository>((ref) => MarketRepository());

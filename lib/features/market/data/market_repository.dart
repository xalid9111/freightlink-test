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

  /// The signed-in user's id straight from the session (no profile fetch).
  String? get myId => _me;

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
    try {
      return _list(await _c.rpc('market_search', params: params).timeout(_timeout));
    } on PostgrestException catch (e) {
      if (!(e.code == 'PGRST202' || e.code == '42883')) rethrow;
      // 0065 not run yet: every ad is in stock, and no ad has a wheel
      // formula, equipment or a damage mark yet.
      if (const ['p_availability', 'p_axle_formula', 'p_equipment', 'p_damaged'].any(params.containsKey)) {
        if (params['p_availability'] == 'on_order' ||
            const ['p_axle_formula', 'p_equipment', 'p_damaged'].any(params.containsKey)) {
          return const [];
        }
        return search(f.copyWith(availability: () => null), offset: offset, limit: limit);
      }
      // 0064 not run yet: the search without body type / other spellings.
      const added = ['p_body_type', 'p_brands', 'p_models'];
      if (!added.any(params.containsKey)) rethrow;
      return _list(await _c
          .rpc('market_search', params: {...params}..removeWhere((k, _) => added.contains(k)))
          .timeout(_timeout));
    }
  }

  /// Brand + model of every active ad (of [category]) — for the real
  /// counts on the "Marka" / "Model" search pages (owner, 24.10.2026).
  Future<List<Map<String, dynamic>>> activeBrandRows({MarketCategory? category}) async {
    var q = _c.from('market_listings').select('brand, model').eq('status', 'active');
    if (category != null) q = q.eq('category', category.wire);
    final rows = await q.limit(5000).timeout(_timeout);
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
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

  /// Saves a draft (new or existing); [publish] puts it online at once
  /// (0041), or back to the admin if the admin had deactivated it.
  Future<MarketListing> save(MarketDraft d, {String? id, required bool publish, MarketStatus? current}) async {
    final data = d.toJson();
    if (publish) {
      final next = marketPublishStatus(current);
      if (next != null) data['status'] = next.name;
    } else if (current == null) {
      data['status'] = 'draft';
    } else if (current == MarketStatus.pending || current == MarketStatus.rejected) {
      data['status'] = 'draft';
    }
    Future<Map<String, dynamic>> write(Map<String, dynamic> d) async => id == null
        ? await _c.from('market_listings').insert({...d, 'owner_id': _me}).select().single().timeout(_timeout)
        : await _c.from('market_listings').update(d).eq('id', id).select().single().timeout(_timeout);
    // 0053 / 0064 / 0065 not run yet: save without the "exact place"
    // mark, the body type or the 0065 choices (all optional). The
    // database names one missing column at a time.
    const optional = ['location_exact', 'body_type', 'availability', 'axle_formula', 'equipment', 'damaged'];
    var rest = data;
    while (true) {
      try {
        return MarketListing.fromJson(await write(rest));
      } on PostgrestException catch (e) {
        if (!(e.code == 'PGRST204' || e.code == '42703')) rethrow;
        final missing = optional.where((k) => e.message.contains(k) && rest.containsKey(k)).toList();
        if (missing.isEmpty) rethrow;
        rest = {...rest}..removeWhere((k, _) => missing.contains(k));
      }
    }
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

  // ---- banner + paid VIP (0044) ---------------------------------------------

  /// The admin's banner (null until the admin saves one).
  Future<MarketHero?> hero() async {
    final row = await _c.from('market_hero').select().eq('id', 1).maybeSingle().timeout(_timeout);
    return row == null ? null : MarketHero.fromJson(row);
  }

  /// The newest VIP ads (for the VIP places beside the ads on a computer).
  Future<List<MarketListing>> vipLatest({MarketCategory? category, int limit = 6}) async {
    final res = await _c.rpc('market_vip_latest', params: {'p_category': category?.wire, 'p_limit': limit}).timeout(_timeout);
    return _list(res);
  }

  Future<List<MarketVipPlan>> vipPlans({bool activeOnly = true}) async {
    var q = _c.from('market_vip_plans').select();
    if (activeOnly) q = q.eq('is_active', true);
    final rows = await q.order('days').timeout(_timeout);
    return [for (final r in rows as List) MarketVipPlan.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// "VIP et": an order for my active ad; the price is set by the server.
  Future<MarketVipOrder> createVipOrder(String listingId, int days) async {
    final res = await _c.rpc('market_vip_order_create', params: {'p_listing': listingId, 'p_days': days}).timeout(_timeout);
    return MarketVipOrder.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Premium ads for the top of the feed (0066); none before 0066 is run.
  Future<List<MarketListing>> premiumLatest({MarketCategory? category, int limit = 12}) async {
    try {
      final res = await _c.rpc('market_premium_latest', params: {'p_category': category?.wire, 'p_limit': limit}).timeout(_timeout);
      return _list(res);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883') return const [];
      rethrow;
    }
  }

  /// Prices of İrəli çək / Premium (0066); VIP from market_vip_plans.
  Future<List<MarketPromoPlan>> promoPlans(MarketPromoKind kind, {bool activeOnly = true}) async {
    if (kind == MarketPromoKind.vip) {
      return [for (final p in await vipPlans(activeOnly: activeOnly)) MarketPromoPlan.vip(p)];
    }
    try {
      var q = _c.from('market_promo_plans').select().eq('kind', kind.wire);
      if (activeOnly) q = q.eq('is_active', true);
      final rows = await q.order('qty').timeout(_timeout);
      return [for (final r in rows as List) MarketPromoPlan.fromJson(Map<String, dynamic>.from(r as Map))];
    } on PostgrestException catch (e) {
      // 0066 not run yet: no prices, nothing to buy.
      if (e.code == '42P01' || e.code == 'PGRST205') return const [];
      rethrow;
    }
  }

  /// "İrəli çək" / "Premium et": an order for my active ad; the server sets
  /// the price.
  Future<MarketPromoOrder> createPromoOrder(String listingId, MarketPromoKind kind, int qty) async {
    final res = await _c
        .rpc('market_promo_order_create', params: {'p_listing': listingId, 'p_kind': kind.wire, 'p_qty': qty})
        .timeout(_timeout);
    return MarketPromoOrder.fromJson(Map<String, dynamic>.from(res as Map));
  }

  // ---- admin (server checks is_admin) --------------------------------------

  Future<void> adminSetHero({String? imageUrl, String? title, String? titleAccent, String? subtitle}) async {
    await _c.rpc('admin_market_set_hero', params: {
      'p_image_url': imageUrl,
      'p_title': title,
      'p_title_accent': titleAccent,
      'p_subtitle': subtitle,
    }).timeout(_timeout);
  }

  Future<void> adminSetPromoPlan(MarketPromoKind kind, int qty, double price, {bool active = true}) async {
    if (kind == MarketPromoKind.vip) return adminSetVipPlan(qty, price, active: active);
    await _c
        .rpc('admin_market_set_promo_plan', params: {'p_kind': kind.wire, 'p_qty': qty, 'p_price': price, 'p_active': active})
        .timeout(_timeout);
  }

  Future<void> adminSetVipPlan(int days, double price, {bool active = true}) async {
    await _c.rpc('admin_market_set_vip_plan', params: {'p_days': days, 'p_price': price, 'p_active': active}).timeout(_timeout);
  }

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

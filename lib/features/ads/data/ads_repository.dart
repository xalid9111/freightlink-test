import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/ad_models.dart';

const _timeout = Duration(seconds: 20);

/// Advertising data (migration 0015). Customers create orders and report
/// payment through server functions; everything that makes an ad visible
/// (approval, image, dates, on/off) is admin-only and checked on the
/// server.
class AdsRepository {
  final SupabaseClient _c = SupabaseConfig.client;
  final Set<String> _impressionsRecordedThisSession = {};

  // ---- everyone ---------------------------------------------------------

  /// Ads to show in the feed right now (RLS already limits other users to
  /// live ads; the extra check hides the viewer's own scheduled ones).
  Future<List<Ad>> liveAds() async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final rows = await _c
        .from('ads')
        .select()
        .eq('is_active', true)
        .lte('starts_at', nowIso)
        .gt('ends_at', nowIso)
        .order('created_at')
        .timeout(_timeout);
    return (rows as List).map((r) => Ad.fromJson(Map<String, dynamic>.from(r as Map))).where((a) => a.isLive).toList();
  }

  Future<List<AdPackage>> packages() async {
    final rows = await _c.from('ad_packages').select().eq('is_active', true).order('sort').timeout(_timeout);
    return (rows as List).map((r) => AdPackage.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<String?> paymentInfo() async {
    final res = await _c.rpc('get_ad_payment_info').timeout(_timeout);
    return res is String && res.trim().isNotEmpty ? res : null;
  }

  Future<AdOrder> createOrder(String packageId, String? note) async {
    final row = await _c.rpc('create_ad_order', params: {'p_package': packageId, 'p_note': note}).timeout(_timeout);
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<AdOrder> createOrderRequest({
    required String packageId,
    required String title,
    required String imageUrl,
    required String destinationType,
    String? destinationUrl,
    required List<String> targetCountries,
    String? routeFrom,
    String? routeTo,
    String? note,
  }) async {
    final row = await _c.rpc('create_ad_order_request', params: {
      'p_package': packageId,
      'p_title': title,
      'p_image_url': imageUrl,
      'p_destination_type': destinationType,
      'p_destination_url': destinationUrl,
      'p_target_countries': targetCountries,
      'p_route_from': routeFrom,
      'p_route_to': routeTo,
      'p_note': note,
    }).timeout(_timeout);
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<void> submitPayment(String orderId, String? reference) async {
    await _c.rpc('submit_ad_payment', params: {'p_order': orderId, 'p_reference': reference}).timeout(_timeout);
  }

  Future<void> cancelOrder(String orderId) async {
    await _c.rpc('cancel_ad_order', params: {'p_order': orderId}).timeout(_timeout);
  }

  Future<String> uploadRequestedBanner(Uint8List bytes, String extension, String userId) async {
    final ext = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
    if (!const {'jpg', 'png', 'webp'}.contains(ext)) throw ArgumentError('unsupported_image_type');
    final path = 'requests/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _c.storage.from('ads').uploadBinary(path, bytes,
        fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _c.storage.from('ads').getPublicUrl(path);
  }

  Future<void> recordEvent(String adId, String eventType) async {
    if (eventType == 'impression' && !_impressionsRecordedThisSession.add(adId)) return;
    try {
      await _c.rpc('record_ad_event', params: {'p_ad': adId, 'p_type': eventType}).timeout(_timeout);
    } catch (_) {
      if (eventType == 'impression') _impressionsRecordedThisSession.remove(adId);
      // Metrics must not interrupt feed navigation or rendering.
    }
  }

  Future<Map<String, ({int impressions, int clicks})>> myAdStats() async {
    final rows = await _c.rpc('get_my_ad_stats').timeout(_timeout);
    return {
      for (final row in rows as List)
        '${row['order_id']}': (
          impressions: (row['impressions'] as num?)?.toInt() ?? 0,
          clicks: (row['clicks'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  Stream<List<AdOrder>> watchMyOrders(String uid) => _c
      .from('ad_orders')
      .stream(primaryKey: ['id'])
      .eq('advertiser_id', uid)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(AdOrder.fromJson).toList());

  // ---- admin ------------------------------------------------------------

  Stream<List<AdOrder>> watchAllOrders() => _c
      .from('ad_orders')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500)
      .map((rows) => rows.map(AdOrder.fromJson).toList());

  Stream<List<Ad>> watchAllAds() => _c
      .from('ads')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500)
      .map((rows) => rows.map(Ad.fromJson).toList());

  Future<List<AdPackage>> allPackages() async {
    final rows = await _c.from('ad_packages').select().order('sort').timeout(_timeout);
    return (rows as List).map((r) => AdPackage.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<Map<String, dynamic>> adCounts() async {
    final res = await _c.rpc('admin_ad_counts').timeout(_timeout);
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  Future<void> updateOrder(String orderId, {String? status, String? paymentStatus, String? note}) async {
    await _c.rpc('admin_update_ad_order', params: {
      'p_order': orderId,
      'p_status': status,
      'p_payment_status': paymentStatus,
      'p_note': note,
    }).timeout(_timeout);
  }

  Future<void> saveAd({
    String? adId,
    String? orderId,
    required String advertiserId,
    String? title,
    required String imageUrl,
    required DateTime startsAt,
    required DateTime endsAt,
    required bool active,
  }) async {
    await _c.rpc('admin_save_ad', params: {
      'p_ad': adId,
      'p_order': orderId,
      'p_advertiser': advertiserId,
      'p_title': title,
      'p_image_url': imageUrl,
      'p_starts': startsAt.toUtc().toIso8601String(),
      'p_ends': endsAt.toUtc().toIso8601String(),
      'p_active': active,
    }).timeout(_timeout);
  }

  Future<void> setAdActive(String adId, bool active) async {
    await _c.rpc('admin_set_ad_active', params: {'p_ad': adId, 'p_active': active}).timeout(_timeout);
  }

  Future<void> savePackage(AdPackage p) async {
    await _c.rpc('admin_save_ad_package', params: {
      'p_id': p.id,
      'p_name': p.name,
      'p_days': p.days,
      'p_price': p.price,
      'p_active': p.isActive,
    }).timeout(_timeout);
  }

  Future<void> setPaymentInfo(String text) async {
    await _c.rpc('admin_set_ad_payment_info', params: {'p_text': text}).timeout(_timeout);
  }

  /// Uploads a banner to the public "ads" bucket (admins only) and
  /// returns its public URL.
  Future<String> uploadBanner(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
    final path = 'banners/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _c.storage
        .from('ads')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _c.storage.from('ads').getPublicUrl(path);
  }
}

final adsRepositoryProvider = Provider<AdsRepository>((ref) => AdsRepository());

/// 0021 — templates, template orders, receipts, home-feed switch.
extension AdTemplatesApi on AdsRepository {
  SupabaseClient get _db => SupabaseConfig.client;

  static bool _missing(Object e) =>
      e is PostgrestException && (e.code == 'PGRST202' || e.code == 'PGRST205' || e.code == '42P01' || e.code == '42883');

  /// Ads for the home feed: [] while the admin switch is off (default) or
  /// before migration 0021 exists.
  Future<List<Ad>> homeFeedAds() async {
    try {
      final res = await _db.rpc('home_feed_ads').timeout(_timeout);
      final list = res is List ? res : const [];
      return list.map((r) => Ad.fromJson(Map<String, dynamic>.from(r as Map))).where((a) => a.isLive).toList();
    } catch (e) {
      if (_missing(e)) return const [];
      rethrow;
    }
  }

  Future<bool> homeAdsEnabled() async {
    try {
      final res = await _db.rpc('home_ads_enabled').timeout(_timeout);
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setHomeAdsEnabled(bool on) async {
    await _db.rpc('admin_set_home_ads_enabled', params: {'p_enabled': on}).timeout(_timeout);
  }

  /// Ad position / rotation in the loads list; defaults before 0025 or on error.
  Future<AdFeedLayout> feedLayout() async {
    try {
      final res = await _db.rpc('ads_feed_layout').timeout(_timeout);
      if (res is Map) return AdFeedLayout.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {}
    return AdFeedLayout.defaults;
  }

  Future<void> setFeedLayout({required int firstAfter, required int every, required int rotateMinutes, required bool repeat}) async {
    await _db.rpc('admin_set_ads_feed_layout', params: {
      'p_first_after': firstAfter,
      'p_every': every,
      'p_rotate_minutes': rotateMinutes,
      'p_repeat': repeat,
    }).timeout(_timeout);
  }

  /// Admin: ads in the wanted order (first = shown first in the loads list).
  Future<void> setAdsOrder(List<String> adIds) async {
    await _db.rpc('admin_set_ads_order', params: {'p_ids': adIds}).timeout(_timeout);
  }

  Future<List<AdTemplate>> templates({bool all = false}) async {
    var q = _db.from('ad_templates').select();
    if (!all) q = q.eq('is_active', true);
    final rows = await q.order('sort').order('created_at').timeout(_timeout);
    return (rows as List).map((r) => AdTemplate.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<AdOrder> createOrderFromTemplate({
    required String templateId,
    required Map<String, String> texts,
    required String color,
    required int days,
    required DateTime startsOn,
    required String destinationType,
    String? destinationUrl,
    required List<String> targetCountries,
    String? routeFrom,
    String? routeTo,
    String? note,
    String? logoUrl,
  }) async {
    final d = '${startsOn.year.toString().padLeft(4, '0')}-${startsOn.month.toString().padLeft(2, '0')}-${startsOn.day.toString().padLeft(2, '0')}';
    final row = await _db.rpc('create_ad_order_from_template', params: {
      'p_template': templateId,
      'p_texts': texts,
      'p_color': color,
      'p_days': days,
      'p_starts_on': d,
      'p_destination_type': destinationType,
      'p_destination_url': destinationUrl,
      'p_target_countries': targetCountries,
      'p_route_from': routeFrom,
      'p_route_to': routeTo,
      'p_note': note,
      'p_logo_url': logoUrl,
    }).timeout(_timeout);
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  /// Uploads the receipt photo into the private bucket and attaches it to
  /// the order ("Yoxlanılır"). It does NOT confirm the payment.
  Future<AdOrder> uploadReceipt({required String userId, required String orderId, required Uint8List bytes, required String ext}) async {
    final e = ext.toLowerCase() == 'jpeg' ? 'jpg' : ext.toLowerCase();
    final type = switch (e) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      _ => 'image/jpeg',
    };
    final path = '$userId/$orderId/${DateTime.now().millisecondsSinceEpoch}.$e';
    await _db.storage
        .from('ad-receipts')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type))
        .timeout(const Duration(minutes: 2));
    final row = await _db.rpc('submit_ad_receipt', params: {'p_order': orderId, 'p_path': path}).timeout(_timeout);
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<String> receiptUrl(String path) => _db.storage.from('ad-receipts').createSignedUrl(path, 60 * 30);

  Future<void> reviewOrder(String orderId, {required bool approve, String? note}) async {
    await _db.rpc('admin_review_ad_order', params: {'p_order': orderId, 'p_approve': approve, 'p_note': note}).timeout(_timeout);
  }

  Future<AdTemplate> saveTemplate({String? id, required String name, required String imageUrl,
      required List<AdTemplateField> fields, required List<String> colors, required bool active, int sort = 100,
      AdLogoSlot? logo}) async {
    final row = await _db.rpc('admin_save_ad_template', params: {
      'p_id': id,
      'p_data': {
        'name': name,
        'image_url': imageUrl,
        'fields': fields.map((f) => f.toJson()).toList(),
        'colors': colors,
        'logo': logo?.toJson(),
        'is_active': active,
        'sort': sort,
      },
    }).timeout(_timeout);
    final m = row is List ? row.first : row;
    return AdTemplate.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<void> setTemplateActive(String id, bool active) async {
    await _db.rpc('admin_set_ad_template_active', params: {'p_id': id, 'p_active': active}).timeout(_timeout);
  }

  /// Template backgrounds live in the public "ads" bucket (admins only).
  Future<String> uploadTemplateImage(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
    final path = 'templates/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _db.storage
        .from('ads')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _db.storage.from('ads').getPublicUrl(path);
  }
}



/// 0023 — standard 1200×400 layout, order editing, second switch,
/// admin link / dates, template delete.
extension AdsStandardApi on AdsRepository {
  SupabaseClient get _sb => SupabaseConfig.client;

  Map<String, dynamic> _v2Params({
    required String templateId,
    required Map<String, String> texts,
    required Map<String, AdTextStyle> style,
    String? logoUrl,
    required String logoBg,
  }) =>
      {
        'p_template': templateId.isEmpty ? null : templateId,
        'p_texts': texts,
        'p_style': {for (final e in style.entries) e.key: e.value.toJson()},
        'p_logo_url': logoUrl,
        'p_logo_bg': logoBg,
      };

  Future<AdOrder> createOrderV2({
    required String templateId,
    required Map<String, String> texts,
    required Map<String, AdTextStyle> style,
    String? logoUrl,
    required String logoBg,
    required int days,
    /// null = no date from the customer: the ad starts when the admin approves.
    DateTime? startsOn,
    required String destinationType,
    String? destinationUrl,
    required List<String> targetCountries,
    String? routeFrom,
    String? routeTo,
    String? note,
  }) async {
    final d = startsOn == null
        ? null
        : '${startsOn.year.toString().padLeft(4, '0')}-${startsOn.month.toString().padLeft(2, '0')}-${startsOn.day.toString().padLeft(2, '0')}';
    final row = await _sb.rpc('create_ad_order_v2', params: {
      ..._v2Params(templateId: templateId, texts: texts, style: style, logoUrl: logoUrl, logoBg: logoBg),
      'p_days': days,
      'p_starts_on': d,
      'p_destination_type': destinationType,
      'p_destination_url': destinationUrl,
      'p_target_countries': targetCountries,
      'p_route_from': routeFrom,
      'p_route_to': routeTo,
      'p_note': note,
    }).timeout(const Duration(seconds: 20));
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  /// Customer edit until the admin approves (after a receipt the order goes
  /// back to the admin's review — enforced on the server).
  Future<AdOrder> updateOrderV2({
    required String orderId,
    required String templateId,
    required Map<String, String> texts,
    required Map<String, AdTextStyle> style,
    String? logoUrl,
    required String logoBg,
  }) async {
    final row = await _sb.rpc('update_my_ad_order_v2', params: {
      'p_order': orderId,
      ..._v2Params(templateId: templateId, texts: texts, style: style, logoUrl: logoUrl, logoBg: logoBg),
    }).timeout(const Duration(seconds: 20));
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<bool> adsOrderingEnabled() async {
    try {
      final res = await _sb.rpc('ads_ordering_enabled').timeout(const Duration(seconds: 20));
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setAdsOrderingEnabled(bool on) async {
    await _sb.rpc('admin_set_ads_ordering_enabled', params: {'p_enabled': on}).timeout(const Duration(seconds: 20));
  }

  Future<AdTemplate> saveTemplateV2({String? id, required String name, required String imageUrl, required bool active, required int sort}) async {
    final row = await _sb.rpc('admin_save_ad_template_v2', params: {
      'p_id': id,
      'p_name': name,
      'p_image_url': imageUrl,
      'p_active': active,
      'p_sort': sort,
    }).timeout(const Duration(seconds: 20));
    final m = row is List ? row.first : row;
    return AdTemplate.fromJson(Map<String, dynamic>.from(m as Map));
  }

  /// Admin: who a template is for — 'cargo', 'service' or 'all' (0029).
  Future<void> setTemplateAudience(String id, String audience) async {
    await _sb.rpc('admin_set_ad_template_audience', params: {'p_id': id, 'p_audience': audience}).timeout(const Duration(seconds: 20));
  }

  /// Service owner: an ad for his own service only (0029) — leads to the
  /// service page, countries only (no route).
  Future<AdOrder> createServiceOrder({
    required String serviceId,
    required String templateId,
    required Map<String, String> texts,
    required Map<String, AdTextStyle> style,
    String? logoUrl,
    required String logoBg,
    required int days,
    required List<String> targetCountries,
    String? note,
  }) async {
    final row = await _sb.rpc('create_service_ad_order', params: {
      'p_service': serviceId,
      ..._v2Params(templateId: templateId, texts: texts, style: style, logoUrl: logoUrl, logoBg: logoBg),
      'p_days': days,
      'p_target_countries': targetCountries,
      'p_note': note,
    }).timeout(const Duration(seconds: 20));
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<void> deleteTemplate(String id) async {
    await _sb.rpc('admin_delete_ad_template', params: {'p_id': id}).timeout(const Duration(seconds: 20));
  }

  /// Admin: edit an order or its published ad — banner, link, target
  /// countries, route (country codes) and, for a published ad, the dates.
  Future<AdOrder> adminUpdateOrderV2({
    required String orderId,
    required String templateId,
    required Map<String, String> texts,
    required Map<String, AdTextStyle> style,
    String? logoUrl,
    required String logoBg,
    required String destinationType,
    String? destinationUrl,
    required List<String> targetCountries,
    String? routeFrom,
    String? routeTo,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final row = await _sb.rpc('admin_update_ad_order_v2', params: {
      'p_order': orderId,
      ..._v2Params(templateId: templateId, texts: texts, style: style, logoUrl: logoUrl, logoBg: logoBg),
      'p_destination_type': destinationType,
      'p_destination_url': destinationUrl,
      'p_target_countries': targetCountries,
      'p_route_from': routeFrom,
      'p_route_to': routeTo,
      'p_starts': startsAt?.toUtc().toIso8601String(),
      'p_ends': endsAt?.toUtc().toIso8601String(),
    }).timeout(const Duration(seconds: 20));
    final m = row is List ? row.first : row;
    return AdOrder.fromJson(Map<String, dynamic>.from(m as Map));
  }

  Future<void> updateAdLinkDates(String adId,
      {required String destinationType, String? destinationUrl, required DateTime startsAt, required DateTime endsAt}) async {
    await _sb.rpc('admin_update_ad_link_dates', params: {
      'p_ad': adId,
      'p_destination_type': destinationType,
      'p_destination_url': destinationUrl,
      'p_starts': startsAt.toUtc().toIso8601String(),
      'p_ends': endsAt.toUtc().toIso8601String(),
    }).timeout(const Duration(seconds: 20));
  }

  /// Logo upload: only PNG / JPEG / WEBP up to 2 MB that really decode as
  /// images (checked by the caller); stored in the customer's own folder.
  Future<String> uploadLogo(Uint8List bytes, String ext, String userId) async {
    final e = ext.toLowerCase() == 'jpeg' ? 'jpg' : ext.toLowerCase();
    if (!const {'png', 'jpg', 'webp'}.contains(e)) throw ArgumentError('unsupported_image_type');
    if (bytes.length > 2 * 1024 * 1024) throw ArgumentError('too_big');
    final path = 'requests/$userId/logo_${DateTime.now().millisecondsSinceEpoch}.$e';
    await _sb.storage
        .from('ads')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _sb.storage.from('ads').getPublicUrl(path);
  }
}

/// 0032 — a service owner's own picture as the ad background.
extension OwnAdBackgroundApi on AdsRepository {
  /// Uploads the (already 1200×400) PNG into my own folder and turns it
  /// into a private service-ad background only I can use.
  Future<AdTemplate> createOwnBackground(Uint8List png, String userId) async {
    final url = await uploadRequestedBanner(png, 'png', userId);
    final row = await SupabaseConfig.client
        .rpc('create_own_ad_background', params: {'p_image_url': url})
        .timeout(_timeout);
    final m = row is List ? row.first : row;
    return AdTemplate.fromJson(Map<String, dynamic>.from(m as Map));
  }
}

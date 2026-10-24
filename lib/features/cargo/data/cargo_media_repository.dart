import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/cargo_model.dart';
import '../domain/cargo_pictures.dart';

const _timeout = Duration(seconds: 20);

class CargoTemplate {
  final String id;
  final String category;
  final String imageUrl;
  const CargoTemplate({required this.id, required this.category, required this.imageUrl});

  factory CargoTemplate.fromJson(Map<String, dynamic> j) =>
      CargoTemplate(id: '${j['id']}', category: '${j['category']}', imageUrl: '${j['image_url']}');
}

/// Load pictures, templates and favourite loads (migration 0058). The
/// database decides who may do what (RLS, admin checks in the RPCs).
class CargoMediaRepository {
  final SupabaseClient _c = SupabaseConfig.client;

  String? get _me => _c.auth.currentUser?.id;

  // ---- templates -----------------------------------------------------------

  Future<List<CargoTemplate>> templates(String category) async {
    final rows = await _c
        .from('cargo_image_templates')
        .select()
        .eq('category', category)
        // (order() is newest-first unless told otherwise)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true)
        .timeout(_timeout);
    return [for (final r in rows as List) CargoTemplate.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> addTemplate(String category, String url) =>
      _c.rpc('admin_add_cargo_image_template', params: {'p_category': category, 'p_image_url': url}).timeout(_timeout);

  Future<void> deleteTemplate(String id) =>
      _c.rpc('admin_delete_cargo_image_template', params: {'p_id': id}).timeout(_timeout);

  Future<void> reorderTemplates(String category, List<String> ids) => _c
      .rpc('admin_reorder_cargo_image_templates', params: {'p_category': category, 'p_ids': ids}).timeout(_timeout);

  Future<void> adminClearImage(String cargoId) =>
      _c.rpc('admin_clear_cargo_image', params: {'p_cargo': cargoId}).timeout(_timeout);

  // ---- pictures (public bucket) -------------------------------------------

  /// Pictures the app accepts (the bucket allows up to 5 MB).
  static const maxBytes = 5 * 1024 * 1024;
  static const types = ['jpg', 'jpeg', 'png', 'webp'];

  /// Why a picture cannot be uploaded (i18n key), or null when it is fine.
  static String? checkUpload(int bytes, String ext) {
    if (!types.contains(ext.toLowerCase())) return 'cargo_pics_bad_type';
    if (bytes > maxBytes) return 'cargo_pics_too_big';
    return null;
  }

  /// Uploads a picture: the user's own folder, or (admin) the templates
  /// folder of [templateCategory]. Returns its public address.
  Future<String> upload(Uint8List bytes, String ext, {String? templateCategory}) async {
    final path = cargoPhotoPath(
        userId: _me ?? 'anon', ext: ext, templateCategory: templateCategory, stamp: DateTime.now().microsecondsSinceEpoch);
    final e = path.split('.').last;
    await _c.storage
        .from(kCargoPhotoBucket)
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return cleanStorageUrl(_c.storage.from(kCargoPhotoBucket).getPublicUrl(path));
  }

  /// Deletes one of my own uploaded pictures (templates are never deleted
  /// here: other loads may use them).
  Future<void> removeOwn(String url) async {
    final me = _me;
    if (me == null || !isOwnCargoPhoto(url, me)) return;
    final i = url.indexOf('/$kCargoPhotoBucket/');
    final path = Uri.decodeComponent(url.substring(i + kCargoPhotoBucket.length + 2));
    try {
      await _c.storage.from(kCargoPhotoBucket).remove([path]).timeout(_timeout);
    } catch (_) {
      // A file left behind costs nothing; the load is already saved.
    }
  }

  // ---- optional contact number of a load (0060) ---------------------------

  /// My load's own contact number (owner only, RLS); null = none / 0060
  /// not run yet.
  Future<String?> contactPhone(String cargoId) async {
    try {
      final row = await _c.from('cargo_contacts').select('phone').eq('cargo_id', cargoId).maybeSingle().timeout(_timeout);
      return row?['phone'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Saves (or with null removes) my load's contact number, already in
  /// international format. Throws when the server refuses / 0060 is
  /// missing — the load itself is saved before this.
  Future<void> setContactPhone(String cargoId, String? phone) async {
    if (phone == null) {
      await _c.from('cargo_contacts').delete().eq('cargo_id', cargoId).timeout(_timeout);
    } else {
      await _c
          .from('cargo_contacts')
          .upsert({'cargo_id': cargoId, 'phone': phone, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .timeout(_timeout);
    }
  }

  /// The owner sets the pictures of his own load (main first; empty =
  /// none). Only the pictures change (RLS: owner only; 0058 / 0060 checks:
  /// our bucket only, at most 6). Until 0060 is run only the main one.
  Future<void> setCargoPictures(String cargoId, List<String> urls) async {
    try {
      await _c
          .from('cargo')
          .update({'image_urls': urls, 'image_url': urls.isEmpty ? null : urls.first})
          .eq('id', cargoId)
          .timeout(_timeout);
    } on PostgrestException catch (e) {
      if (!((e.code == 'PGRST204' || e.code == '42703') && e.message.contains('image_urls'))) rethrow;
      await _c.from('cargo').update({'image_url': urls.isEmpty ? null : urls.first}).eq('id', cargoId).timeout(_timeout);
    }
  }

  // ---- favourites ("Seçilmiş yüklər") -------------------------------------

  Future<Set<String>> favoriteIds() async {
    if (_me == null) return const {};
    final rows = await _c.from('cargo_favorites').select('cargo_id').timeout(_timeout);
    return {for (final r in rows as List) '${r['cargo_id']}'};
  }

  /// My favourite loads, newest favourite first. A load that was deleted
  /// is gone from the list; a closed or hidden one is not shown.
  Future<List<CargoModel>> favorites() async {
    if (_me == null) return const [];
    final favs = await _c.from('cargo_favorites').select('cargo_id').order('created_at', ascending: false).timeout(_timeout);
    final ids = [for (final r in favs as List) '${r['cargo_id']}'];
    if (ids.isEmpty) return const [];
    final rows = await _c.from('cargo').select().inFilter('id', ids).timeout(_timeout);
    final byId = {for (final r in rows as List) '${r['id']}': CargoModel.fromJson(Map<String, dynamic>.from(r as Map))};
    return [
      for (final id in ids)
        if (byId[id] case final c? when c.status == 'new' && !c.isHidden) c,
    ];
  }

  Future<void> setFavorite(String cargoId, bool on) async {
    final me = _me;
    if (me == null) return;
    if (on) {
      await _c.from('cargo_favorites').upsert({'user_id': me, 'cargo_id': cargoId}).timeout(_timeout);
    } else {
      await _c.from('cargo_favorites').delete().eq('user_id', me).eq('cargo_id', cargoId).timeout(_timeout);
    }
  }
}

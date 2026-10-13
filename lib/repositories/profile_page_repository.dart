import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../features/auth/presentation/providers/auth_providers.dart';

/// Extra, WhatsApp-business-style profile info (migration 0031).
class ProfileDetails {
  final String userId;
  final String? about;
  final String? workHours;
  final String? address;
  final String? coverUrl;

  const ProfileDetails({required this.userId, this.about, this.workHours, this.address, this.coverUrl});

  bool get isEmpty =>
      (about ?? '').trim().isEmpty && (workHours ?? '').trim().isEmpty && (address ?? '').trim().isEmpty && (coverUrl ?? '').isEmpty;

  factory ProfileDetails.fromJson(Map<String, dynamic> j) => ProfileDetails(
        userId: '${j['user_id']}',
        about: j['about'] as String?,
        workHours: j['work_hours'] as String?,
        address: j['address'] as String?,
        coverUrl: j['cover_url'] as String?,
      );
}

/// One photo of the user's work in their catalog, with a short caption.
class CatalogItem {
  final String id;
  final String userId;
  final String imagePath;
  final String imageUrl;
  final String? caption;
  final DateTime createdAt;

  const CatalogItem({
    required this.id,
    required this.userId,
    required this.imagePath,
    required this.imageUrl,
    this.caption,
    required this.createdAt,
  });
}

/// A service owned by the user (shown on their profile, links to it).
class OwnedService {
  final String id;
  final String name;
  const OwnedService({required this.id, required this.name});
}

class ProfilePageRepository {
  final SupabaseClient _client = SupabaseConfig.client;
  static const bucket = 'profile-media';
  static const maxCaption = 300;

  String? get _uid => _client.auth.currentUser?.id;

  String publicUrl(String path) => _client.storage.from(bucket).getPublicUrl(path);

  Future<ProfileDetails?> details(String userId) async {
    final row = await _client.from('profile_details').select().eq('user_id', userId).maybeSingle();
    return row == null ? null : ProfileDetails.fromJson(row);
  }

  Future<void> saveDetails({String? about, String? workHours, String? address}) async {
    final uid = _uid;
    if (uid == null) throw StateError('not_signed_in');
    String? clean(String? v) => (v ?? '').trim().isEmpty ? null : v!.trim();
    await _client.from('profile_details').upsert({
      'user_id': uid,
      'about': clean(about),
      'work_hours': clean(workHours),
      'address': clean(address),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<void> uploadCover(Uint8List bytes, {String? contentType}) async {
    final uid = _uid;
    if (uid == null) throw StateError('not_signed_in');
    final path = '$uid/cover';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType ?? 'image/jpeg'),
        );
    final url = '${publicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('profile_details').upsert({
      'user_id': uid,
      'cover_url': url,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  /// The owner's chosen order (migration 0035); photos without a saved
  /// position (new uploads) first, newest first — the same for everyone.
  Future<List<CatalogItem>> catalog(String userId) async {
    List<dynamic> rows;
    try {
      rows = await _client
          .from('profile_catalog_items')
          .select()
          .eq('user_id', userId)
          .order('sort_order', ascending: true, nullsFirst: true)
          .order('created_at', ascending: false);
    } on PostgrestException catch (e) {
      // Before migration 0035 there is no sort_order column: old order.
      if (e.code != '42703' && !e.message.contains('sort_order')) rethrow;
      rows = await _client
          .from('profile_catalog_items')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
    }
    return [
      for (final r in rows)
        CatalogItem(
          id: '${r['id']}',
          userId: '${r['user_id']}',
          imagePath: '${r['image_path']}',
          imageUrl: publicUrl('${r['image_path']}'),
          caption: r['caption'] as String?,
          createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
        ),
    ];
  }

  Future<void> addCatalogItem(Uint8List bytes, {String? caption, String? contentType}) async {
    final uid = _uid;
    if (uid == null) throw StateError('not_signed_in');
    final ext = (contentType ?? '').contains('png') ? 'png' : ((contentType ?? '').contains('webp') ? 'webp' : 'jpg');
    final path = '$uid/catalog/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: false, contentType: contentType ?? 'image/jpeg'),
        );
    try {
      await _client.from('profile_catalog_items').insert({
        'user_id': uid,
        'image_path': path,
        'caption': (caption ?? '').trim().isEmpty ? null : caption!.trim(),
      });
    } catch (_) {
      // Don't leave an orphan file when the row could not be saved.
      await _client.storage.from(bucket).remove([path]).catchError((_) => <FileObject>[]);
      rethrow;
    }
  }

  /// Saves the owner's new photo order in one step (RPC, migration 0035).
  /// [ids] must be all of the owner's photos, each once — the server
  /// refuses anything else, so no photo can be lost or duplicated.
  Future<void> reorderCatalog(List<String> ids) async {
    await _client.rpc('reorder_catalog', params: {'p_ids': ids});
  }

  Future<void> updateCaption(String itemId, String? caption) async {
    await _client
        .from('profile_catalog_items')
        .update({'caption': (caption ?? '').trim().isEmpty ? null : caption!.trim()})
        .eq('id', itemId);
  }

  Future<void> deleteCatalogItem(CatalogItem item) async {
    await _client.from('profile_catalog_items').delete().eq('id', item.id);
    await _client.storage.from(bucket).remove([item.imagePath]).catchError((_) => <FileObject>[]);
  }

  Future<List<OwnedService>> ownedServices(String userId) async {
    final rows = await _client.from('service_providers').select('id,name').eq('owner_id', userId);
    return [for (final r in rows as List) OwnedService(id: '${r['id']}', name: '${r['name']}')];
  }
}

final profilePageRepositoryProvider = Provider<ProfilePageRepository>((ref) => ProfilePageRepository());

/// Null when the user has not filled anything in (or before 0031).
final profileDetailsProvider = FutureProvider.family<ProfileDetails?, String>((ref, userId) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.read(profilePageRepositoryProvider).details(userId);
  } catch (_) {
    return null;
  }
});

final profileCatalogProvider = FutureProvider.family<List<CatalogItem>, String>((ref, userId) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.read(profilePageRepositoryProvider).catalog(userId);
  } catch (_) {
    return const <CatalogItem>[];
  }
});

final ownedServicesProvider = FutureProvider.family<List<OwnedService>, String>((ref, userId) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.read(profilePageRepositoryProvider).ownedServices(userId);
  } catch (_) {
    return const <OwnedService>[];
  }
});

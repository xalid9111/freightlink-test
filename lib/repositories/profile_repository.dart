import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../features/auth/presentation/providers/auth_providers.dart';

/// What a signed-in user may see about a user. For OTHER users this comes
/// from the public view user_profiles (migration 0019): phone and the
/// moderation fields are then null/false — phone is fetched separately
/// with [UserContact]. For the signed-in user it is their full own row.
/// Fields are read defensively, so older databases still work.
class PublicProfile {
  final String id;
  final String fullName;
  final String? phone;
  final String? avatarUrl;
  final DateTime? lastSeenAt;
  final bool isVerified;
  final bool isEarlyMember;

  /// Account role and moderation state (migration 0012).
  final String? role;
  final bool isBlocked;
  final DateTime? blockedUntil;
  final String? blockReason;
  final bool isActive;

  const PublicProfile({
    required this.id,
    required this.fullName,
    this.phone,
    this.avatarUrl,
    this.lastSeenAt,
    this.isVerified = false,
    this.isEarlyMember = false,
    this.role,
    this.isBlocked = false,
    this.blockedUntil,
    this.blockReason,
    this.isActive = true,
  });

  /// True while the account may not post loads, offers or messages.
  bool get isRestricted {
    if (!isActive) return true;
    if (!isBlocked) return false;
    return blockedUntil == null || blockedUntil!.isAfter(DateTime.now());
  }

  factory PublicProfile.fromJson(Map<String, dynamic> j) {
    final seen = j['last_seen_at'];
    return PublicProfile(
      id: j['id'] as String,
      fullName: (j['full_name'] as String?) ?? '',
      phone: j['phone'] as String?,
      avatarUrl: j['avatar_url'] as String?,
      lastSeenAt: seen is String ? DateTime.tryParse(seen) : null,
      isVerified: j['is_verified'] == true,
      isEarlyMember: j['is_early_member'] == true,
      role: j['role'] as String?,
      isBlocked: j['is_blocked'] == true,
      blockedUntil: j['blocked_until'] is String ? DateTime.tryParse(j['blocked_until'] as String) : null,
      blockReason: j['block_reason'] as String?,
      isActive: j['is_active'] != false,
    );
  }

  /// "XX" style initials for avatar placeholders.
  String get initials {
    final parts = fullName.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = String.fromCharCode(parts.first.runes.first);
    final b = parts.length > 1 ? String.fromCharCode(parts[1].runes.first) : '';
    return (a + b).toUpperCase();
  }
}

class ProfileRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  /// Columns of the public profile view (migration 0019).
  static const _publicCols =
      'id,role,full_name,avatar_url,is_verified,is_early_member,last_seen_at,is_active,created_at';

  Future<PublicProfile?> fetch(String userId) async {
    // Own profile: the full own row (incl. phone and block state for the
    // restriction banner). RLS (0019) lets a user read only their own row.
    if (userId == _client.auth.currentUser?.id) {
      final row = await _client.from('users').select('*').eq('id', userId).maybeSingle();
      return row == null ? null : PublicProfile.fromJson(row);
    }
    // Anyone else: public fields only, from the user_profiles view. Phone
    // and e-mail are no longer part of a profile — see contact().
    try {
      final row = await _client.from('user_profiles').select(_publicCols).eq('id', userId).maybeSingle();
      return row == null ? null : PublicProfile.fromJson(row);
    } on PostgrestException catch (e) {
      if (!isMissingRelation(e)) rethrow;
      // Migration 0019 not applied yet: the old table read still works.
      final row = await _client.from('users').select('*').eq('id', userId).maybeSingle();
      return row == null ? null : PublicProfile.fromJson(row);
    }
  }

  /// Phone / e-mail of [userId] as far as the server allows the caller to
  /// see them (RPC get_user_contact, migration 0019): own data, admins,
  /// a paid contact unlock, the person wrote to you, or the person runs a
  /// live advert / has an open load. Otherwise phone and e-mail are null.
  Future<UserContact> contact(String userId) async {
    try {
      final res = await _client.rpc('get_user_contact', params: {'p_user': userId});
      if (res is! Map) return const UserContact();
      return UserContact.fromJson(Map<String, dynamic>.from(res));
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      // 0019 not applied yet: contact data is still on the users row.
      final row = await _client.from('users').select('full_name,phone,email').eq('id', userId).maybeSingle();
      return row == null ? const UserContact() : UserContact.fromJson(row);
    }
  }

  /// Records "now" as the signed-in user's last activity (own row only —
  /// RLS users_update_self). Silently ignored if migration 0009 hasn't
  /// added the column yet.
  Future<void> touchLastSeen() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('users').update({'last_seen_at': DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
    } catch (_) {}
  }

  /// Renames the signed-in user (company or person name shown to others).
  Future<void> updateName(String name) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('not signed in');
    await _client.from('users').update({'full_name': name.trim()}).eq('id', uid);
  }

  /// Saves the signed-in user's phone (E.164, e.g. +994501234567) on
  /// their own row (RLS users_update_self). Throws [PhoneTakenException]
  /// if another account already uses it (users.phone is unique).
  Future<void> updatePhone(String phone) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('not signed in');
    try {
      await _client.from('users').update({'phone': phone}).eq('id', uid);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const PhoneTakenException();
      rethrow;
    }
  }

  /// Uploads a profile photo to storage bucket "avatars" under the
  /// user's own folder (policy avatars_insert_own, migration 0009) and
  /// stores its public URL on the user row. Returns the new URL.
  Future<String> uploadAvatar(Uint8List bytes, {String? contentType}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('not signed in');
    final path = '$uid/avatar';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType ?? 'image/jpeg'),
        );
    // Cache-buster so every client shows the new photo immediately.
    final url = '${_client.storage.from('avatars').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    await _client.from('users').update({'avatar_url': url}).eq('id', uid);
    return url;
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository());

final publicProfileProvider = FutureProvider.family<PublicProfile?, String>((ref, userId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).fetch(userId);
});

/// Contact data the server releases to the signed-in user (see
/// ProfileRepository.contact). autoDispose: re-checked each time a screen
/// needs it, e.g. after the other person has written for the first time.
final userContactProvider = FutureProvider.autoDispose.family<UserContact, String>((ref, userId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(profileRepositoryProvider).contact(userId);
});

/// Result of get_user_contact / get_cargo_contact.
class UserContact {
  final String? fullName;
  final String? phone;
  final String? email;
  const UserContact({this.fullName, this.phone, this.email});

  factory UserContact.fromJson(Map<String, dynamic> j) => UserContact(
        fullName: j['full_name'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
      );
}

/// True when PostgREST reports that a table / view does not exist (yet),
/// e.g. user_profiles before migration 0019. PGRST205 = not in the schema
/// cache (PostgREST 12+), 42P01 = undefined_table (older versions).
bool isMissingRelation(PostgrestException e) => e.code == 'PGRST205' || e.code == '42P01';

class PhoneTakenException implements Exception {
  const PhoneTakenException();
}

// Profil → Şəxsi məlumatlarım: "Şifrəni yenilə" and "Hesabı sil"; a deleted
// user's ads leave every list (owner, 13.11.2026, SQL 0119).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/auth/presentation/profile_screen.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('the confirmation word in any case', () {
    expect(deleteWordMatches('sil', 'SİL'), isTrue);
    expect(deleteWordMatches(' SİL ', 'SİL'), isTrue);
    expect(deleteWordMatches('SIL', 'SİL'), isTrue);
    expect(deleteWordMatches('delete', 'DELETE'), isTrue);
    expect(deleteWordMatches('', 'SİL'), isFalse);
    expect(deleteWordMatches('si', 'SİL'), isFalse);
  });

  test('Şəxsi məlumatlarım: password and delete rows; the server function does the work', () {
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    final personal = p.substring(p.indexOf('class ProfilePersonalScreen'), p.indexOf('class ProfileActivityScreen'));
    expect(personal.contains("ValueKey('pf-change-password')") && personal.contains("context.pushOnce('/change-password')"), isTrue);
    expect(personal.contains("ValueKey('pf-delete-account')"), isTrue);
    expect(personal.contains('user.role != AppConstants.roleAdmin'), isTrue, reason: 'admins are not offered it');
    expect(p.contains("rpc('delete_my_account', params: {'p_confirm': 'DELETE'})"), isTrue);
    expect(p.contains('authRepositoryProvider).signOut()'), isTrue);
  });

  test('texts in all six languages', () {
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$l.json')) as Map<String, dynamic>;
      for (final k in ['pf_change_password', 'pf_change_password_sub', 'pf_delete_account', 'pf_delete_account_sub', 'pf_delete_word',
        'pf_delete_body', 'pf_delete_type', 'pf_delete_not_ready', 'pf_delete_failed', 'pf_delete_done', 'pf_my_trucks_sub']) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
      expect(m['pf_delete_type'], contains('{word}'), reason: l);
    }
  });

  test('SQL 0119: every kind of ad is hidden, nothing deleted; self-delete is checked on the server', () {
    final sql = src('supabase/migrations/0119_deleted_user_ads_self_delete.sql');
    for (final t in ['cargo', 'market_listings', 'service_providers', 'job_vacancies', 'job_seeker_profiles', 'empty_truck_ads']) {
      expect(sql.contains(t), isTrue, reason: t);
    }
    expect(RegExp(r'drop\s+table|truncate|delete\s+from\s+(public\.)?(cargo|market_listings|service_providers|messages|users)\b', caseSensitive: false)
        .hasMatch(sql), isFalse);
    expect(sql.contains("raise exception 'admin_cannot_delete'"), isTrue);
    expect(sql.contains('revoke all on function public._hide_user_ads(uuid) from public, anon, authenticated'), isTrue);
  });
}

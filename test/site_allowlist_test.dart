import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/site/site_access.dart';
import 'package:freightlink/features/auth/data/auth_repository_impl.dart' show isSiteClosedAuthError;

/// Who stays in a closed site (owner, 24.11.2026, SQL 0134): admins, the Baş
/// admin and the accounts given "Bağlı saytda girişə icazə"; everybody else
/// (visitors too) sees the notice.
void main() {
  test('a closed site blocks everybody but admins and allowed accounts', () {
    SiteStatus st(Map<String, dynamic> j) => SiteStatus.fromJson(j);
    expect(st({'closed': false}).blocks, isFalse, reason: 'open site: nobody');
    expect(st({'closed': true}).blocks, isTrue, reason: 'a visitor / an ordinary account');
    expect(st({'closed': true, 'admin': true, 'allowed': true}).blocks, isFalse, reason: 'admin / Baş admin');
    expect(st({'closed': true, 'allowed': true}).blocks, isFalse, reason: 'the chosen account');
    expect(st({'closed': true, 'admin': false, 'allowed': false}).blocks, isTrue);
  });

  test('the Auth hook\'s refusal is told as "the site is closed"', () {
    expect(isSiteClosedAuthError('site_closed: Sayt hazırda bağlıdır'), isTrue);
    expect(isSiteClosedAuthError('Invalid login credentials'), isFalse);
  });

  test('wired: the admin\'s switch per user, the server function, texts in 6 languages', () {
    final admin = File('lib/features/admin/presentation/admin_pages.dart').readAsStringSync();
    expect(admin, contains("ValueKey('admin-user-login-allowed')"));
    expect(admin, contains('setLoginAllowed('));
    final repo = File('lib/features/admin/data/admin_repository.dart').readAsStringSync();
    expect(repo, contains("rpc('admin_user_login_allowed_set'"));
    final sql = File('supabase/migrations/0134_login_allowlist.sql').readAsStringSync();
    expect(sql, contains("'allowed', auth.uid() is not null"));
    expect(sql, contains('create trigger zz_users_login_allowed_guard'));
    expect(sql, contains('exception when others then'), reason: 'a glitch never locks everybody out');
    expect(sql.contains('drop table'), isFalse);
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      expect(File('assets/i18n/$l.json').readAsStringSync(), contains('"error_site_closed"'), reason: l);
    }
  });
}

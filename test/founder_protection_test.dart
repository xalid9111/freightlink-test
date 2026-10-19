// Founder account (0045): only the founder changes it. The server rules are
// tested in supabase/tests/local/83_founder_protection.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/admin/data/admin_repository.dart';

void main() {
  test('a refused change says why', () {
    expect(adminErrorText(Exception('founder_protected')), contains('Founder'));
  });
  test('the lock is a trigger on every change of the founder\'s row', () {
    final sql = File('supabase/migrations/0045_founder_protection.sql').readAsStringSync();
    expect(sql.contains("where lower(u.email) = 'xelilov.1881@gmail.com'"), isTrue);
    expect(sql.contains('before update or delete on public.users'), isTrue);
    expect(sql.contains("raise exception 'founder_protected'"), isTrue);
    expect(sql.contains('revoke all on public.founders from anon, authenticated;'), isTrue);
  });
  test('admin panel shows the founder locked for other admins', () {
    final page = File('lib/features/admin/presentation/admin_pages.dart').readAsStringSync();
    expect(page.contains('final locked = founder && ref.watch(currentUserIdProvider) != id;'), isTrue);
  });
}

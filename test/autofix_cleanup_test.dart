import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/admin/presentation/admin_autofix_page.dart';

void main() {
  test('status chip tells who solved a problem', () {
    expect(autofixStatusLabel({'status': 'open'}), isNull);
    expect(autofixStatusLabel({'status': 'fixed', 'resolved_by': null}), 'həll olunub (avtomatik)');
    expect(autofixStatusLabel({'status': 'fixed', 'resolved_by': 'a0000000-0000-4000-8000-000000000001'}), 'həll olunub');
    expect(autofixStatusLabel({'status': 'ignored'}), 'gizlədilib');
  });

  test('automatic check waits 3 days', () {
    expect(kAutofixAutoResolveDays, 3);
  });

  test('0042 deletes only problems marked fixed, nothing else', () {
    final sql = File('supabase/migrations/0042_autofix_cleanup.sql').readAsStringSync().toLowerCase();
    final deletes = RegExp(r'delete\s+from\s+([a-z_.]+)([^;]*)').allMatches(sql).toList();
    expect(deletes, hasLength(1));
    expect(deletes.single.group(1), 'app_errors');
    expect(deletes.single.group(2), contains("where status = 'fixed'"));
    expect(sql, contains('_require_admin()'));
  });

  test('0057: old hidden problems are moved to solved too, nothing deleted', () {
    final sql = File('supabase/migrations/0057_autofix_resolve_hidden.sql').readAsStringSync().toLowerCase();
    expect(sql, contains("where status in ('open', 'ignored')"));
    expect(sql, contains("set status = 'fixed'"));
    expect(sql, contains('_require_admin()'));
    expect(RegExp(r'delete\s+from').hasMatch(sql), isFalse);
  });
}

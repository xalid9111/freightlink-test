// "Function not found" names the real SQL file (not a fixed "0012").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/admin/data/admin_repository.dart';
import 'package:freightlink/features/admin/data/rpc_migrations.dart';

void main() {
  test('every server function the app calls is mapped to the migration that creates it', () {
    final calls = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r"rpc\('([a-z0-9_]+)'").allMatches(f.readAsStringSync())) {
        calls.add(m.group(1)!);
      }
    }
    expect(calls, isNotEmpty);
    for (final fn in calls) {
      expect(kRpcMigration.containsKey(fn), isTrue, reason: '$fn missing in rpc_migrations.dart');
    }
    for (final e in kRpcMigration.entries) {
      final sql = File('supabase/migrations/${e.value}');
      expect(sql.existsSync(), isTrue, reason: e.value);
      expect(RegExp('function (public\\.)?${e.key}\\(').hasMatch(sql.readAsStringSync()), isTrue,
          reason: '${e.key} not created in ${e.value}');
    }
  });

  test('template "who is it for" save: names 0029', () {
    const raw = 'PGRST202 Could not find the function public.admin_set_ad_template_audience(p_audience, p_id) in the schema cache';
    final t = missingFunctionText(raw);
    expect(t, contains('admin_set_ad_template_audience'));
    expect(t, contains('0029_service_ads.sql'));
    expect(t, isNot(contains('0012')));
    expect(adminErrorText(Exception(raw)), t);
  });

  test('unknown function still gets a clear text', () {
    expect(missingFunctionText('Could not find the function public.something_new(p) in the schema cache'), contains('something_new'));
    expect(missingFunctionText('PGRST202'), contains('SQL'));
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/admin/data/admin_repository.dart';
import 'package:freightlink/features/admin/presentation/admin_purge_page.dart';
import 'package:freightlink/features/admin/presentation/admin_shell.dart';

String src(String p) => File(p).readAsStringSync();

class _Repo implements AdminRepository {
  final purged = <String>[];
  @override
  Future<List<Map<String, dynamic>>> purgeList(String kind, String query) async => [
        {'id': 'u1', 'title': 'Saxta Profil', 'sub': 'fake@t.test', 'at': '2026-11-01T10:00:00Z'},
      ];
  @override
  Future<void> purge(String kind, String id, String confirm) async => purged.add('$kind|$id|$confirm');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('Admin → Test məlumatlarını sil: nothing goes before SİL is typed; then exactly that item', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: AdminPurgePage())),
    ));
    await tester.pumpAndSettle();
    for (final k in ['user', 'cargo', 'service', 'market', 'job_vacancy', 'job_seeker', 'tir_park']) {
      expect(find.byKey(ValueKey('purge-kind-$k')), findsOneWidget, reason: k);
    }
    expect(find.text('Saxta Profil'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('purge-del-u1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('HƏR ŞEY birdəfəlik silinəcək'), findsOneWidget, reason: 'the warning says what goes');
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('purge-go'))).onPressed, isNull, reason: 'not before SİL');
    await tester.enterText(find.byKey(const ValueKey('purge-confirm')), 'si');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('purge-go'))).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('purge-confirm')), 'sil');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('purge-go')));
    await tester.pumpAndSettle();
    expect(repo.purged, ['user|u1|SİL']);
  });

  test('SİL typed on any keyboard counts; nothing else does', () {
    expect(AdminPurgeTestHook.typedSil('SİL'), isTrue);
    expect(AdminPurgeTestHook.typedSil(' sil '), isTrue);
    expect(AdminPurgeTestHook.typedSil('SIL'), isTrue);
    expect(AdminPurgeTestHook.typedSil('SILL'), isFalse);
    expect(AdminPurgeTestHook.typedSil(''), isFalse);
  });

  test('wired: admin section, server checks, no wiping at migration time', () {
    expect(adminSections.any((s) => s.key == 'purge'), isTrue);
    final sql = src('supabase/migrations/0083_admin_purge.sql');
    expect(sql, contains('perform public._require_admin();'));
    expect(sql, contains("if p_confirm is distinct from 'SİL' then raise exception 'confirm_required'"));
    expect(sql, contains("raise exception 'founder_protected'"));
    expect(sql, contains("raise exception 'admin_protected'"));
    expect(sql, contains("raise exception 'cannot_delete_self'"));
    expect(sql, contains('revoke all on function public._purge_rows(regclass, text, integer) from public, anon, authenticated;'));
    expect(sql, contains("perform public._admin_log('purge.' || p_kind"), reason: 'every deletion is logged');
    // Outside function bodies the file only creates functions.
    final outside = sql.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '').toLowerCase();
    expect(outside.contains('delete from'), isFalse, reason: 'running the SQL deletes nothing');
    expect(src('supabase/tests/local/run_local.sh'), contains('121_admin_purge.sql'));
    // 0084: + TIR parks, the same server checks.
    final parks = src('supabase/migrations/0084_admin_purge_tir_parks.sql');
    expect(parks, contains("when 'tir_park' then v_table := 'public.tir_parks'; v_key := 'id';"));
    expect(parks, contains("if p_confirm is distinct from 'SİL' then raise exception 'confirm_required'"));
    expect(parks, contains('perform public._require_admin();'));
    expect(parks.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '').toLowerCase().contains('delete from'), isFalse);
    expect(src('supabase/tests/local/run_local.sh'), contains('122_admin_purge_tir_parks.sql'));
  });
}

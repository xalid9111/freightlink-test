import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_repository.dart';
import 'admin_widgets.dart';

/// What the admin can delete for good (0083).
const adminPurgeKinds = <String, String>{
  'user': 'İstifadəçilər',
  'cargo': 'Yüklər',
  'service': 'Servislər',
  'market': 'TIR Bazarı elanları',
  'job_vacancy': 'İş elanları (vakansiya)',
  'job_seeker': 'Sürücü profilləri (İş Mərkəzi)',
  'tir_park': 'TIR parkları', // 0084
};

/// For tests: the SİL check of the confirm dialog.
class AdminPurgeTestHook {
  static bool typedSil(String v) => _AdminPurgePageState.typedSil(v);
}

final adminPurgeListProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String)>(
    (ref, q) => ref.watch(adminRepositoryProvider).purgeList(q.$1, q.$2));

/// Admin → "Test məlumatlarını sil" (owner, 02.11.2026, 0083): fake test
/// profiles, loads, services, TIR Bazarı sale ads and job ads are deleted
/// completely. A user goes with everything he has (loads, ads, chats and
/// messages, comments, bookings, test payments). Admins only — checked on
/// the server; the admin types SİL to confirm.
class AdminPurgePage extends ConsumerStatefulWidget {
  const AdminPurgePage({super.key});

  @override
  ConsumerState<AdminPurgePage> createState() => _AdminPurgePageState();
}

class _AdminPurgePageState extends ConsumerState<AdminPurgePage> {
  String _kind = 'user';
  String _query = '';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _warning => _kind == 'user'
      ? 'Hesab, girişi və ona aid HƏR ŞEY birdəfəlik silinəcək: yükləri, servisləri, TIR Bazarı və iş elanları, '
          'mesajları və söhbətləri (həqiqi istifadəçilərlə olanlar da), şərhləri, rezervasiyaları, test ödənişləri. '
          'Geri qaytarmaq olmur.'
      : 'Bu qeyd və ona bağlı hər şey (təkliflər, şərhlər, müraciətlər …) birdəfəlik silinəcək. Geri qaytarmaq olmur.';

  /// "SİL" typed on any keyboard ("sil", "SIL" with a Latin I) counts.
  static bool typedSil(String v) => const {'SIL', 'SİL'}.contains(v.trim().toUpperCase());

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = '${row['id']}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _PurgeDialog(title: 'Silinsin: ${row['title'] ?? ''}', warning: _warning),
    );
    if (ok != true || !mounted) return;
    final done = await runAdmin(context, () => ref.read(adminRepositoryProvider).purge(_kind, id, 'SİL'), success: 'Silindi');
    if (done) ref.invalidate(adminPurgeListProvider((_kind, _query)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminPurgeListProvider((_kind, _query)));
    final rows = async.valueOrNull ?? const <Map<String, dynamic>>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const SectionTitle('Test məlumatlarını sil'),
        Text(
          'Yoxlama üçün əlavə edilmiş saxta profilləri və elanları tamamilə silmək üçündür. '
          'Yalnız adminlər görür və edə bilər; hər silmə Audit Log-a yazılır.',
          style: TextStyle(color: AppColors.textSoft, height: 1.35),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in adminPurgeKinds.entries)
            ChoiceChip(
              key: ValueKey('purge-kind-${e.key}'),
              label: Text(e.value),
              selected: _kind == e.key,
              onSelected: (_) => setState(() => _kind = e.key),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('purge-search'),
          controller: _search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Ad, telefon, e-poçt, şəhər, marka …'),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
        const SizedBox(height: 12),
        if (async.isLoading && !async.hasValue) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
        if (async.hasError)
          Text('Yüklənmədi: ${adminErrorText(async.error!)}', style: TextStyle(color: AppColors.danger)),
        if (async.hasValue && rows.isEmpty) const EmptyNote('Heç nə tapılmadı'),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: AdminRow(
                  title: '${r['title'] ?? ''}',
                  subtitle: [
                    if ('${r['sub'] ?? ''}'.isNotEmpty) '${r['sub']}',
                    if (r['at'] != null) '${r['at']}'.substring(0, 10),
                  ].join(' · '),
                ),
              ),
              IconButton(
                key: ValueKey('purge-del-${r['id']}'),
                tooltip: 'Birdəfəlik sil',
                color: AppColors.danger,
                icon: const Icon(Icons.delete_forever_outlined),
                onPressed: () => _delete(r),
              ),
            ]),
          ),
      ],
    );
  }
}

/// The confirm dialog; it owns its text field (disposed with the dialog).
class _PurgeDialog extends StatefulWidget {
  final String title, warning;
  const _PurgeDialog({required this.title, required this.warning});

  @override
  State<_PurgeDialog> createState() => _PurgeDialogState();
}

class _PurgeDialogState extends State<_PurgeDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.warning, style: TextStyle(color: AppColors.danger, height: 1.35)),
            const SizedBox(height: 12),
            const Text('Təsdiq üçün böyük hərflərlə SİL yazın:'),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('purge-confirm'),
              controller: _typed,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'SİL'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ləğv et')),
          FilledButton(
            key: const ValueKey('purge-go'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: _AdminPurgePageState.typedSil(_typed.text) ? () => Navigator.pop(context, true) : null,
            child: const Text('Birdəfəlik sil'),
          ),
        ],
      );
}

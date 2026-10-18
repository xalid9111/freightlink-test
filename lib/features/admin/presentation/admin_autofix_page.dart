import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/autofix/autofix_logic.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/admin_repository.dart';
import 'admin_widgets.dart';

/// Admin → AutoFix (migration 0034): problems reported by the apps, the
/// GitHub quality check, and the "Problemi həll et" button that runs ONLY
/// the pre-tested recovery that fits the problem kind.

final _autofixShowAllProvider = StateProvider.autoDispose<bool>((ref) => false);

final _autofixErrorsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final all = ref.watch(_autofixShowAllProvider);
  var q = SupabaseConfig.client.from('app_errors').select();
  if (!all) q = q.eq('status', 'open');
  final rows = await q.order('last_seen_at', ascending: false).limit(100);
  return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
});

final _autofixCiProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await SupabaseConfig.client.from('autofix_ci_runs').select().order('id', ascending: false).limit(5);
  return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
});

const _kindLabels = <String, String>{
  AutoFixKind.runtime: 'Kod xətası',
  AutoFixKind.api: 'Server / API',
  AutoFixKind.network: 'İnternet / şəbəkə',
  AutoFixKind.freeze: 'Donma',
  AutoFixKind.messaging: 'Mesajlaşma',
  AutoFixKind.navigation: 'Naviqasiya',
  AutoFixKind.auth: 'Giriş sessiyası',
};

const _actionLabels = <String, String>{
  'reconnect': 'Bütün açıq tətbiqlərdə mesaj bağlantısını yenidən qur',
  'refresh_data': 'Sessiyanı yenilə və məlumatları təkrar yüklə (yalnız oxuma)',
  'reload_when_idle': 'Tətbiq arxa fona keçəndə səhifəni yenidən yüklə (yazılan heç nə itmir)',
};

Color _kindColor(String k) => switch (k) {
      AutoFixKind.runtime => AppColors.danger,
      AutoFixKind.freeze => AppColors.urgentFg,
      AutoFixKind.messaging => AppColors.blue,
      AutoFixKind.navigation => AppColors.newFg,
      _ => AppColors.accent,
    };

class AdminAutoFixPage extends ConsumerWidget {
  const AdminAutoFixPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showAll = ref.watch(_autofixShowAllProvider);
    final errors = ref.watch(_autofixErrorsProvider);
    final ci = ref.watch(_autofixCiProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_autofixErrorsProvider);
        ref.invalidate(_autofixCiProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'AutoFix tətbiqlərdə baş verən xətaları toplayır. Təhlükəsiz hallarda özü düzəldir '
            '(yenidən qoşulma, məhdud təkrar sorğu, sessiyanın yenilənməsi). Kod xətalarını '
            'avtomatik düzəltmir — onlar üçün fayl, sətir və loglar göstərilir.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          _CiCard(async: ci, onChanged: () => ref.invalidate(_autofixCiProvider)),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: Text('Problemlər', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              ChoiceChip(
                label: const Text('Açıq'),
                selected: !showAll,
                onSelected: (_) => ref.read(_autofixShowAllProvider.notifier).state = false,
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Hamısı'),
                selected: showAll,
                onSelected: (_) => ref.read(_autofixShowAllProvider.notifier).state = true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          errors.when(
            loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(
              'Yüklənmədi: ${adminErrorText(e)}\n(0034_autofix.sql işə salınıbmı?)',
              style: TextStyle(color: AppColors.danger),
            ),
            data: (list) => list.isEmpty
                ? const EmptyNote('Açıq problem yoxdur 👍')
                : Column(
                    children: [
                      for (final e in list)
                        _ErrorCard(row: e, onChanged: () => ref.invalidate(_autofixErrorsProvider)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onChanged;
  const _ErrorCard({required this.row, required this.onChanged});

  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard> {
  bool _open = false;

  Map<String, dynamic> get r => widget.row;

  String _report() {
    final b = StringBuffer()
      ..writeln('Növ: ${_kindLabels[r['kind']] ?? r['kind']}  Kod: ${txt(r['code'])}')
      ..writeln('Mesaj: ${txt(r['message'])}')
      ..writeln('Fayl: ${txt(r['file'])}${r['line'] == null ? '' : ':${r['line']}'}')
      ..writeln('Səhifə: ${txt(r['route'])}')
      ..writeln('Say: ${r['count']}  İstifadəçi: ${r['users']}  Avtomatik bərpa: ${r['auto_fixed']}')
      ..writeln('İlk: ${fmtDateTime(r['first_seen_at'])}  Son: ${fmtDateTime(r['last_seen_at'])}')
      ..writeln('Versiya: ${txt(r['app_version'])}  Brauzer: ${txt(r['user_agent'])}')
      ..writeln('\nAddımlar:\n${txt(r['breadcrumbs'])}')
      ..writeln('\nStack:\n${txt(r['stack'])}');
    return b.toString();
  }

  Future<void> _fix() async {
    final action = autofixActionFor('${r['kind']}');
    if (action == null) return;
    final ok = await confirmAction(
      context,
      'Problemi həll et',
      'Bu əvvəlcədən yoxlanmış təhlükəsiz əməliyyat icra olunacaq:\n\n• ${_actionLabels[action]}\n\n'
          'İstifadəçi məlumatları silinmir və dəyişmir.',
      ok: 'İcra et',
    );
    if (!ok || !mounted) return;
    final done = await runAdmin(context, () async {
      final res = await SupabaseConfig.client.rpc('admin_autofix_run', params: {'p_error': r['id']});
      if ('$res' == 'none') throw Exception('no_safe_fix');
    }, success: 'İcra olundu: tətbiqlər bir neçə dəqiqə ərzində tətbiq edəcək');
    if (done) widget.onChanged();
  }

  Future<void> _setStatus(String status, String success) async {
    final done = await runAdmin(context, () async {
      await SupabaseConfig.client.rpc('admin_autofix_set_status', params: {'p_error': r['id'], 'p_status': status});
    }, success: success);
    if (done) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final kind = '${r['kind']}';
    final action = autofixActionFor(kind);
    final status = '${r['status']}';
    final file = r['file'] as String?;
    final line = r['line'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AdminChip(_kindLabels[kind] ?? kind, color: _kindColor(kind)),
              if ('${r['code']}'.isNotEmpty) AdminChip('${r['code']}'),
              AdminChip('${r['count']}× · ${r['users']} istifadəçi'),
              if ((r['auto_fixed'] as num? ?? 0) > 0) AdminChip('avtomatik bərpa: ${r['auto_fixed']}', color: AppColors.online),
              if (status != 'open') AdminChip(status == 'fixed' ? 'həll olunub' : 'gizlədilib', color: AppColors.online),
            ],
          ),
          const SizedBox(height: 8),
          Text(txt(r['message']), maxLines: _open ? 20 : 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            'Fayl: ${file ?? '— (tapılmadı)'}${line == null ? '' : ' · sətir $line'}',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSoft),
          ),
          if (file != null && file.startsWith('≈'))
            Text('≈ = stack oxunmadı (minified build); xəta zamanı açıq olan ekranın faylı göstərilir',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
          Text('Səhifə: ${txt(r['route'])} · son: ${fmtDateTime(r['last_seen_at'])}',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
          if (_open) ...[
            const SizedBox(height: 8),
            const Text('Addımlar (son hərəkətlər):', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            SelectableText(txt(r['breadcrumbs']), style: const TextStyle(fontSize: 12, height: 1.35)),
            const SizedBox(height: 8),
            const Text('Stack / log:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            SelectableText(txt(r['stack']), style: AppFonts.mono(size: 11, weight: FontWeight.w400)),
            const SizedBox(height: 6),
            Text('Versiya: ${txt(r['app_version'])}\nBrauzer: ${txt(r['user_agent'])}',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
          ],
          const SizedBox(height: 10),
          if (status == 'open')
            action != null
                ? FilledButton.icon(
                    onPressed: _fix,
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Problemi həll et'),
                  )
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.urgentBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Avtomatik düzəliş mümkün deyil — bu kod xətasıdır, manual müdaxilə lazımdır. '
                      'Fayl, sətir və logları kopyalayıb düzəliş üçün göndərin.',
                      style: TextStyle(color: AppColors.urgentFg, fontSize: 12.5),
                    ),
                  ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(onPressed: () => setState(() => _open = !_open), child: Text(_open ? 'Bağla' : 'Loglar')),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _report()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hesabat kopyalandı')));
                  }
                },
                child: const Text('Kopyala'),
              ),
              if (status == 'open') ...[
                TextButton(onPressed: () => _setStatus('fixed', 'Həll olundu kimi qeyd edildi'), child: const Text('Həll olundu')),
                TextButton(onPressed: () => _setStatus('ignored', 'Gizlədildi'), child: const Text('Gizlət')),
              ] else
                TextButton(onPressed: () => _setStatus('open', 'Yenidən açıldı'), child: const Text('Yenidən aç')),
            ],
          ),
        ],
      ),
    );
  }
}

class _CiCard extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> async;
  final VoidCallback onChanged;
  const _CiCard({required this.async, required this.onChanged});

  Future<void> _setToken(BuildContext context) async {
    const chars = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final token = List.generate(40, (_) => chars[rnd.nextInt(chars.length)]).join();
    final ok = await confirmAction(
      context,
      'GitHub yoxlama açarı',
      'Yeni gizli açar yaradılacaq. Sonra onu GitHub-da Settings → Secrets → Actions bölməsində '
          'AUTOFIX_CI_TOKEN adı ilə saxlayın. Köhnə açar işləməyəcək.',
      ok: 'Yarat',
    );
    if (!ok || !context.mounted) return;
    final done = await runAdmin(context, () async {
      await SupabaseConfig.client.rpc('admin_autofix_set_ci_token', params: {'p_token': token});
    }, success: 'Açar yaradıldı');
    if (!done || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AUTOFIX_CI_TOKEN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bu açarı kopyalayın — yalnız indi göstərilir:'),
            const SizedBox(height: 8),
            SelectableText(token, style: AppFonts.mono(size: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
            child: const Text('Kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bağla')),
        ],
      ),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fact_check_outlined, color: AppColors.accent),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('GitHub yoxlaması (analyze + testlər)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: () => _setToken(context), child: const Text('Açar')),
            ],
          ),
          const SizedBox(height: 6),
          async.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Yüklənmədi: ${adminErrorText(e)}', style: TextStyle(color: AppColors.danger)),
            data: (runs) {
              if (runs.isEmpty) {
                return Text('Hələ nəticə yoxdur. "AutoFix CI" workflow-u GitHub-a əlavə olunub açar təyin ediləndən sonra görünəcək.',
                    style: TextStyle(color: AppColors.textSoft, fontSize: 12.5));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in runs)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        onTap: () => showDetail(
                          context,
                          title: 'Yoxlama ${fmtDateTime(r['created_at'])}',
                          body: (_) => SelectableText(txt(r['details']), style: AppFonts.mono(size: 11, weight: FontWeight.w400)),
                        ),
                        child: Row(
                          children: [
                            Icon(r['ok'] == true ? Icons.check_circle : Icons.cancel,
                                color: r['ok'] == true ? AppColors.online : AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${fmtDateTime(r['created_at'])} · ${txt(r['sha']).length > 7 ? txt(r['sha']).substring(0, 7) : txt(r['sha'])}\n'
                                'Analyze: ${r['analyze_errors']} xəta, ${r['analyze_warnings']} xəbərdarlıq · '
                                'Testlər: ${r['tests_passed']} keçdi, ${r['tests_failed']} uğursuz',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.textSoft),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

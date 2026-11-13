import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/config/supabase_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/localization/locale_controller.dart';
import '../../core/router/safe_navigation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mouse_drag_scroll.dart';
import '../../core/widgets/published_notice.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../chat/data/group_repository.dart';
import '../chat/presentation/providers/chat_providers.dart';
import '../finance/presentation/finance_providers.dart';

/// "Təklif və iradlar" and payment / VIP problems for the admins (owner,
/// 13.11.2026, SQL 0120). Users write only through support_report_submit;
/// admins read through admin_support_list and change the status through
/// admin_support_set_status (logged).
enum SupportKind { feedback, payment, promo }

/// SQL 0120 not run yet.
class SupportNotReady implements Exception {
  const SupportNotReady();
}

class SupportReport {
  final String id;
  final String? userId, userName, message, paymentId, problem, adminNote, paymentStatus, paymentMode, failureReason, orderKind, currency;
  final String kind, status;
  final double? amount;
  final DateTime createdAt;
  const SupportReport({
    required this.id,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.userId,
    this.userName,
    this.message,
    this.paymentId,
    this.problem,
    this.adminNote,
    this.amount,
    this.currency,
    this.paymentStatus,
    this.paymentMode,
    this.failureReason,
    this.orderKind,
  });

  factory SupportReport.fromJson(Map<String, dynamic> j) => SupportReport(
        id: '${j['id']}',
        kind: '${j['kind']}',
        status: '${j['status'] ?? 'new'}',
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        userId: j['user_id'] as String?,
        userName: j['user_name'] as String?,
        message: j['message'] as String?,
        paymentId: j['payment_id'] as String?,
        problem: j['problem'] as String?,
        adminNote: j['admin_note'] as String?,
        amount: (j['amount'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        paymentStatus: j['payment_status'] as String?,
        paymentMode: j['payment_mode'] as String?,
        failureReason: j['failure_reason'] as String?,
        orderKind: j['order_kind'] as String?,
      );

  /// The i18n key of the card's title.
  String get titleKey => kind == 'auto_payment' ? 'sup_problem_${problem ?? 'failed'}' : 'sup_kind_$kind';
}

/// The error text key for a failed submit.
String supportErrorKey(Object e) {
  if (e is SupportNotReady) return 'sup_not_ready';
  final m = e is PostgrestException ? e.message : '$e';
  if (m.contains('too_many')) return 'sup_err_too_many';
  if (m.contains('invalid_message')) return 'sup_err_short';
  return 'sup_err_send';
}

class SupportRepository {
  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883' || e.code == 'PGRST205' || e.code == '42P01') throw const SupportNotReady();
      rethrow;
    }
  }

  Future<void> submit(SupportKind kind, String message, {String? paymentId}) => _run(
      () => SupportConfigCall.rpc('support_report_submit', {'p_kind': kind.name, 'p_message': message.trim(), 'p_payment_id': paymentId}));

  Future<int> openCount() async {
    try {
      final n = await SupportConfigCall.rpc('admin_support_open_count', const {});
      return (n as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0; // before SQL 0120 / offline: no count
    }
  }

  Future<List<SupportReport>> list({String? status}) => _run(() async {
        final rows = await SupportConfigCall.rpc('admin_support_list', {'p_status': status, 'p_limit': 200});
        return [for (final r in (rows as List? ?? const [])) SupportReport.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<void> setStatus(String id, String status, {String? note}) =>
      _run(() => SupportConfigCall.rpc('admin_support_set_status', {'p_id': id, 'p_status': status, 'p_note': note}));
}

/// One place for the calls (with a timeout).
class SupportConfigCall {
  static Future<dynamic> rpc(String fn, Map<String, dynamic> params) =>
      SupabaseConfig.client.rpc(fn, params: params).timeout(const Duration(seconds: 15));
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) => SupportRepository());

/// The red count on Profil → admin card (0 for everybody else).
final adminSupportCountProvider = FutureProvider.autoDispose<int>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return 0;
  return ref.watch(supportRepositoryProvider).openCount();
});

/// null = all.
final adminSupportListProvider = FutureProvider.autoDispose
    .family<List<SupportReport>, String?>((ref, status) => ref.watch(supportRepositoryProvider).list(status: status));

/// Opens the form: Profil → Təklif və iradlar, or "Problem bildir" on a
/// payment / "Önə çıxar" sheet (with the payment when there is one).
void openSupportForm(BuildContext context, {SupportKind kind = SupportKind.feedback, String? paymentId}) =>
    context.pushOnce('/support?kind=${kind.name}${paymentId == null ? '' : '&payment=$paymentId'}');

SupportKind supportKindOf(String? q) => SupportKind.values.where((k) => k.name == q).firstOrNull ?? SupportKind.feedback;

/// "Təklif və iradlar" / "Problem bildir": one text box and Göndər; after
/// sending "Təşəkkürlər! Adminlər qeydinizi nəzərə alacaq." and back.
class SupportFormScreen extends ConsumerStatefulWidget {
  final SupportKind kind;
  final String? paymentId;
  const SupportFormScreen({super.key, this.kind = SupportKind.feedback, this.paymentId});

  @override
  ConsumerState<SupportFormScreen> createState() => _SupportFormScreenState();
}

class _SupportFormScreenState extends ConsumerState<SupportFormScreen> {
  final _text = TextEditingController();
  late SupportKind _kind = widget.kind;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(AppStrings s) async {
    if (_busy) return;
    if (_text.text.trim().length < 3) {
      setState(() => _error = s.t('sup_err_short'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supportRepositoryProvider).submit(_kind, _text.text, paymentId: widget.paymentId);
      if (!mounted) return;
      showPublishedNotice(context, s.t('sup_thanks'));
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/profile');
      }
    } catch (e) {
      if (mounted) setState(() => _error = s.t(supportErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final title = s.t(widget.kind == SupportKind.feedback ? 'sup_title' : 'sup_problem_title');
    // Təklif / irad · Ödəniş problemi · VIP / reklam problemi.
    Widget kindChip(SupportKind k) => ChoiceChip(
          key: ValueKey('sup-kind-${k.name}'),
          label: Text(s.t('sup_kind_${k.name}')),
          selected: _kind == k,
          onSelected: (_) => setState(() => _kind = k),
        );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        Text(s.t(_kind == SupportKind.feedback ? 'sup_intro' : 'sup_problem_intro'),
            style: TextStyle(fontSize: 15, color: AppColors.textSoft)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [for (final k in SupportKind.values) kindChip(k)]),
        if (widget.paymentId != null) ...[
          const SizedBox(height: 8),
          Text(s.t('sup_with_payment'), key: const ValueKey('sup-with-payment'), style: TextStyle(fontSize: 13, color: AppColors.accent)),
        ],
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('sup-text'),
          controller: _text,
          minLines: 5,
          maxLines: 10,
          maxLength: 2000,
          decoration: InputDecoration(hintText: s.t('sup_hint'), border: const OutlineInputBorder()),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, key: const ValueKey('sup-error'), style: TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('sup-send'),
          onPressed: _busy ? null : () => _send(s),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.accentFill),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          label: Text(s.t('sup_send')),
        ),
      ]),
    );
  }
}

/// Admin → Bildirişlər: the users' suggestions / problems and the server's
/// own payment finds; Baxılır · Həll olundu, Mesaj yaz, Maliyyə.
class AdminSupportScreen extends ConsumerStatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  ConsumerState<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends ConsumerState<AdminSupportScreen> {
  String? _status = 'new';
  final Set<String> _busy = {};

  Future<void> _set(SupportReport r, String status, AppStrings s) async {
    setState(() => _busy.add(r.id));
    try {
      await ref.read(supportRepositoryProvider).setStatus(r.id, status);
      ref.invalidate(adminSupportListProvider);
      ref.invalidate(adminSupportCountProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('sup_err_send'))));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _message(SupportReport r, AppStrings s) async {
    final uid = r.userId;
    if (uid == null) return;
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(uid);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('chat_open_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final async = ref.watch(adminSupportListProvider(_status));
    final finance = ref.watch(isFinanceAdminProvider).valueOrNull == true;
    Widget chip(String? v, String key) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            key: ValueKey('sup-filter-${v ?? 'all'}'),
            label: Text(s.t(key)),
            selected: _status == v,
            onSelected: (_) => setState(() => _status = v),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.t('sup_admin_title'))),
      body: Column(children: [
        MouseDragScroll(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            chip('new', 'sup_status_new'),
            chip('seen', 'sup_status_seen'),
            chip('resolved', 'sup_status_resolved'),
            chip(null, 'sup_status_all'),
          ]),
        )),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(adminSupportListProvider);
              ref.invalidate(adminSupportCountProvider);
            },
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(s.t(e is SupportNotReady ? 'sup_not_ready' : 'sup_admin_only'), textAlign: TextAlign.center),
                ),
              ]),
              data: (list) => list.isEmpty
                  ? ListView(
                      children: [Padding(padding: const EdgeInsets.all(24), child: Text(s.t('sup_empty'), textAlign: TextAlign.center))])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _ReportCard(
                        report: list[i],
                        strings: s,
                        lang: lang,
                        busy: _busy.contains(list[i].id),
                        finance: finance,
                        onStatus: (st) => _set(list[i], st, s),
                        onMessage: () => _message(list[i], s),
                      ),
                    ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final SupportReport report;
  final AppStrings strings;
  final String lang;
  final bool busy, finance;
  final ValueChanged<String> onStatus;
  final VoidCallback onMessage;
  const _ReportCard({
    required this.report,
    required this.strings,
    required this.lang,
    required this.busy,
    required this.finance,
    required this.onStatus,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    final s = strings;
    final auto = r.kind == 'auto_payment';
    final icon = switch (r.kind) {
      'feedback' => Icons.lightbulb_outline,
      'promo' => Icons.workspace_premium_outlined,
      _ => Icons.credit_card,
    };
    final color = auto ? AppColors.danger : (r.kind == 'feedback' ? AppColors.blue : AppColors.accent);
    final pay = r.paymentId == null
        ? null
        : [
            if (r.amount != null) '${r.amount!.toStringAsFixed(2)} ${r.currency ?? ''}',
            if (r.paymentStatus != null) s.t('sup_pay_${r.paymentStatus}'),
            if (r.orderKind != null) s.t('sup_order_${r.orderKind}'),
            if (r.paymentMode == 'test') 'TEST',
          ].join(' · ');
    return Material(
      key: ValueKey('sup-report-${r.id}'),
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(s.t(r.titleKey), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text))),
            Text(s.t('sup_status_${r.status}'),
                style: TextStyle(fontSize: 12, color: r.status == 'new' ? AppColors.danger : AppColors.textSoft)),
          ]),
          const SizedBox(height: 4),
          Text('${r.userName ?? s.t('sup_unknown_user')} · ${DateFormat('d MMM, HH:mm', lang).format(r.createdAt)}',
              style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          if ((r.message ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.message!, style: TextStyle(fontSize: 15, color: AppColors.text)),
          ],
          if (pay != null) ...[
            const SizedBox(height: 6),
            Text(pay, key: ValueKey('sup-pay-${r.id}'), style: TextStyle(fontSize: 13.5, color: AppColors.text)),
            if ((r.failureReason ?? '').isNotEmpty) Text(r.failureReason!, style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
          ],
          if ((r.adminNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${s.t('sup_note')}: ${r.adminNote}', style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          ],
          const SizedBox(height: 6),
          Wrap(spacing: 4, runSpacing: 0, children: [
            if (r.status != 'seen' && r.status != 'resolved')
              TextButton(
                  key: ValueKey('sup-seen-${r.id}'), onPressed: busy ? null : () => onStatus('seen'), child: Text(s.t('sup_mark_seen'))),
            if (r.status != 'resolved')
              TextButton(
                  key: ValueKey('sup-resolve-${r.id}'),
                  onPressed: busy ? null : () => onStatus('resolved'),
                  child: Text(s.t('sup_mark_resolved'))),
            if (r.status == 'resolved')
              TextButton(
                  key: ValueKey('sup-reopen-${r.id}'), onPressed: busy ? null : () => onStatus('new'), child: Text(s.t('sup_reopen'))),
            if (r.userId != null)
              TextButton.icon(
                  key: ValueKey('sup-message-${r.id}'),
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: Text(s.t('sup_message_user'))),
            if (r.paymentId != null && finance)
              TextButton.icon(
                  key: ValueKey('sup-finance-${r.id}'),
                  onPressed: () => context.pushOnce('/finance'),
                  icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                  label: Text(s.t('pf_finance'))),
          ]),
        ]),
      ),
    );
  }
}

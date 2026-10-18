import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../admin/presentation/admin_widgets.dart' show AdminChip, EmptyNote, confirmAction;
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import 'finance_providers.dart';

/// Profile → "Maliyyə və ödənişlər" (0037). Only for the finance owner —
/// the server checks it in every call; this screen only hides itself.
/// Admin texts are Azerbaijani like the rest of the admin panel.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(isFinanceAdminProvider);
    return allowed.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const _Denied(),
      data: (ok) => ok ? const _FinanceTabs() : const _Denied(),
    );
  }
}

class _Denied extends StatelessWidget {
  const _Denied();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Maliyyə və ödənişlər')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Bu bölmə yalnız maliyyə admininə açıqdır.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
          ),
        ),
      );
}

class _FinanceTabs extends ConsumerStatefulWidget {
  const _FinanceTabs();
  @override
  ConsumerState<_FinanceTabs> createState() => _FinanceTabsState();
}

class _FinanceTabsState extends ConsumerState<_FinanceTabs> {
  String? _mode; // which data to show: test | live

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(paymentSettingsProvider).valueOrNull;
    final mode = _mode ?? (settings?.mode == 'test' ? 'test' : 'live');
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Maliyyə və ödənişlər'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Panel'), Tab(text: 'Ödənişlər'), Tab(text: 'Bank hesabları'), Tab(text: 'Ayarlar'), Tab(text: 'Jurnal')],
          ),
        ),
        body: TabBarView(children: [
          _DashboardTab(mode: mode, onMode: (m) => setState(() => _mode = m)),
          _PaymentsTab(mode: mode, onMode: (m) => setState(() => _mode = m)),
          const _AccountsTab(),
          const _SettingsTab(),
          const _AuditTab(),
        ]),
      ),
    );
  }
}

// ---- helpers -------------------------------------------------------------------

/// Runs a sensitive action; if the server asks for a fresh sign-in, asks
/// for the password, signs in again and retries once.
Future<bool> runSensitive(BuildContext context, WidgetRef ref, Future<void> Function() action, {String success = 'Yadda saxlanıldı'}) async {
  final messenger = ScaffoldMessenger.of(context);
  Future<bool> attempt() async {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  }

  try {
    return await attempt();
  } catch (e) {
    if (!e.toString().contains('reauth_required')) {
      messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(financeErrorText(e))));
      return false;
    }
  }
  if (!context.mounted) return false;
  final ok = await showReauthDialog(context, ref);
  if (!ok) return false;
  try {
    return await attempt();
  } catch (e) {
    messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(financeErrorText(e))));
    return false;
  }
}

/// Extra authentication: the password again (the server then sees a sign-in
/// from the last minutes). Nothing is stored.
Future<bool> showReauthDialog(BuildContext context, WidgetRef ref) async {
  final email = ref.read(currentUserProvider)?.email ?? '';
  final ctrl = TextEditingController();
  String? error;
  var busy = false;
  final res = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('Təhlükəsizlik yoxlaması'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bank hesabı və ödəniş ayarlarını dəyişmək üçün parolunuzu yenidən daxil edin.',
                style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(labelText: 'Parol', errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setD(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await ref.read(financeRepositoryProvider).reauthenticate(email, ctrl.text);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (_) {
                      setD(() {
                        busy = false;
                        error = 'Parol düzgün deyil';
                      });
                    }
                  },
            child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Təsdiqlə'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return res == true;
}

class _ModeSwitch extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onMode;
  const _ModeSwitch({required this.mode, required this.onMode});
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'live', label: Text('Canlı'), icon: Icon(Icons.verified_outlined, size: 18)),
          ButtonSegment(value: 'test', label: Text('Test'), icon: Icon(Icons.science_outlined, size: 18)),
        ],
        selected: {mode},
        onSelectionChanged: (v) => onMode(v.first),
      );
}

class _TestBanner extends StatelessWidget {
  static const text = 'TEST MƏLUMATLARI — real pul hərəkəti yoxdur, sifarişlər dəyişmir.';
  const _TestBanner();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(Icons.science_outlined, color: AppColors.blue, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.blue, fontSize: 12.5))),
        ]),
      );
}

String statusLabelAz(String s) => switch (s) {
      'succeeded' => 'Uğurlu',
      'pending' => 'Gözləyir',
      'created' => 'Başladı',
      'failed' => 'Uğursuz',
      'cancelled' => 'Ləğv edilib',
      'refunded' => 'Geri qaytarılıb',
      _ => s,
    };

Color statusColorOf(String s) => switch (s) {
      'succeeded' => AppColors.online,
      'pending' || 'created' => AppColors.blue,
      'failed' => AppColors.danger,
      _ => AppColors.textSoft,
    };

String methodLabel(String m) => switch (m) { 'apple_pay' => 'Apple Pay', 'google_pay' => 'Google Pay', _ => 'Visa / Mastercard' };
IconData methodIcon(String m) => switch (m) { 'apple_pay' => Icons.apple, 'google_pay' => Icons.g_mobiledata, _ => Icons.credit_card };

// ---- 1. dashboard ------------------------------------------------------------------
class _DashboardTab extends ConsumerWidget {
  final String mode;
  final ValueChanged<String> onMode;
  const _DashboardTab({required this.mode, required this.onMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sum = ref.watch(financeSummaryProvider(mode));
    final recent = ref.watch(financePaymentsProvider(PaymentFilter(mode: mode)));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(financeSummaryProvider(mode));
        ref.invalidate(financePaymentsProvider(PaymentFilter(mode: mode)));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Align(alignment: Alignment.centerLeft, child: _ModeSwitch(mode: mode, onMode: onMode)),
          const SizedBox(height: 12),
          if (mode == 'test') ...[const _TestBanner(), const SizedBox(height: 12)],
          sum.when(
            loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => EmptyNote(financeErrorText(e)),
            data: (s) => LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 900 ? 3 : 2;
              final w = (c.maxWidth - 10 * (cols - 1)) / cols;
              Widget card(String label, String value, IconData icon, Color color, [String? hint]) => SizedBox(
                    width: w,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 6),
                          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSoft))),
                        ]),
                        const SizedBox(height: 6),
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                            child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                        if (hint != null) Text(hint, style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
                      ]),
                    ),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 10, runSpacing: 10, children: [
                  card('Ümumi gəlir', money(s.gross, s.currency), Icons.trending_up, AppColors.online, '${s.succeededCount} uğurlu ödəniş'),
                  card('Təsdiqlənmiş balans', money(s.confirmedBalance, s.currency), Icons.account_balance_wallet_outlined, AppColors.accent,
                      'provayder təsdiqindən sonra'),
                  card('Gözləyən ödənişlər', money(s.pending, s.currency), Icons.hourglass_top, AppColors.blue, '${s.pendingCount} ədəd'),
                  card('Komissiyalar', money(s.commission, s.currency), Icons.percent, AppColors.textSoft),
                  card('Çıxarıla bilən məbləğ', money(s.withdrawable, s.currency), Icons.savings_outlined, AppColors.online),
                  card('Banka köçürülən', money(s.transferred, s.currency), Icons.account_balance_outlined, AppColors.textSoft,
                      s.payoutsInProgress > 0 ? 'yolda: ${money(s.payoutsInProgress, s.currency)}' : null),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.send_to_mobile_outlined),
                  label: const Text('Banka köçür'),
                  onPressed: () => runSensitive(context, ref, () => ref.read(financeRepositoryProvider).requestPayout(s.withdrawable),
                      success: 'Köçürmə sorğusu göndərildi'),
                ),
                const SizedBox(height: 4),
                Text('Köçürmə yalnız real provayder və təsdiqlənmiş bank hesabı qoşulandan sonra işləyir.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
              ]);
            }),
          ),
          const SizedBox(height: 20),
          const Text('Son ödənişlər', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          recent.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => EmptyNote(financeErrorText(e)),
            data: (list) => list.isEmpty
                ? const EmptyNote('Hələ ödəniş yoxdur')
                : Column(children: [for (final p in list.take(5)) _PaymentTile(p: p)]),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final FinancePayment p;
  const _PaymentTile({required this.p});
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(methodIcon(p.method), color: AppColors.textSoft),
        title: Row(children: [
          Expanded(child: Text(money(p.amount, p.currency), style: const TextStyle(fontWeight: FontWeight.w800))),
          AdminChip(statusLabelAz(p.status), color: statusColorOf(p.status)),
        ]),
        subtitle: Text('Sifariş ${p.orderLabel}${p.orderTitle == null ? '' : ' · ${p.orderTitle}'}\n${p.customer ?? ''} · ${fmt.format(p.createdAt)}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        isThreeLine: true,
        onTap: () => _showPayment(context, p),
      ),
    );
  }
}

void _showPayment(BuildContext context, FinancePayment p) {
  final fmt = DateFormat('dd.MM.yyyy HH:mm');
  Widget line(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: AppColors.textSoft, fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(money(p.amount, p.currency), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          line('Status', statusLabelAz(p.status)),
          line('Sifariş', '${p.orderLabel}${p.orderTitle == null ? '' : ' · ${p.orderTitle}'}'),
          line('Sifariş ID', p.orderId),
          line('Müştəri', p.customer ?? '—'),
          line('Üsul', methodLabel(p.method)),
          line('Komissiya', money(p.commission, p.currency)),
          line('Provayder', '${p.provider} (${p.mode == 'test' ? 'test' : 'canlı'})'),
          line('Yaradılıb', fmt.format(p.createdAt)),
          if (p.confirmedAt != null) line('Təsdiqlənib', fmt.format(p.confirmedAt!)),
          if (p.failureReason != null) line('Səbəb', p.failureReason!),
          line('Ödəniş ID', p.id),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: p.orderId));
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Sifariş ID-ni kopyala'),
          ),
        ]),
      ),
    ),
  );
}

// ---- 2. payments history + filters ------------------------------------------------
class _PaymentsTab extends ConsumerStatefulWidget {
  final String mode;
  final ValueChanged<String> onMode;
  const _PaymentsTab({required this.mode, required this.onMode});
  @override
  ConsumerState<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends ConsumerState<_PaymentsTab> {
  String? _status;
  DateTimeRange? _range;
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = PaymentFilter(mode: widget.mode, status: _status, from: _range?.start, to: _range?.end, search: _q);
    final list = ref.watch(financePaymentsProvider(filter));
    final dfmt = DateFormat('dd.MM.yy');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Align(alignment: Alignment.centerLeft, child: _ModeSwitch(mode: widget.mode, onMode: widget.onMode)),
        const SizedBox(height: 10),
        if (widget.mode == 'test') ...[const _TestBanner(), const SizedBox(height: 10)],
        TextField(
          controller: _search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Sifariş, müştəri və ya ID'),
          onSubmitted: (v) => setState(() => _q = v.trim()),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final s in const [null, 'succeeded', 'pending', 'failed', 'cancelled'])
            ChoiceChip(
              label: Text(s == null ? 'Hamısı' : statusLabelAz(s)),
              selected: _status == s,
              onSelected: (_) => setState(() => _status = s),
            ),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(_range == null ? 'Tarix' : '${dfmt.format(_range!.start)} – ${dfmt.format(_range!.end)}'),
            onPressed: () async {
              final now = DateTime.now();
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2025),
                lastDate: DateTime(now.year, now.month, now.day),
                initialDateRange: _range,
              );
              if (r != null) setState(() => _range = r);
            },
          ),
          if (_range != null || _q.isNotEmpty || _status != null)
            TextButton(
              onPressed: () => setState(() {
                _range = null;
                _status = null;
                _q = '';
                _search.clear();
              }),
              child: const Text('Filtrləri sıfırla'),
            ),
        ]),
        const SizedBox(height: 10),
        list.when(
          loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => EmptyNote(financeErrorText(e)),
          data: (rows) => rows.isEmpty
              ? const EmptyNote('Bu filtrə uyğun ödəniş yoxdur')
              : Column(children: [for (final p in rows) _PaymentTile(p: p)]),
        ),
      ],
    );
  }
}

// ---- 3. payout accounts ---------------------------------------------------------------
class _AccountsTab extends ConsumerWidget {
  const _AccountsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(payoutAccountsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        FilledButton.icon(
          onPressed: () async {
            final added = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _AddAccountSheet(),
            );
            if (added == true) ref.invalidate(payoutAccountsProvider);
          },
          icon: const Icon(Icons.add_card),
          label: const Text('Bank kartı / biznes hesabı əlavə et'),
        ),
        const SizedBox(height: 8),
        Text(
          'Kartın tam nömrəsi və CVV soruşulmur və saxlanılmır. Yeni hesab real provayder onu öz təhlükəsiz '
          'mexanizmi ilə yoxlayana qədər "Təsdiq gözləyir" vəziyyətində qalır.',
          style: TextStyle(fontSize: 12, color: AppColors.textSoft),
        ),
        const SizedBox(height: 14),
        accounts.when(
          loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => EmptyNote(financeErrorText(e)),
          data: (list) => list.isEmpty
              ? const EmptyNote('Hələ bank hesabı əlavə edilməyib — bu normal vəziyyətdir.\nÖdənişlər balansda toplanır.')
              : Column(children: [for (final a in list) _AccountTile(a: a)]),
        ),
      ],
    );
  }
}

class _AccountTile extends ConsumerWidget {
  final PayoutAccount a;
  const _AccountTile({required this.a});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(financeRepositoryProvider);
    final status = switch (a.status) {
      'verified' => AdminChip('Təsdiqlənib', color: AppColors.online),
      'disabled' => const AdminChip('Deaktiv'),
      _ => AdminChip('Təsdiq gözləyir', color: AppColors.blue),
    };
    return Opacity(
      opacity: a.isDisabled ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(a.isCard ? Icons.credit_card : Icons.business, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (a.isPrimary) ...[AdminChip('Əsas', color: AppColors.accent), const SizedBox(width: 6)],
              status,
            ]),
            const SizedBox(height: 4),
            Text(
              [a.holderName, if (a.bankName != null) a.bankName!, if (a.voen != null) 'VÖEN ${a.voen}'].join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.textSoft),
            ),
            if (!a.isDisabled)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!a.isPrimary)
                  TextButton(
                    onPressed: () async {
                      if (await runSensitive(context, ref, () => repo.setPrimary(a.id), success: 'Əsas hesab dəyişdi')) {
                        ref.invalidate(payoutAccountsProvider);
                      }
                    },
                    child: const Text('Əsas et'),
                  ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () async {
                    if (!await confirmAction(context, 'Deaktiv edilsin?', '"${a.title}" bundan sonra istifadə olunmayacaq.', ok: 'Deaktiv et', danger: true)) {
                      return;
                    }
                    if (!context.mounted) return;
                    if (await runSensitive(context, ref, () => repo.disable(a.id), success: 'Hesab deaktiv edildi')) {
                      ref.invalidate(payoutAccountsProvider);
                    }
                  },
                  child: const Text('Deaktiv et'),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _AddAccountSheet extends ConsumerStatefulWidget {
  const _AddAccountSheet();
  @override
  ConsumerState<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends ConsumerState<_AddAccountSheet> {
  String _kind = 'card';
  String _brand = 'visa';
  final _holder = TextEditingController();
  final _bank = TextEditingController();
  final _last4 = TextEditingController();
  final _company = TextEditingController();
  final _voen = TextEditingController();
  final _iban = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_holder, _bank, _last4, _company, _voen, _iban]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validate() {
    if (_holder.text.trim().length < 2) return 'Hesab sahibinin adını yazın.';
    if (_kind == 'card') {
      if (!isValidLast4(_last4.text)) return 'Kartın yalnız son 4 rəqəmini yazın.';
    } else {
      if (_company.text.trim().isEmpty) return 'Şirkətin adını yazın.';
      if (!isValidVoen(_voen.text)) return 'VÖEN 10 rəqəm olmalıdır.';
      if (!isValidAzIban(_iban.text)) return 'IBAN düzgün deyil (AZ.. 28 simvol).';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final repo = ref.read(financeRepositoryProvider);
    final ok = await runSensitive(
      context,
      ref,
      () => _kind == 'card'
          ? repo.addCardAccount(holder: _holder.text.trim(), bank: _bank.text.trim(), last4: _last4.text.trim(), brand: _brand)
          : repo.addBusinessAccount(
              holder: _holder.text.trim(), bank: _bank.text.trim(), company: _company.text.trim(), voen: _voen.text.trim(), iban: _iban.text),
      success: 'Hesab əlavə edildi — təsdiq gözləyir',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Bank kartı / biznes hesabı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'card', label: Text('Şəxsi kart'), icon: Icon(Icons.credit_card)),
                ButtonSegment(value: 'business', label: Text('Biznes (VÖEN)'), icon: Icon(Icons.business)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 12),
            if (_kind == 'business') ...[
              TextField(controller: _company, maxLength: 160, decoration: const InputDecoration(labelText: 'Şirkətin adı')),
              TextField(
                controller: _voen,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                decoration: const InputDecoration(labelText: 'VÖEN (10 rəqəm)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _iban,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'IBAN', hintText: 'AZ00 BANK 0000 0000 0000 0000 0000'),
              ),
              const SizedBox(height: 8),
            ],
            TextField(controller: _holder, maxLength: 120, decoration: InputDecoration(labelText: _kind == 'card' ? 'Kart sahibi' : 'Məsul şəxs')),
            TextField(controller: _bank, maxLength: 80, decoration: const InputDecoration(labelText: 'Bank (istəyə bağlı)')),
            if (_kind == 'card') ...[
              TextField(
                controller: _last4,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                decoration: const InputDecoration(labelText: 'Kartın son 4 rəqəmi', hintText: '1234'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'visa', label: Text('Visa')),
                  ButtonSegment(value: 'mastercard', label: Text('Mastercard')),
                  ButtonSegment(value: 'other', label: Text('Digər')),
                ],
                selected: {_brand},
                onSelectionChanged: (v) => setState(() => _brand = v.first),
              ),
              const SizedBox(height: 6),
              Text('Tam kart nömrəsi və CVV burada daxil edilmir — onları yalnız provayderin təhlükəsiz səhifəsi qəbul edəcək.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: AppColors.danger))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Əlavə et'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---- 4. settings ------------------------------------------------------------------------
class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab();
  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  String? _mode;
  Set<PayMethod>? _methods;
  final _commission = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _commission.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(paymentSettingsProvider);
    return s.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyNote(financeErrorText(e)),
      data: (cur) {
        if (!_loaded) {
          _loaded = true;
          _mode = cur.mode == 'live' ? 'off' : cur.mode;
          _methods = cur.methods.toSet();
          _commission.text = cur.commissionPct.toStringAsFixed(cur.commissionPct % 1 == 0 ? 0 : 2);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            const Text('Ödəniş rejimi', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'off', label: Text('Söndürülüb')),
                ButtonSegment(value: 'test', label: Text('Test')),
                ButtonSegment(value: 'live', label: Text('Canlı'), enabled: false),
              ],
              selected: {_mode ?? 'off'},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 6),
            Text(
              'Test: ödəniş axını daxili test provayderi ilə işləyir, yalnız siz görürsünüz, real pul çıxılmır və sifarişlər dəyişmir. '
              'Canlı rejim real provayder qoşulandan sonra açılacaq.',
              style: TextStyle(fontSize: 12, color: AppColors.textSoft),
            ),
            const SizedBox(height: 16),
            const Text('Provayder', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.science_outlined, color: AppColors.blue),
              title: const Text('Daxili test provayderi'),
              subtitle: const Text('Payriff / Epoint / Stripe — qoşulmayıb (açarlar yalnız serverdə saxlanılacaq)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commission,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Komissiya, %', helperText: '0–50'),
            ),
            const SizedBox(height: 12),
            const Text('Ödəniş üsulları', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final m in PayMethod.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _methods!.contains(m),
                title: Text(methodLabel(m.wire)),
                onChanged: (v) => setState(() => v == true ? _methods!.add(m) : _methods!.remove(m)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                final pct = double.tryParse(_commission.text.replaceAll(',', '.'));
                if (pct == null || pct < 0 || pct > 50) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Komissiya 0–50% arasında olmalıdır.')));
                  return;
                }
                final repo = ref.read(financeRepositoryProvider);
                if (await runSensitive(context, ref,
                    () => repo.saveSettings(mode: _mode ?? 'off', commissionPct: pct, methods: _methods!.toList()))) {
                  ref.invalidate(paymentSettingsProvider);
                  ref.invalidate(checkoutAvailabilityProvider);
                }
              },
              child: const Text('Yadda saxla'),
            ),
            const SizedBox(height: 24),
            const _ProviderRequirements(),
          ],
        );
      },
    );
  }
}

class _ProviderRequirements extends StatelessWidget {
  const _ProviderRequirements();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Real provayder qoşmaq üçün lazım olanlar', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '• Provayderlə müqavilə (Apple Pay, Google Pay, Visa/Mastercard dəstəyi ilə)\n'
            '• Merchant ID, gizli API açarı və webhook imza açarı — yalnız Supabase → Edge Functions → Secrets-ə yazılır\n'
            '• Webhook ünvanı: …/functions/v1/payments-webhook/<provayder>\n'
            '• Apple Pay üçün domen təsdiqi (provayder verir)\n'
            '• Şirkət sənədləri, VÖEN, IBAN — provayderin yoxlaması üçün\n'
            'Ətraflı: docs/payments/README.md',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSoft, height: 1.45),
          ),
        ]),
      );
}

// ---- 5. audit log ---------------------------------------------------------------------------
String auditActionAz(String a) => switch (a) {
      'payment.create' => 'Ödəniş başladı',
      'payment.succeeded' => 'Ödəniş təsdiqləndi (provayder)',
      'payment.failed' => 'Ödəniş uğursuz oldu',
      'payment.cancel' => 'Ödəniş ləğv edildi',
      'provider_event.rejected' => 'Provayder hadisəsi rədd edildi',
      'payout_account.add' => 'Bank hesabı əlavə edildi',
      'payout_account.primary' => 'Əsas hesab dəyişdi',
      'payout_account.disable' => 'Bank hesabı deaktiv edildi',
      'settings.update' => 'Ödəniş ayarları dəyişdi',
      _ => a,
    };

final _auditProvider = FutureProvider.autoDispose<List<Map>>((ref) async {
  final rows = await ref.watch(financeRepositoryProvider).auditRecent();
  return rows;
});

class _AuditTab extends ConsumerWidget {
  const _AuditTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('dd.MM.yyyy HH:mm:ss');
    return ref.watch(_auditProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyNote(financeErrorText(e)),
          data: (rows) => rows.isEmpty
              ? const EmptyNote('Jurnal boşdur')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  children: [
                    Text('Maliyyə əməliyyatları jurnalı (dəyişdirilə və silinə bilməz)',
                        style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                    const SizedBox(height: 8),
                    for (final r in rows)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.history, size: 18, color: AppColors.textSoft),
                        title: Text(auditActionAz('${r['action']}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${DateTime.tryParse('${r['created_at']}') == null ? '' : fmt.format(DateTime.parse('${r['created_at']}').toLocal())}'
                          ' · ${r['entity']} ${r['entity_id'] ?? ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                  ],
                ),
        );
  }
}

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../ads/presentation/ads_providers.dart';
import '../data/finance_repository.dart';
import '../domain/finance_models.dart';
import 'finance_providers.dart';

DeviceKind currentDeviceKind() => switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => DeviceKind.apple,
      TargetPlatform.android => DeviceKind.android,
      _ => DeviceKind.desktop,
    };

/// "Pay online" on an unpaid ad order. Shown only when the server opens the
/// checkout for this user (LIVE: everybody; TEST: only the finance owner),
/// so customers never see a test checkout. The receipt flow stays as it is.
class CardCheckoutButton extends ConsumerWidget {
  final AdOrder order;
  final AppStrings s;
  const CardCheckoutButton({super.key, required this.order, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final av = ref.watch(checkoutAvailabilityProvider).valueOrNull;
    if (av == null || !av.available) return const SizedBox.shrink();
    final methods = methodsForDevice(currentDeviceKind(), av.methods);
    if (methods.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: Icon(methods.first == PayMethod.applePay ? Icons.apple : (methods.first == PayMethod.googlePay ? Icons.g_mobiledata : Icons.credit_card)),
        label: Text(s.t('pay_card_button')),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          builder: (_) => CheckoutSheet(order: order, s: s, availability: av, methods: methods),
        ),
      ),
    );
  }
}

class CheckoutSheet extends ConsumerStatefulWidget {
  final AdOrder order;
  final AppStrings s;
  final CheckoutAvailability availability;
  final List<PayMethod> methods;
  const CheckoutSheet({super.key, required this.order, required this.s, required this.availability, required this.methods});

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  static const stepLock = Duration(milliseconds: 700);

  /// One key for this checkout: every tap / retry sends the same key, so
  /// the server can never create a second payment.
  final String _key = newIdempotencyKey();
  late PayMethod _method = widget.methods.first;
  CheckoutPayment? _payment;
  bool _busy = false;
  bool _locked = false;
  String? _errorKey;

  AppStrings get s => widget.s;

  Future<void> _run(Future<CheckoutPayment> Function() step) async {
    if (_busy || _locked) return;
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final p = await step();
      if (mounted) {
        setState(() {
          _payment = p;
          _busy = false;
          _locked = true;
        });
      }
      if (p.status == 'succeeded') ref.invalidate(myAdOrdersProvider);
      // The next step's buttons appear where the user just tapped: keep
      // them disabled a moment so a fast double tap cannot press them too.
      await Future<void>.delayed(stepLock);
    } catch (e) {
      if (mounted) setState(() => _errorKey = checkoutErrorKey(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _locked = false;
        });
      }
    }
  }

  void _close() {
    final p = _payment;
    if (p != null && p.status == 'created') {
      ref.read(financeRepositoryProvider).cancelPayment(p.id).catchError((_) {});
    }
    Navigator.of(context).pop();
  }

  String _label(PayMethod m) => s.t(switch (m) { PayMethod.applePay => 'pay_method_apple', PayMethod.googlePay => 'pay_method_google', _ => 'pay_method_card' });
  IconData _icon(PayMethod m) => switch (m) { PayMethod.applePay => Icons.apple, PayMethod.googlePay => Icons.g_mobiledata, _ => Icons.credit_card };

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(financeRepositoryProvider);
    final p = _payment;
    final isTest = widget.availability.isTest;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(s.t('pay_sheet_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(onPressed: _busy ? null : _close, icon: const Icon(Icons.close)),
          ]),
          if (isTest) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Text(s.t('pay_test_banner'), style: const TextStyle(color: AppColors.blue, fontSize: 12.5)),
            ),
            const SizedBox(height: 10),
          ],
          Text(s.t('pay_amount'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
          Text(money(widget.order.price, widget.order.currency), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (p == null) ...[
            Text(s.t('pay_choose_method'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final m in widget.methods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: !_busy,
                onTap: () => setState(() => _method = m),
                leading: Icon(_method == m ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: _method == m ? AppColors.accent : AppColors.textSoft),
                title: Row(children: [Icon(_icon(m), size: 20), const SizedBox(width: 8), Text(_label(m))]),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _run(() => repo.startCheckout(orderId: widget.order.id, method: _method, idempotencyKey: _key)),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('${s.t('pay_now')} · ${money(widget.order.price, widget.order.currency)}'),
            ),
          ] else if (!p.isFinal) ...[
            // Built-in test provider = what a real provider's secure page will do.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [Icon(_icon(_method)), const SizedBox(width: 8), Expanded(child: Text(s.t('pay_test_page'), style: const TextStyle(fontWeight: FontWeight.w700)))]),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _busy || _locked ? null : () => _run(() => repo.completeTestPayment(p.id, success: true)),
                  child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(s.t('pay_test_approve')),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: _busy || _locked ? null : () => _run(() => repo.completeTestPayment(p.id, success: false)),
                  child: Text(s.t('pay_test_decline')),
                ),
              ]),
            ),
          ] else
            _Result(payment: p, s: s),
          if (_errorKey != null) ...[
            const SizedBox(height: 10),
            Text(s.t(_errorKey!), style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 10),
          Text(s.t('pay_server_note'), style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
        ]),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  final CheckoutPayment payment;
  final AppStrings s;
  const _Result({required this.payment, required this.s});
  @override
  Widget build(BuildContext context) {
    final ok = payment.status == 'succeeded';
    final text = ok ? s.t(payment.mode == 'test' ? 'pay_success_test' : 'pay_success') : s.t('pay_failed');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (ok ? AppColors.online : AppColors.danger).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.error_outline, color: ok ? AppColors.online : AppColors.danger),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/cargo_model.dart';
import '../../../finance/domain/finance_models.dart';
import '../../../finance/presentation/card_checkout.dart';
import '../../../finance/presentation/finance_providers.dart';
import '../../domain/cargo_vip.dart';
import '../providers/cargo_media_providers.dart';
import '../providers/cargo_providers.dart';

/// "VIP et" on my own open load (owner, 24.10.2026, 0062) — like TIR
/// Bazarı: choose 7 / 14 / 30 days, pay by card; the server makes the load
/// VIP after the verified payment. While the card checkout is not open
/// for this account (test mode is for the owner only) it says so —
/// nothing is pretended.
Future<void> showCargoVipSheet(BuildContext context, AppStrings s, CargoModel c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CargoVipSheet(s: s, cargo: c),
  );
}

class _CargoVipSheet extends ConsumerStatefulWidget {
  final AppStrings s;
  final CargoModel cargo;
  const _CargoVipSheet({required this.s, required this.cargo});

  @override
  ConsumerState<_CargoVipSheet> createState() => _CargoVipSheetState();
}

class _CargoVipSheetState extends ConsumerState<_CargoVipSheet> {
  int? _days;
  bool _busy = false;
  String? _error;

  AppStrings get s => widget.s;

  Future<void> _pay(CargoVipPlan plan, CheckoutAvailability av, List<PayMethod> methods) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await ref.read(cargoMediaRepositoryProvider).createVipOrder(widget.cargo.id, plan.days);
      if (!mounted) return;
      // This sheet closes; the checkout opens in its place.
      final nav = Navigator.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      nav.pop();
      await showModalBottomSheet<void>(
        context: nav.context,
        isScrollControlled: true,
        isDismissible: false,
        builder: (_) => CheckoutSheet(
          vip: VipCheckoutTarget(vipOrderId: order.id, amount: order.amount, currency: order.currency, cargo: true),
          s: s,
          availability: av,
          methods: methods,
        ),
      );
      container.invalidate(cargoDetailProvider(widget.cargo.id));
      container.invalidate(myCargoProvider);
      container.invalidate(marketplaceProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'cargo_vip_failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(cargoVipPlansProvider(true));
    final av = ref.watch(checkoutAvailabilityProvider).valueOrNull;
    final methods = av == null ? const <PayMethod>[] : methodsForDevice(currentDeviceKind(), av.methods);
    final canPay = av != null && av.available && methods.isNotEmpty;
    final c = widget.cargo;
    final until = c.isVipAt(DateTime.now()) ? c.featuredUntil : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.workspace_premium, color: AppColors.vipGold, size: 26),
          const SizedBox(width: 8),
          Expanded(child: Text(s.t('cargo_vip_title'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        Text(s.t('cargo_vip_body'), style: TextStyle(color: AppColors.textSoft, height: 1.35)),
        if (until != null) ...[
          const SizedBox(height: 8),
          Text(s.t('mk_vip_active_until', {'date': '${until.day}.${until.month}.${until.year}'}),
              style: const TextStyle(color: AppColors.vipGold, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 12),
        plans.when(
          loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          error: (_, __) => Text(s.t('cargo_vip_not_ready'), style: TextStyle(color: AppColors.textSoft)),
          data: (list) {
            if (list.isEmpty) return Text(s.t('mk_vip_no_plans'), style: TextStyle(color: AppColors.textSoft));
            final chosen = list.firstWhere((p) => p.days == _days, orElse: () => list.first);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final p in list)
                ListTile(
                  key: ValueKey('cargo-vip-plan-${p.days}'),
                  contentPadding: EdgeInsets.zero,
                  enabled: !_busy,
                  onTap: () => setState(() => _days = p.days),
                  leading: Icon(p.days == chosen.days ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: p.days == chosen.days ? AppColors.accent : AppColors.textSoft),
                  title: Text(s.t('mk_vip_days', {'days': '${p.days}'}), style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: Text(money(p.price, p.currency), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              const SizedBox(height: 10),
              if (canPay)
                FilledButton.icon(
                  key: const ValueKey('cargo-vip-pay'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _busy ? null : () => _pay(chosen, av, methods),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.credit_card),
                  label: Text('${s.t('pay_now')} · ${money(chosen.price, chosen.currency)}'),
                )
              else
                Container(
                  key: const ValueKey('cargo-vip-pay-soon'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Text(s.t('cargo_vip_pay_soon'), style: TextStyle(color: AppColors.blue, height: 1.35)),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(s.t(_error!), style: TextStyle(color: AppColors.danger)),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}

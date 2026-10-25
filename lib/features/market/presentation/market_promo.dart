import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../../finance/domain/finance_models.dart';
import '../../finance/presentation/card_checkout.dart';
import '../../finance/presentation/finance_providers.dart';
import '../data/market_repository.dart';
import '../domain/market_models.dart';
import 'market_providers.dart';

/// Colour of each way to the front (from AppColors).
Color marketPromoColor(MarketPromoKind k) => switch (k) {
      MarketPromoKind.bump => AppColors.promoBump,
      MarketPromoKind.vip => AppColors.promoVip,
      MarketPromoKind.premium => AppColors.promoPremium,
    };

/// The owner's icon of a way to the front (assets/images/promo).
class MarketPromoIcon extends StatelessWidget {
  final MarketPromoKind kind;
  final double size;
  const MarketPromoIcon(this.kind, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => Image.asset(kind.asset,
      key: ValueKey('promo-icon-${kind.name}'), width: size, height: size, filterQuality: FilterQuality.medium);
}

/// Small marks on an ad card (owner, 25.10.2026, like Turbo.az): crown for
/// Premium, diamond for VIP — no frame on the picture.
class MarketPromoMarks extends StatelessWidget {
  final MarketListing l;
  final double size;
  const MarketPromoMarks(this.l, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => PromoMarks(premium: l.premiumActive(), vip: l.vipActive(), size: size);
}

/// The same marks for anything with Premium / VIP (a load too, 0067).
class PromoMarks extends StatelessWidget {
  final bool premium, vip;
  final double size;
  const PromoMarks({super.key, required this.premium, required this.vip, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final marks = [
      if (premium) MarketPromoKind.premium,
      if (vip) MarketPromoKind.vip,
    ];
    if (marks.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < marks.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        MarketPromoIcon(marks[i], size: size),
      ],
    ]);
  }
}

/// What "Önə çıxar" works on: a TIR Bazarı ad (0066) or a load (0067).
/// Same sheets and checkout; each side has its own prices and orders.
abstract class PromoTarget {
  const PromoTarget();

  /// The packs of one way to the front (active ones).
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind);

  /// The date a running VIP / Premium is paid to (null = none running).
  DateTime? paidUntil(MarketPromoKind kind);

  /// An order on the server (it sets the price) → what the checkout pays.
  Future<VipCheckoutTarget> order(WidgetRef ref, MarketPromoKind kind, int qty);

  /// After the checkout: show the new state.
  void refresh(ProviderContainer c);

  /// Text key when the order cannot be made.
  String get failedKey;

  /// What the way gives, in words (a load's Premium names the Loads page).
  String bodyKey(MarketPromoKind kind) => 'mk_promo_${kind.name}_body';
}

/// A TIR Bazarı ad (0066).
class MarketPromoTarget extends PromoTarget {
  final MarketListing l;
  const MarketPromoTarget(this.l);

  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) => marketPromoPlansProvider((kind, true));

  @override
  DateTime? paidUntil(MarketPromoKind kind) => switch (kind) {
        MarketPromoKind.vip => l.vipActive() ? l.vipUntil : null,
        MarketPromoKind.premium => l.premiumActive() ? l.premiumUntil : null,
        MarketPromoKind.bump => null,
      };

  @override
  Future<VipCheckoutTarget> order(WidgetRef ref, MarketPromoKind kind, int qty) async {
    final repo = ref.read(marketRepositoryProvider);
    if (kind == MarketPromoKind.vip) {
      final o = await repo.createVipOrder(l.id, qty);
      return VipCheckoutTarget(vipOrderId: o.id, amount: o.amount, currency: o.currency);
    }
    final o = await repo.createPromoOrder(l.id, kind, qty);
    return VipCheckoutTarget(vipOrderId: o.id, amount: o.amount, currency: o.currency, promo: true);
  }

  @override
  void refresh(ProviderContainer c) {
    c.invalidate(marketListingProvider(l.id));
    c.invalidate(myMarketListingsProvider);
    c.invalidate(marketFeedProvider);
  }

  @override
  String get failedKey => 'mk_vip_failed';
}

/// "Önə çıxar" on my own active ad: İrəli çək · VIP · Premium, each with
/// its lowest price ("3 AZN-dən"), as in the owner's picture.
class MarketPromoOptions extends ConsumerWidget {
  final AppStrings s;
  final PromoTarget target;

  /// Instead of opening the sheet at once (the chooser closes first).
  final void Function(MarketPromoKind kind)? onPick;
  const MarketPromoOptions({super.key, required this.s, required this.target, this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = [
      for (final k in MarketPromoKind.values)
        _PromoCard(
          kind: k,
          s: s,
          from: marketPromoFrom(ref.watch(target.plans(k)).valueOrNull ?? const []),
          onTap: () => onPick != null ? onPick!(k) : showPromoSheet(context, s, target, k),
        ),
    ];
    return Column(key: const ValueKey('mk-promo-options'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t('mk_promo_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, c) {
        // Wide: three side by side; phone: one under the other.
        if (c.maxWidth >= 640) {
          return Row(children: [
            for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: cards[i])],
          ]);
        }
        return Column(children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 8), cards[i]],
        ]);
      }),
    ]);
  }
}

class _PromoCard extends StatelessWidget {
  final MarketPromoKind kind;
  final AppStrings s;
  final MarketPromoPlan? from;
  final VoidCallback onTap;
  const _PromoCard({required this.kind, required this.s, required this.from, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = marketPromoColor(kind);
    return Material(
      color: c.withValues(alpha: AppColors.isDay ? 0.08 : 0.12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.withValues(alpha: 0.7))),
      child: InkWell(
        key: ValueKey('mk-promo-${kind.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t('mk_promo_${kind.name}'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 2),
                if (from != null)
                  // "3 AZN-dən": the price in colour inside the sentence.
                  Text.rich(TextSpan(style: TextStyle(color: AppColors.textSoft), children: [
                    for (final (i, part) in s.t('mk_promo_from').split('{price}').indexed) ...[
                      if (i > 0)
                        TextSpan(
                            text: money(from!.price, from!.currency),
                            style: TextStyle(color: c, fontWeight: FontWeight.w600)),
                      TextSpan(text: part),
                    ],
                  ]))
                else
                  Text(s.t('mk_promo_soon'), style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
              ]),
            ),
            MarketPromoIcon(kind, size: 46),
          ]),
        ),
      ),
    );
  }
}

/// "Önə çıxar" from the ad page: the three ways, then the chosen one's sheet.
Future<void> showMarketPromoChooser(BuildContext context, AppStrings s, MarketListing l) =>
    showPromoChooser(context, s, MarketPromoTarget(l));

/// The same chooser for any [PromoTarget] (a load: 0067).
Future<void> showPromoChooser(BuildContext context, AppStrings s, PromoTarget target) {
  final outer = context;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: MarketPromoOptions(
        s: s,
        target: target,
        onPick: (k) {
          Navigator.of(sheet).pop();
          showPromoSheet(outer, s, target, k);
        },
      ),
    ),
  );
}

/// The sheet of one way to the front: what it gives, the packs, the date it
/// runs to, and the card payment (same checkout as VIP; the server sets
/// the price and applies it only after a verified payment).
Future<void> showMarketPromoSheet(BuildContext context, AppStrings s, MarketListing l, MarketPromoKind kind) =>
    showPromoSheet(context, s, MarketPromoTarget(l), kind);

Future<void> showPromoSheet(BuildContext context, AppStrings s, PromoTarget target, MarketPromoKind kind) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PromoSheet(s: s, target: target, kind: kind),
  );
}

class _PromoSheet extends ConsumerStatefulWidget {
  final AppStrings s;
  final PromoTarget target;
  final MarketPromoKind kind;
  const _PromoSheet({required this.s, required this.target, required this.kind});

  @override
  ConsumerState<_PromoSheet> createState() => _PromoSheetState();
}

class _PromoSheetState extends ConsumerState<_PromoSheet> {
  int? _qty;
  bool _busy = false;
  String? _error;

  AppStrings get s => widget.s;
  MarketPromoKind get kind => widget.kind;

  Future<void> _pay(MarketPromoPlan plan, CheckoutAvailability av, List<PayMethod> methods) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = await widget.target.order(ref, kind, plan.qty);
      if (!mounted) return;
      // This sheet closes; the checkout opens in its place.
      final nav = Navigator.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      nav.pop();
      await showModalBottomSheet<void>(
        context: nav.context,
        isScrollControlled: true,
        isDismissible: false,
        builder: (_) => CheckoutSheet(vip: target, s: s, availability: av, methods: methods),
      );
      widget.target.refresh(container);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.target.failedKey;
        });
      }
    }
  }

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(widget.target.plans(kind));
    final av = ref.watch(checkoutAvailabilityProvider).valueOrNull;
    final methods = av == null ? const <PayMethod>[] : methodsForDevice(currentDeviceKind(), av.methods);
    final canPay = av != null && av.available && methods.isNotEmpty;
    final c = marketPromoColor(kind);
    // What each one includes, as in the owner's pictures.
    final icons = switch (kind) {
      MarketPromoKind.bump => [MarketPromoKind.bump],
      MarketPromoKind.vip => [MarketPromoKind.bump, MarketPromoKind.vip],
      MarketPromoKind.premium => [MarketPromoKind.bump, MarketPromoKind.vip, MarketPromoKind.premium],
    };
    final until = widget.target.paidUntil(kind);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
          key: ValueKey('mk-promo-sheet-${kind.name}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(s.t('mk_promo_${kind.name}_title'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
              IconButton(onPressed: _busy ? null : () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              for (final k in icons) ...[
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
                  child: MarketPromoIcon(k, size: 30),
                ),
                const SizedBox(width: 10),
              ],
            ]),
            const SizedBox(height: 12),
            Text(s.t(widget.target.bodyKey(kind)),
                style: TextStyle(color: AppColors.text, fontSize: 15.5, height: 1.35)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Text(s.t('mk_promo_${kind.name}_gift'), style: TextStyle(color: c, fontWeight: FontWeight.w500)),
              ),
            ),
            if (until != null) ...[
              const SizedBox(height: 10),
              Text(s.t('mk_promo_paid_until', {'date': _date(until)}), style: TextStyle(color: AppColors.text)),
            ],
            const SizedBox(height: 14),
            plans.when(
              loading: () =>
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
              error: (_, __) => Text(s.t('home_error_loading'), style: TextStyle(color: AppColors.danger)),
              data: (list) {
                if (list.isEmpty) return Text(s.t('mk_vip_no_plans'), style: TextStyle(color: AppColors.textSoft));
                final chosen = list.firstWhere((p) => p.qty == _qty, orElse: () => list.first);
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  MouseDragScroll(child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final p in list) ...[
                        _PackTile(
                          key: ValueKey('promo-plan-${kind.name}-${p.qty}'),
                          label: s.t(kind.countsDays ? 'mk_promo_days' : 'mk_promo_times', {'n': '${p.qty}'}),
                          price: money(p.price, p.currency),
                          selected: p.qty == chosen.qty,
                          color: c,
                          onTap: _busy ? null : () => setState(() => _qty = p.qty),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ]),
                  )),
                  const SizedBox(height: 16),
                  if (canPay)
                    FilledButton.icon(
                      key: const ValueKey('promo-pay'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _busy ? null : () => _pay(chosen, av, methods),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.credit_card),
                      label: Text('${s.t('pay_now')} · ${money(chosen.price, chosen.currency)}'),
                    )
                  else
                    Container(
                      key: const ValueKey('promo-pay-soon'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Text(s.t('mk_vip_pay_soon'), style: TextStyle(color: AppColors.blue, height: 1.35)),
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

class _PackTile extends StatelessWidget {
  final String label, price;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;
  const _PackTile(
      {super.key, required this.label, required this.price, required this.selected, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : AppColors.cardAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? color : AppColors.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 92,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(label, style: TextStyle(color: AppColors.text, fontSize: 14.5)),
              const SizedBox(height: 4),
              Text(price, style: TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

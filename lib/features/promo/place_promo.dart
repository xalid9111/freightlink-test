import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../finance/presentation/card_checkout.dart';
import '../market/domain/market_models.dart';
import '../market/presentation/market_promo.dart';
import '../cargo/presentation/providers/cargo_media_providers.dart' show cargoPromoPlansProvider;

/// "Önə çıxar" for a service (Servislər) or a TIR park (TIRPark) — owner,
/// 04.11.2026, 0093. The same İrəli çək · VIP · Premium sheets, packs,
/// currency and card checkout as TIR Bazarı / Loads; each section has its
/// own prices (admin), its own orders and its own place: a promoted
/// service stands first in the Servislər list / map around its own
/// location, a promoted park on the TIRPark map / list around its own
/// location. Nothing of this is shown among Loads.
enum PlaceTarget { service, tirpark }

extension PlaceTargetX on PlaceTarget {
  String get wire => name;
}

/// What runs on one place now (only active promotions come back).
class PlacePromo {
  final String id;
  final DateTime? vipUntil, premiumUntil, liftedAt;
  final int? bumpLeft;
  const PlacePromo({required this.id, this.vipUntil, this.premiumUntil, this.liftedAt, this.bumpLeft});

  static DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  factory PlacePromo.fromJson(Map<String, dynamic> j) => PlacePromo(
        id: '${j['id']}',
        vipUntil: _d(j['vip_until']),
        premiumUntil: _d(j['premium_until']),
        liftedAt: _d(j['lifted_at']),
        bumpLeft: (j['bump_left'] as num?)?.toInt(),
      );

  bool isPremiumAt(DateTime now) => premiumUntil != null && premiumUntil!.isAfter(now);
  bool isVipAt(DateTime now) => isPremiumAt(now) || (vipUntil != null && vipUntil!.isAfter(now));
  bool get isPremium => isPremiumAt(DateTime.now());
  bool get isVip => isVipAt(DateTime.now());
  /// Lifted to the front now (İrəli çək, VIP or Premium).
  bool get isPromoted => liftedAt != null || isVip;
}

/// Promoted places first, the rest keep their order (nearest first):
/// Premium on top, then VIP / İrəli çək — each by its last lift, newest
/// first (the same rule as Loads, so every promoted place comes forward).
List<T> promotedFirst<T>(List<T> items, String Function(T) idOf, Map<String, PlacePromo> promos, {DateTime? now}) {
  if (promos.isEmpty) return items;
  final at = now ?? DateTime.now();
  final premium = <T>[], lifted = <T>[], rest = <T>[];
  for (final it in items) {
    final p = promos[idOf(it)];
    if (p == null || !(p.liftedAt != null || p.isVipAt(at))) {
      rest.add(it);
    } else if (p.isPremiumAt(at)) {
      premium.add(it);
    } else {
      lifted.add(it);
    }
  }
  int byLift(T a, T b) {
    final la = promos[idOf(a)]?.liftedAt, lb = promos[idOf(b)]?.liftedAt;
    if (la == null && lb == null) return 0;
    if (la == null) return 1;
    if (lb == null) return -1;
    return lb.compareTo(la);
  }

  // List.sort is not stable: keep the original order among equals.
  List<T> stable(List<T> l) {
    final idx = {for (var i = 0; i < l.length; i++) l[i]: i};
    return l..sort((a, b) => byLift(a, b) != 0 ? byLift(a, b) : idx[a]!.compareTo(idx[b]!));
  }

  return [...stable(premium), ...stable(lifted), ...rest];
}

/// A placed order (the server sets the price).
class PlacePromoOrder {
  final String id;
  final double amount;
  final String currency;
  const PlacePromoOrder({required this.id, required this.amount, required this.currency});

  factory PlacePromoOrder.fromJson(Map<String, dynamic> j) => PlacePromoOrder(
        id: '${j['id']}',
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AZN',
      );
}

const _timeout = Duration(seconds: 20);

/// Server calls of 0093. The database decides who may do what.
class PlacePromoRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  /// Running promotions of these places; empty when 0093 is not run yet,
  /// signed out or offline (the lists then look as before).
  Future<Map<String, PlacePromo>> state(PlaceTarget t, List<String> ids) async {
    if (ids.isEmpty || _c.auth.currentUser == null) return const {};
    try {
      final res = await _c
          .rpc('place_promo_state', params: {'p_target': t.wire, 'p_ids': ids.take(1000).toList()}).timeout(_timeout);
      final out = <String, PlacePromo>{};
      for (final r in (res as List? ?? const [])) {
        final p = PlacePromo.fromJson(Map<String, dynamic>.from(r as Map));
        out[p.id] = p;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<List<MarketPromoPlan>> plans(PlaceTarget t, MarketPromoKind kind, {bool activeOnly = true}) async {
    try {
      var q = _c.from('place_promo_plans').select().eq('target', t.wire).eq('kind', kind.wire);
      if (activeOnly) q = q.eq('is_active', true);
      final rows = await q.order('qty').timeout(_timeout);
      return [
        for (final r in rows as List)
          MarketPromoPlan(
            kind: kind,
            qty: (r['qty'] as num).toInt(),
            price: (r['price'] as num).toDouble(),
            currency: (r['currency'] as String?) ?? 'AZN',
            isActive: r['is_active'] != false,
          ),
      ];
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205') return const []; // 0093 not run yet
      rethrow;
    }
  }

  /// [places] (Premium, 0103): 'market' / 'loads' — where else it is
  /// shown; null = its own map only (the 0093 call).
  Future<PlacePromoOrder> createOrder(PlaceTarget t, String id, MarketPromoKind kind, int qty, {List<String>? places}) async {
    final res = await _c.rpc('place_promo_order_create', params: {
      'p_target': t.wire,
      'p_id': id,
      'p_kind': kind.wire,
      'p_qty': qty,
      if (places != null) 'p_places': places,
    }).timeout(_timeout);
    return PlacePromoOrder.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Admin: one pack's price / on-off (checked + logged on the server).
  Future<void> adminSetPlan(PlaceTarget t, MarketPromoKind kind, int qty, double price, {bool active = true}) =>
      _c.rpc('admin_place_set_promo_plan', params: {
        'p_target': t.wire,
        'p_kind': kind.wire,
        'p_qty': qty,
        'p_price': price,
        'p_active': active,
      }).timeout(_timeout);
}

final placePromoRepositoryProvider = Provider<PlacePromoRepository>((ref) => PlacePromoRepository());

/// Key of [placePromoStateProvider]: the section and the ids (sorted, so
/// the same places give the same key).
typedef PlacePromoKey = (PlaceTarget, String);

PlacePromoKey placePromoKey(PlaceTarget t, Iterable<String> ids) => (t, (ids.toSet().toList()..sort()).join(','));

final placePromoStateProvider = FutureProvider.autoDispose.family<Map<String, PlacePromo>, PlacePromoKey>((ref, key) {
  ref.watch(currentUserIdProvider);
  final ids = key.$2.isEmpty ? const <String>[] : key.$2.split(',');
  return ref.watch(placePromoRepositoryProvider).state(key.$1, ids);
});

final placePromoPlansProvider =
    FutureProvider.autoDispose.family<List<MarketPromoPlan>, (PlaceTarget, MarketPromoKind, bool)>((ref, k) {
  return ref.watch(placePromoRepositoryProvider).plans(k.$1, k.$2, activeOnly: k.$3);
});

/// The running promotions of these places (empty while loading).
Map<String, PlacePromo> watchPlacePromos(WidgetRef ref, PlaceTarget t, Iterable<String> ids) =>
    ref.watch(placePromoStateProvider(placePromoKey(t, ids))).valueOrNull ?? const {};

/// "Önə çıxar" on my own service / shop / park. Its Premium is always on
/// its own map and picks where else it is shown: TIR Bazarı · Yüklər
/// bölməsi (owner, 07.11.2026, 0103).
class PlacePromoTarget extends PromoTarget {
  final PlaceTarget target;
  final String id;
  final PlacePromo? now;
  const PlacePromoTarget(this.target, this.id, this.now);

  @override
  List<PromoPlace> get placeChoices => PromoPlace.values;

  /// Both places = the own price + the Yüklər Premium price.
  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> secondPlacePlans() =>
      cargoPromoPlansProvider((MarketPromoKind.premium, true));

  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) =>
      placePromoPlansProvider((target, kind, true));

  @override
  DateTime? paidUntil(MarketPromoKind kind) => switch (kind) {
        MarketPromoKind.vip => (now?.isVip ?? false) ? now!.vipUntil ?? now!.premiumUntil : null,
        MarketPromoKind.premium => (now?.isPremium ?? false) ? now!.premiumUntil : null,
        MarketPromoKind.bump => null,
      };

  @override
  Future<VipCheckoutTarget> order(WidgetRef ref, MarketPromoKind kind, int qty, {Set<PromoPlace>? places}) async {
    final o = await ref.read(placePromoRepositoryProvider).createOrder(target, id, kind, qty,
        places: kind == MarketPromoKind.premium && places != null ? promoPlacesWire(places) : null);
    return VipCheckoutTarget(vipOrderId: o.id, amount: o.amount, currency: o.currency, place: true);
  }

  @override
  void refresh(ProviderContainer c) => c.invalidate(placePromoStateProvider);

  @override
  String get failedKey => 'pp_failed';

  @override
  String bodyKey(MarketPromoKind kind) => 'pp_${target == PlaceTarget.service ? 'svc' : 'tp'}_${kind.name}_body';
}

/// The "Önə çıxar" block on my own service / park page. [open] = the place
/// may be promoted now (approved and active, with its place on the map);
/// otherwise [closedKey] says why.
class PlacePromoSection extends ConsumerWidget {
  final AppStrings s;
  final PlaceTarget target;
  final String id;
  final bool open;
  final String? closedKey;
  const PlacePromoSection(
      {super.key, required this.s, required this.target, required this.id, required this.open, this.closedKey});

  String _date(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promo = watchPlacePromos(ref, target, [id])[id];
    final area = s.t(target == PlaceTarget.service ? 'pp_area_service' : 'pp_area_tirpark');
    return Container(
      key: ValueKey('pp-section-${target.wire}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!open)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t('mk_promo_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 6),
            Text(s.t(closedKey ?? 'pp_not_open_${target.wire}'),
                key: const ValueKey('pp-closed'), style: TextStyle(color: AppColors.textSoft, height: 1.35)),
          ])
        else ...[
          MarketPromoOptions(s: s, target: PlacePromoTarget(target, id, promo)),
          if (promo != null && promo.isVip) ...[
            const SizedBox(height: 8),
            Row(children: [
              PromoMarks(premium: promo.isPremium, vip: promo.isVip),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    s.t('mk_promo_paid_until', {'date': _date((promo.isPremium ? promo.premiumUntil : promo.vipUntil ?? promo.premiumUntil)!)}),
                    key: const ValueKey('pp-running'),
                    style: TextStyle(color: AppColors.text)),
              ),
            ]),
          ] else if (promo?.bumpLeft != null) ...[
            const SizedBox(height: 8),
            Text(s.t('pp_bump_left', {'n': '${promo!.bumpLeft}'}),
                key: const ValueKey('pp-running'), style: TextStyle(color: AppColors.text)),
          ],
        ],
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textSoft),
          const SizedBox(width: 6),
          Expanded(
              child: Text(area,
                  key: const ValueKey('pp-area'), style: TextStyle(color: AppColors.textSoft, fontSize: 12.5, height: 1.35))),
        ]),
      ]),
    );
  }
}

/// The small "Reklam" mark with the crown / diamond on a promoted card.
class PlacePromoTag extends StatelessWidget {
  final AppStrings s;
  final PlacePromo promo;
  const PlacePromoTag({super.key, required this.s, required this.promo});

  @override
  Widget build(BuildContext context) {
    final c = promo.isPremium ? AppColors.promoPremium : (promo.isVip ? AppColors.promoVip : AppColors.promoBump);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PromoMarks(premium: promo.isPremium, vip: promo.isVip, size: 16),
      if (promo.isVip) const SizedBox(width: 4),
      Container(
        key: ValueKey('pp-tag-${promo.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
        child: Text(s.t('pp_ad'), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w500)),
      ),
    ]);
  }
}

/// A map pin of a promoted place: the pin with its crown / diamond (or the
/// İrəli çək arrow) on the corner.
class PlacePromoPin extends StatelessWidget {
  final Widget pin;
  final PlacePromo? promo;
  final double size;
  const PlacePromoPin({super.key, required this.pin, required this.promo, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final p = promo;
    if (p == null || !p.isPromoted) return pin;
    final kind = p.isPremium ? MarketPromoKind.premium : (p.isVip ? MarketPromoKind.vip : MarketPromoKind.bump);
    return Stack(clipBehavior: Clip.none, children: [
      pin,
      Positioned(
        right: -4,
        top: -4,
        child: Container(
          key: ValueKey('pp-pin-${p.id}'),
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: marketPromoColor(kind))),
          child: MarketPromoIcon(kind, size: size),
        ),
      ),
    ]);
  }
}

/// Admin: the prices of one way to the front for Servislər or TIRPark
/// (started from the Loads prices, 0093; each section changed apart).
class PlacePromoPricesCard extends ConsumerStatefulWidget {
  final PlaceTarget target;
  final MarketPromoKind kind;
  final Future<bool> Function(BuildContext context, Future<void> Function() action) run;
  const PlacePromoPricesCard(this.target, this.kind, {super.key, required this.run});

  @override
  ConsumerState<PlacePromoPricesCard> createState() => _PlacePromoPricesCardState();
}

class _PlacePromoPricesCardState extends ConsumerState<PlacePromoPricesCard> {
  final _price = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _price.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(MarketPromoPlan p, {bool? active}) async {
    final v = double.tryParse((_price[p.qty]?.text ?? '').replaceAll(',', '.').trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Qiyməti düzgün yazın (0-dan böyük).')));
      return;
    }
    final ok = await widget.run(context,
        () => ref.read(placePromoRepositoryProvider).adminSetPlan(widget.target, widget.kind, p.qty, v, active: active ?? p.isActive));
    if (ok) ref.invalidate(placePromoPlansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final where = widget.target == PlaceTarget.service ? 'Servis' : 'TIRPark';
    final name = switch (k) {
      MarketPromoKind.bump => 'İrəli çək',
      MarketPromoKind.vip => 'VIP',
      MarketPromoKind.premium => 'Premium',
    };
    final async = ref.watch(placePromoPlansProvider((widget.target, k, false)));
    return Card(
      key: ValueKey('admin-place-promo-${widget.target.wire}-${k.name}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            MarketPromoIcon(k, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text('$where: $name qiymətləri', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Yüklənmədi: $e', style: TextStyle(color: AppColors.danger)),
            data: (plans) => plans.isEmpty
                ? Text('Qiymət yoxdur (0093_place_promotions.sql işə salınıbmı?)', style: TextStyle(color: AppColors.danger))
                : Column(children: [
                    for (final p in plans)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          SizedBox(width: 62, child: Text(k.countsDays ? '${p.qty} gün' : '${p.qty} dəfə')),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              key: ValueKey('place-promo-price-${widget.target.wire}-${k.name}-${p.qty}'),
                              controller: _price.putIfAbsent(
                                  p.qty, () => TextEditingController(text: p.price.toStringAsFixed(p.price % 1 == 0 ? 0 : 2))),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(isDense: true, suffixText: p.currency),
                            ),
                          ),
                          FilledButton(onPressed: () => _save(p), child: const Text('Saxla')),
                          Switch(value: p.isActive, onChanged: (v) => _save(p, active: v)),
                          Text(p.isActive ? 'Aktiv' : 'Bağlı', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                        ]),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// The three price cards of one section (Admin → Servislər / TIRPark).
class PlacePromoPrices extends StatelessWidget {
  final PlaceTarget target;
  final Future<bool> Function(BuildContext context, Future<void> Function() action) run;
  const PlacePromoPrices(this.target, {super.key, required this.run});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            target == PlaceTarget.service
                ? 'Servisin sahibi onu öz yerində önə çıxarır: Servislər siyahısında və xəritədə birinci görünür. Yüklər səhifəsində göstərilmir.'
                : 'Parkın idarəçisi onu öz yerində önə çıxarır: TIRPark xəritəsində və siyahısında birinci görünür. Yüklər səhifəsində göstərilmir.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
        const SizedBox(height: 8),
        for (final k in MarketPromoKind.values) ...[
          PlacePromoPricesCard(target, k, run: run),
          const SizedBox(height: 8),
        ],
      ]);
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/cargo_model.dart';
import '../../../finance/presentation/card_checkout.dart';
import '../../../market/domain/market_models.dart';
import '../../../market/presentation/market_promo.dart';
import '../providers/cargo_media_providers.dart';
import '../providers/cargo_providers.dart';

/// "Önə çıxar" on my own open load (owner, 25.10.2026, 0067): the same
/// İrəli çək · VIP · Premium sheets and card checkout as TIR Bazarı; the
/// server sets the price and applies it only after a verified payment.
class CargoPromoTarget extends PromoTarget {
  final CargoModel cargo;
  const CargoPromoTarget(this.cargo);

  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) =>
      cargoPromoPlansProvider((kind, true));

  @override
  DateTime? paidUntil(MarketPromoKind kind) {
    final now = DateTime.now();
    return switch (kind) {
      MarketPromoKind.vip => cargo.isVipAt(now) ? cargo.featuredUntil : null,
      MarketPromoKind.premium => cargo.isPremiumAt(now) ? cargo.premiumUntil : null,
      MarketPromoKind.bump => null,
    };
  }

  @override
  Future<VipCheckoutTarget> order(WidgetRef ref, MarketPromoKind kind, int qty) async {
    final repo = ref.read(cargoMediaRepositoryProvider);
    if (kind == MarketPromoKind.vip) {
      final o = await repo.createVipOrder(cargo.id, qty);
      return VipCheckoutTarget(vipOrderId: o.id, amount: o.amount, currency: o.currency, cargo: true);
    }
    final o = await repo.createPromoOrder(cargo.id, kind, qty);
    return VipCheckoutTarget(vipOrderId: o.id, amount: o.amount, currency: o.currency, cargo: true, promo: true);
  }

  @override
  void refresh(ProviderContainer c) {
    c.invalidate(cargoDetailProvider(cargo.id));
    c.invalidate(myCargoProvider);
    c.invalidate(marketplaceProvider);
  }

  @override
  String get failedKey => 'cargo_vip_failed';

  @override
  String bodyKey(MarketPromoKind kind) =>
      kind == MarketPromoKind.premium ? 'cargo_promo_premium_body' : super.bodyKey(kind);
}

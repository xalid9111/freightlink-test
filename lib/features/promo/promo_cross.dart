import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/constants/countries.dart';
import '../../core/localization/app_strings.dart';
import '../../core/localization/locale_controller.dart';
import '../../core/router/safe_navigation.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/mouse_drag_scroll.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../cargo/presentation/providers/cargo_providers.dart';
import '../market/presentation/market_promo.dart' show MarketPromoIcon;
import '../market/domain/market_models.dart' show MarketPromoKind;
import '../market/presentation/market_providers.dart';

/// Premium of an item in the OTHER section (owner, 07.11.2026, 0101): the
/// loads whose Premium chose TIR Bazarı ([PromoPlace.market] → 'market') and
/// the TIR Bazarı ads whose Premium chose Yüklər ('loads'). Ids only, newest
/// first; the items themselves come from their own providers. Empty before
/// SQL 0101.
final promoCrossProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, place) async {
  ref.watch(currentUserIdProvider);
  try {
    final res = await SupabaseConfig.client.rpc('promo_cross_latest', params: {'p_place': place, 'p_limit': 12}).timeout(const Duration(seconds: 15));
    return [for (final r in (res as List? ?? const [])) '${(r as Map)['source_id']}'];
  } on PostgrestException {
    return const [];
  } catch (_) {
    return const [];
  }
});

class _StripFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String stripKey;
  const _StripFrame({required this.title, required this.children, required this.stripKey});

  @override
  Widget build(BuildContext context) => Column(
        key: ValueKey(stripKey),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const MarketPromoIcon(MarketPromoKind.premium, size: 20),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.text)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: MouseDragScroll(child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => children[i],
            )),
          ),
        ],
      );
}

Widget _card({required Key key, required VoidCallback onTap, required String title, required String line, String? price}) => SizedBox(
      width: 230,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.promoPremium.withValues(alpha: 0.8), width: 1.4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text, fontSize: 14.5)),
              const SizedBox(height: 4),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
              if (price != null) ...[
                const SizedBox(height: 4),
                Text(price, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ),
      ),
    );

/// TIR Bazarı: "Premium yüklər" — loads whose Premium chose TIR Bazarı; a
/// tap opens the load.
class CrossPremiumLoadsStrip extends ConsumerWidget {
  final AppStrings s;
  const CrossPremiumLoadsStrip({super.key, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final ids = ref.watch(promoCrossProvider('market')).valueOrNull ?? const <String>[];
    final cards = <Widget>[
      for (final id in ids)
        if (ref.watch(cargoDetailProvider(id)).valueOrNull case final c?)
          _card(
            key: ValueKey('cross-load-${c.id}'),
            onTap: () => context.pushOnce('/load/${c.id}'),
            title: '${Countries.label(c.pickupCountry, lang)} → ${Countries.label(c.destinationCountry, lang)}',
            line: '${c.pickupCity} → ${c.destinationCity}',
            price: c.offeredPrice > 0 ? '${c.offeredPrice.toStringAsFixed(0)} ${c.currency}' : null,
          ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _StripFrame(stripKey: 'cross-premium-loads', title: s.t('promo_cross_loads'), children: cards),
    );
  }
}

/// Yüklər: "Premium · TIR Bazarı" — TIR Bazarı ads whose Premium chose
/// Yüklər; a tap opens the ad.
class CrossPremiumMarketStrip extends ConsumerWidget {
  final AppStrings s;
  const CrossPremiumMarketStrip({super.key, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(promoCrossProvider('loads')).valueOrNull ?? const <String>[];
    final cards = <Widget>[
      for (final id in ids)
        if (ref.watch(marketListingProvider(id)).valueOrNull case final l?)
          _card(
            key: ValueKey('cross-ad-${l.id}'),
            onTap: () => context.pushOnce('/market/l/${l.id}'),
            title: [l.brand, l.model].whereType<String>().where((x) => x.trim().isNotEmpty).join(' '),
            line: [if (l.year != null) '${l.year}', if ((l.city ?? '').isNotEmpty) l.city!].join(' · '),
            price: l.price == null ? null : '${l.price!.toStringAsFixed(0)} ${l.currency}',
          ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _StripFrame(stripKey: 'cross-premium-ads', title: s.t('promo_cross_ads'), children: cards),
    );
  }
}

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

/// Loads whose Premium chose TIR Bazarı (owner, 07.11.2026, 0101; paid
/// before 0102, they run to their end — Yüklər takes no advertising any
/// more). Ids only, newest first; the loads come from their own provider.
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

/// One park / service / shop of another section whose Premium chose this
/// section (owner, 07.11.2026, 0102).
class PlaceCrossItem {
  final String kind; // 'service' | 'tirpark'
  final String id;
  final String name;
  final String? city;
  final bool shop;
  const PlaceCrossItem({required this.kind, required this.id, required this.name, this.city, this.shop = false});

  factory PlaceCrossItem.fromJson(Map<String, dynamic> j) => PlaceCrossItem(
        kind: '${j['source_kind']}',
        id: '${j['source_id']}',
        name: '${j['name'] ?? ''}',
        city: j['city'] as String?,
        shop: j['shop'] == true,
      );

  bool get isPark => kind == 'tirpark';

  /// The item's own page.
  String get route => isPark ? '/tirpark/p/$id' : '/service/$id';

  /// Park · Servis · Mağaza.
  String labelKey() => isPark ? 'promo_place_kind_park' : (shop ? 'promo_place_kind_shop' : 'promo_place_kind_service');
}

/// Key: the section ('parks' | 'services' | 'shops') and the map's centre
/// (rounded, so small moves keep the same list).
typedef PlaceCrossKey = (String, double, double);

PlaceCrossKey placeCrossKey(String place, double lat, double lng) =>
    (place, (lat * 10).roundToDouble() / 10, (lng * 10).roundToDouble() / 10);

/// The other sections' Premium for this section around the map's centre
/// (100 km, newest first). Empty before SQL 0102, signed out or offline.
final placeCrossProvider = FutureProvider.autoDispose.family<List<PlaceCrossItem>, PlaceCrossKey>((ref, k) async {
  ref.watch(currentUserIdProvider);
  if (SupabaseConfig.client.auth.currentUser == null) return const [];
  try {
    final res = await SupabaseConfig.client.rpc('place_cross_latest',
        params: {'p_place': k.$1, 'p_lat': k.$2, 'p_lng': k.$3, 'p_limit': 12}).timeout(const Duration(seconds: 15));
    return [for (final r in (res as List? ?? const [])) PlaceCrossItem.fromJson(Map<String, dynamic>.from(r as Map))];
  } catch (_) {
    return const [];
  }
});

/// Parklar / Servislər / Mağazalar: "Premium" — parks, services and shops of
/// the other sections whose Premium chose this one; a tap opens the page.
class PlaceCrossStrip extends ConsumerWidget {
  final AppStrings s;
  final String place;
  final double lat, lng;
  const PlaceCrossStrip({super.key, required this.s, required this.place, required this.lat, required this.lng});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(placeCrossProvider(placeCrossKey(place, lat, lng))).valueOrNull ?? const <PlaceCrossItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _StripFrame(
        stripKey: 'place-cross-$place',
        title: s.t('promo_cross_places'),
        children: [
          for (final it in items)
            _card(
              key: ValueKey('place-cross-${it.id}'),
              onTap: () => context.pushOnce(it.route),
              title: it.name,
              line: [s.t(it.labelKey()), if ((it.city ?? '').trim().isNotEmpty) it.city!.trim()].join(' · '),
            ),
        ],
      ),
    );
  }
}

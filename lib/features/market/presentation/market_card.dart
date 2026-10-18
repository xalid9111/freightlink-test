import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/market_models.dart';
import 'market_providers.dart';

const kVipGold = Color(0xFFFFC83D);

/// "👑 VIP" badge.
class VipBadge extends StatelessWidget {
  final bool big;
  const VipBadge({super.key, this.big = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 12 : 8, vertical: big ? 5 : 3),
      decoration: BoxDecoration(color: kVipGold, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium, size: big ? 18 : 14, color: Colors.black),
        const SizedBox(width: 4),
        Text('VIP', style: TextStyle(fontSize: big ? 15 : 12, fontWeight: FontWeight.w900, color: Colors.black)),
      ]),
    );
  }
}

/// Photo or a neutral placeholder (never a fake picture).
class MarketPhoto extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  const MarketPhoto({super.key, required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.cardAlt,
      alignment: Alignment.center,
      child: const Icon(Icons.local_shipping_outlined, color: AppColors.textSoft, size: 36),
    );
    if (url == null) return placeholder;
    return Image.network(
      url!,
      fit: fit,
      cacheWidth: 800, // decoded small: fast lists on phones
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (c, child, p) => p == null ? child : placeholder,
    );
  }
}

/// Heart on a card / the detail page.
class FavoriteHeart extends ConsumerWidget {
  final String id;
  final double size;
  const FavoriteHeart({super.key, required this.id, this.size = 20});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(marketFavoriteIdsProvider).contains(id);
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => ref.read(marketFavoriteIdsProvider.notifier).toggle(id).catchError((_) {}),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(on ? Icons.favorite : Icons.favorite_border, size: size, color: on ? AppColors.accent : Colors.white),
        ),
      ),
    );
  }
}

/// One ad in the 2-column grid (Şəkil 2) and in "similar ads" (Şəkil 5).
class MarketCard extends ConsumerWidget {
  final MarketListing l;
  final bool compact;
  const MarketCard({super.key, required this.l, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final vip = l.vipActive();
    final lang = ref.watch(currentLocaleProvider).languageCode;
    // Stored like loads (English catalogue names), shown in the app language.
    final place = [
      if ((l.city ?? '').trim().isNotEmpty) Cities.label(l.city!, lang),
      if ((l.country ?? '').trim().isNotEmpty) Countries.find(l.country)?.name(lang) ?? l.country!,
    ].join(', ');
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushOnce('/market/l/${l.id}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: vip ? kVipGold.withValues(alpha: 0.6) : AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: compact ? 1.45 : 1.55,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MarketPhoto(url: l.cover),
                    if (vip) const Positioned(left: 8, top: 8, child: VipBadge()),
                    Positioned(right: 6, top: 6, child: FavoriteHeart(id: l.id, size: 18)),
                    if (l.photos.length > 1 && !compact)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.photo_outlined, size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('${l.photos.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    if (l.status == MarketStatus.sold)
                      Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: Text(s.t('mk_sold'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(compact ? [l.brand, l.model].whereType<String>().join(' ') : l.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (compact && l.year != null)
                      Text('${l.year}', style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(marketPrice(l.price, l.currency),
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(
                      [if (l.mileageKm != null) marketKm(l.mileageKm), if (place.isNotEmpty) place].join(' · '),
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/market_models.dart';
import 'market_promo.dart';
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
      child: Icon(Icons.local_shipping_outlined, color: AppColors.textSoft, size: 36),
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
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: compact ? 1.45 : 1.55,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // No frame on the picture: Premium / VIP marks sit by
                    // the price (owner, 25.10.2026, 0066).
                    MarketPhoto(url: l.cover),
                    Positioned(right: 6, top: 6, child: FavoriteHeart(id: l.id, size: 18)),
                    if (l.onOrder) Positioned(left: 8, bottom: 8, child: MarketOnOrderTag(s: s)),
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
                            Text('${l.photos.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    if (l.status == MarketStatus.sold)
                      Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: Text(s.t('mk_sold'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
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
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14.5)),
                    if (compact && l.year != null)
                      Text('${l.year}', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(
                        child: Text(marketPrice(l.price, l.currency),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 17)),
                      ),
                      MarketPromoMarks(l),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      [if (l.mileageKm != null) marketKm(l.mileageKm), if (place.isNotEmpty) place].join(' · '),
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSoft, fontSize: 12),
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

/// Details line under the title: "2017, 2.2 L, 140 000 km".
String marketCardDetails(MarketListing l) => [
      if (l.year != null) '${l.year}',
      if (l.engineL != null) '${l.engineL!.toStringAsFixed(1)} L',
      if (l.mileageKm != null) marketKm(l.mileageKm),
    ].join(', ');

/// Phone feed card (owner, 21.10.2026, like the picture he sent): the photo
/// on top with only the heart on it, the texts under it — price, name,
/// details, place + time, a small crown for VIP. The computer page and the
/// other lists keep [MarketCard].
/// "Sifarişlə" on the picture of an ad brought on order (0065).
class MarketOnOrderTag extends StatelessWidget {
  final AppStrings s;
  const MarketOnOrderTag({super.key, required this.s});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('mk-on-order'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(10)),
        child: Text(s.t('mk_avail_on_order'),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      );
}

class MarketFeedCard extends ConsumerWidget {
  final MarketListing l;
  const MarketFeedCard({super.key, required this.l});

  /// Smallest grid row height for this card.
  static const double extent = 236;

  /// Grid row height that fits the picture and the four text lines at the
  /// chosen text size (owner, 25.10.2026: the cards must not run into each
  /// other with a larger text size).
  static double extentFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // The same style the card's texts get (font, flag fallback, height).
    final base = DefaultTextStyle.of(context).style;
    double line(double size) => (TextPainter(
          text: TextSpan(text: 'Ağ', style: base.merge(TextStyle(fontSize: size))),
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout())
            .height;
    // The last line also holds the Premium / VIP marks (18 high).
    final last = line(12) > 18 ? line(12) : 18.0;
    final h = 140 + 8 + line(17) + 2 + line(14.5) + line(13) + 2 + last + 6;
    return h > extent ? h : extent;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final city = (l.city ?? '').trim().isNotEmpty
        ? Cities.label(l.city!, lang)
        : ((l.country ?? '').trim().isNotEmpty ? Countries.find(l.country)?.name(lang) ?? l.country! : '');
    final (agoKey, agoN) = marketAgo(l.publishedAt ?? l.createdAt);
    final when = s.t(agoKey, {'n': '$agoN'});
    final details = marketCardDetails(l);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.pushOnce('/market/l/${l.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // No frame or seal on the picture: Premium / VIP marks sit
                  // at the end of the city line (owner, 25.10.2026, 0066).
                  MarketPhoto(url: l.cover),
                  Positioned(right: 6, top: 6, child: FavoriteHeart(id: l.id, size: 18)),
                  if (l.onOrder) Positioned(left: 8, bottom: 8, child: MarketOnOrderTag(s: s)),
                  if (l.status == MarketStatus.sold)
                    Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      alignment: Alignment.center,
                      child: Text(s.t('mk_sold'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(marketPrice(l.price, l.currency),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 17)),
          const SizedBox(height: 2),
          Text([l.brand, l.model].whereType<String>().join(' '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w400, fontSize: 14.5)),
          if (details.isNotEmpty)
            Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text, fontSize: 13)),
          const SizedBox(height: 2),
          Row(children: [
            Expanded(
              child: Text([if (city.isNotEmpty) city, when].join(', '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            ),
            MarketPromoMarks(l, key: const ValueKey('feed-marks')),
          ]),
        ],
      ),
    );
  }
}

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
import 'package:latlong2/latlong.dart';
import '../covers/profile_covers.dart';
import '../services/presentation/services_providers.dart' show serviceByIdProvider, userLocationProvider;
import '../tirpark/data/tir_park_repository.dart' show tirParksProvider;
import '../market/domain/market_models.dart' show MarketPromoKind;

/// Loads whose Premium chose TIR Bazarı (owner, 07.11.2026, 0101; paid
/// before 0102, they run to their end — Yüklər takes no advertising any
/// more). Ids only, newest first; the loads come from their own provider.
final promoCrossProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, place) async {
  ref.watch(currentUserIdProvider);
  try {
    final res = await SupabaseConfig.client
        .rpc('promo_cross_latest', params: {'p_place': place, 'p_limit': 12}).timeout(const Duration(seconds: 15));
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

/// One park / service / shop whose Premium chose TIR Bazarı or Yüklər
/// (owner, 07.11.2026, 0103).
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

/// Parks, services and shops whose Premium chose this section ('market' =
/// TIR Bazarı, 'loads' = Yüklər; 0103), newest first. Empty before SQL
/// 0103, signed out or offline.
final placeCrossProvider = FutureProvider.autoDispose.family<List<PlaceCrossItem>, String>((ref, place) async {
  ref.watch(currentUserIdProvider);
  if (SupabaseConfig.client.auth.currentUser == null) return const [];
  try {
    final res = await SupabaseConfig.client
        .rpc('place_cross_latest', params: {'p_place': place, 'p_limit': 12}).timeout(const Duration(seconds: 15));
    return [for (final r in (res as List? ?? const [])) PlaceCrossItem.fromJson(Map<String, dynamic>.from(r as Map))];
  } catch (_) {
    return const [];
  }
});

/// What the ad card shows of a park / service / shop: its picture, one line
/// about it and its place (from the existing service / park data).
class PlaceAdInfo {
  final String? photo; // a network picture; null = the default picture
  final String? about;
  final double? lat, lng;
  const PlaceAdInfo({this.photo, this.about, this.lat, this.lng});
}

/// The first line of a text (no made-up words: empty → null).
String? firstLine(String? t) {
  final l = (t ?? '').split('\n').map((x) => x.trim()).firstWhere((x) => x.isNotEmpty, orElse: () => '');
  return l.isEmpty ? null : l;
}

/// "Bakı · 5 km": the city and, when the user's place is known, the distance.
String placeAdWhere(String? city, double? km) => [
      if ((city ?? '').trim().isNotEmpty) city!.trim(),
      if (km != null) '${km < 10 ? km.toStringAsFixed(1) : km.round()} km',
    ].join(' · ');

final _servicePlaceAdProvider = FutureProvider.autoDispose.family<PlaceAdInfo, String>((ref, id) async {
  final p = await ref.watch(serviceByIdProvider(id).future);
  final media = await ref.watch(placeMediaProvider((CoverSection.service, id)).future).catchError((_) => const PlaceMedia());
  return PlaceAdInfo(
    photo: p?.photos.firstOrNull ?? media.cover ?? media.logo,
    about: firstLine(p?.description) ?? firstLine(p?.specialty),
    lat: p?.lat,
    lng: p?.lng,
  );
});

final _parkPlaceAdProvider = FutureProvider.autoDispose.family<PlaceAdInfo, (String, AppStrings)>((ref, k) async {
  final parks = await ref.watch(tirParksProvider.future);
  final p = parks.where((x) => x.id == k.$1).firstOrNull;
  final media = await ref.watch(placeMediaProvider((CoverSection.park, k.$1)).future).catchError((_) => const PlaceMedia());
  final am = p == null ? const <String>[] : [for (final a in p.amenities.take(3)) k.$2.t('tp_am_$a')];
  return PlaceAdInfo(
    photo: p?.photoUrls.firstOrNull ?? media.cover ?? media.logo,
    about: am.isNotEmpty ? am.join(' · ') : firstLine(p?.note),
    lat: p?.lat,
    lng: p?.lng,
  );
});

/// TIR Bazarı / Yüklər: the ad card of the parks, services and shops whose
/// Premium chose this section (owner's picture, 07.11.2026; 0103): the
/// picture, "REKLAM", the kind's icon + name, one line about it, the city ·
/// distance and "Profilə bax". Several = swiped left / right with dots.
class PlaceCrossStrip extends ConsumerStatefulWidget {
  final AppStrings s;
  final String place;
  const PlaceCrossStrip({super.key, required this.s, required this.place});

  @override
  ConsumerState<PlaceCrossStrip> createState() => _PlaceCrossStripState();
}

class _PlaceCrossStripState extends ConsumerState<PlaceCrossStrip> {
  final _page = PageController();
  int _at = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(placeCrossProvider(widget.place)).valueOrNull ?? const <PlaceCrossItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    // Grows with the text size (Profil → 1…5), so nothing is cut.
    final h = 150 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    return Padding(
      key: ValueKey('place-cross-${widget.place}'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: h + 8,
          child: MouseDragScroll(child: PageView.builder(
              scrollDirection: Axis.horizontal,
              controller: _page,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _at = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: PlaceAdCard(s: widget.s, item: items[i]),
              ),
            ),
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _at ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _at ? AppColors.accent : AppColors.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// One ad card (the owner's picture).
class PlaceAdCard extends ConsumerWidget {
  final AppStrings s;
  final PlaceCrossItem item;
  const PlaceAdCard({super.key, required this.s, required this.item});

  IconData get _icon => item.isPark ? Icons.local_parking : (item.shop ? Icons.storefront : Icons.build);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = (item.isPark ? ref.watch(_parkPlaceAdProvider((item.id, s))) : ref.watch(_servicePlaceAdProvider(item.id))).valueOrNull ??
        const PlaceAdInfo();
    final me = ref.watch(userLocationProvider).point;
    final km = me == null || info.lat == null || info.lng == null
        ? null
        : const Distance().as(LengthUnit.Meter, me, LatLng(info.lat!, info.lng!)) / 1000;
    final where = placeAdWhere(item.city, km);
    void open() => context.pushOnce(item.route);
    final c = AppColors.accent;
    final fallback = Image.asset(defaultServiceCover(shop: item.shop), fit: BoxFit.cover);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('place-ad-${item.id}'),
        borderRadius: BorderRadius.circular(18),
        onTap: open,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.withValues(alpha: 0.75), width: 1.4),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.22), blurRadius: 14, spreadRadius: 0.5)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // The picture (left).
            Expanded(
              flex: 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child:
                    info.photo == null ? fallback : Image.network(info.photo!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 11,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  key: const ValueKey('place-ad-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(6)),
                  child: Text(s.t('pp_ad').toUpperCase(),
                      style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(_icon, size: 18, color: c),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ]),
                if (info.about != null) ...[
                  const SizedBox(height: 3),
                  Text(info.about!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textSoft, fontSize: 12.5, height: 1.25)),
                ],
                const Spacer(),
                Row(children: [
                  if (where.isNotEmpty) ...[
                    Icon(Icons.place_outlined, size: 15, color: AppColors.textSoft),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: 2,
                      child: Text(where,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 6),
                  // Shrinks on a narrow phone / big text instead of overflowing.
                  Flexible(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: FilledButton(
                          key: ValueKey('place-ad-open-${item.id}'),
                          onPressed: open,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentFill,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(s.t('job_view_profile'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            const Icon(Icons.chevron_right, size: 18),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import 'providers/cargo_providers.dart';
import 'widgets/cargo_card.dart';
import '../../../core/constants/countries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/cargo_model.dart';
import 'widgets/live_map.dart';
import 'widgets/wheel_feed.dart';
import '../../ads/presentation/ads_providers.dart';
import '../../ads/presentation/sponsored_banner.dart';
import '../../../models/ad_models.dart';
import 'providers/route_filter.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';

/// The "Home" tab body (bottom-nav branch 0) — the real, live cargo
/// marketplace, connected to Supabase via marketplaceProvider. No
/// demo/mock data anywhere in this file.
class CargoMarketplaceScreen extends ConsumerWidget {
  const CargoMarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final marketplaceAsync = ref.watch(marketplaceProvider);
    final cargoList = marketplaceAsync.valueOrNull ?? const <CargoModel>[];
    final filter = ref.watch(routeFilterProvider);
    final allAds = ref.watch(liveAdsProvider).valueOrNull ?? const <Ad>[];
    // Admin switch (default OFF): no ads and no empty ad slots at all.
    final adsOn = ref.watch(homeAdsEnabledProvider).valueOrNull ?? false;
    // Admin: position of the ads and how many minutes one ad stays (0025).
    final layout = ref.watch(adsFeedLayoutProvider).valueOrNull ?? AdFeedLayout.defaults;
    final minute = layout.rotateMinutes > 0 ? (ref.watch(adMinuteTickProvider).valueOrNull ?? 0) : 0;
    final rotation = layout.rotateMinutes > 0 ? minute ~/ layout.rotateMinutes : 0;
    final shown = filter.isActive ? cargoList.where(filter.matches).toList() : cargoList;

    return Scaffold(
      // "Add load" moved to the bottom navigation bar.
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketplaceProvider);
          ref.invalidate(liveAdsProvider);
          ref.invalidate(homeAdsEnabledProvider);
          ref.invalidate(adsFeedLayoutProvider);
          ref.invalidate(activeCarriersCountProvider);
          ref.invalidate(newCargo24hCountProvider);
        },
        // Open Loads feed = 3D wheel (scale / veil / tilt by distance from
        // the screen centre, detent haptic, gentle snap).
        child: WheelScope(
          child: CustomScrollView(
          // iOS-style momentum everywhere: long, soft glide and no hard stop.
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _Hero(strings: strings, cargoList: cargoList, loaded: marketplaceAsync.hasValue)),
            SliverToBoxAdapter(child: _RouteSearch(strings: strings)),
            SliverToBoxAdapter(
              child: Padding(
                key: _feedHeaderKey,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(strings.t('home_open_loads'), style: AppFonts.display(size: 22, color: AppColors.text)),
                    const Spacer(),
                    if (marketplaceAsync.hasValue)
                      Text(strings.t('home_results', {'count': '${shown.length}'}),
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                  ],
                ),
              ),
            ),
            ...marketplaceAsync.when<List<Widget>>(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
                ),
              ],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: _ErrorState(
                    message: strings.t('home_error_loading'),
                    retryLabel: strings.t('home_retry'),
                    onRetry: () => ref.invalidate(marketplaceProvider),
                  ),
                ),
              ],
              data: (all) {
                final list = filter.isActive ? all.where(filter.matches).toList() : all;
                // Admin order (0026): smaller priority first.
                final ads = allAds.where((ad) => _adMatchesLoads(ad, list)).toList()
                  ..sort((a, b) => a.priority != b.priority ? a.priority.compareTo(b.priority) : a.startsAt.compareTo(b.startsAt));
                // No live ad → no ad slot at all (never an empty card).
                final showAds = adsOn && ads.isNotEmpty;
                // No repeat (default): at most one place per ad.
                final plan = _feedPlan(list.length, showAds, layout, maxAds: layout.repeat ? null : ads.length);
                if (list.isEmpty && filter.isActive) {
                  return [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                        child: Column(
                          children: [
                            Icon(Icons.search_off, size: 40, color: AppColors.textSoft),
                            const SizedBox(height: 10),
                            Text(strings.t('route_no_results'), textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: () => ref.read(routeFilterProvider.notifier).state = const RouteFilter(),
                              child: Text(strings.t('route_clear')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                }
                if (list.isEmpty) return [SliverToBoxAdapter(child: _EmptyMarketplace(strings: strings))];
                return [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    // first ad after N loads, then one after every M loads (admin
                    // setting); live ads take turns per slot and, if set, per X minutes.
                    sliver: SliverList.builder(
                      itemCount: plan.length,
                      itemBuilder: (context, i) {
                        final slot = plan[i];
                        if (slot.isAd) {
                          // Every X minutes the order moves one place: the last ad
                          // comes to the front (Dart % is never negative here).
                          final ad = ads[(slot.index - rotation) % ads.length];
                          return WheelItem(
                            index: i,
                            isAd: true,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 10, 0, 18),
                              child: SponsoredBanner(key: ValueKey('ad-${slot.index}-${ad.id}'), ad: ad, strings: strings),
                            ),
                          );
                        }
                        final cargo = list[slot.index];
                        return WheelItem(
                          index: i,
                          isAd: false,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CargoCard(
                              cargo: cargo,
                              strings: strings,
                              compact: true,
                              onTap: () => context.pushOnce('/cargo/${cargo.id}'),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
        ),
      ),
    );
  }
}

bool _adMatchesLoads(Ad ad, List<CargoModel> loads) {
  if (ad.targetCountries.isEmpty && (ad.routeFrom ?? '').trim().isEmpty && (ad.routeTo ?? '').trim().isEmpty) return true;
  String norm(String value) => Countries.normalize(value);
  return loads.any((load) {
    final fromCode = Countries.find(load.pickupCountry)?.code;
    final toCode = Countries.find(load.destinationCountry)?.code;
    final countryMatches = ad.targetCountries.isEmpty ||
        ad.targetCountries.contains(fromCode) || ad.targetCountries.contains(toCode);
    final fromMatches = (ad.routeFrom ?? '').trim().isEmpty || norm(Countries.canonical(ad.routeFrom!)) == norm(Countries.canonical(load.pickupCountry));
    final toMatches = (ad.routeTo ?? '').trim().isEmpty || norm(Countries.canonical(ad.routeTo!)) == norm(Countries.canonical(load.destinationCountry));
    return countryMatches && fromMatches && toMatches;
  });
}

/// Dark hero: brand row, live-map title, the animated map, REAL stats
/// computed from the open marketplace (no invented numbers), and the
/// most common routes among the open loads.
class _Hero extends ConsumerWidget {
  final AppStrings strings;
  final List<CargoModel> cargoList;
  final bool loaded;
  const _Hero({required this.strings, required this.cargoList, required this.loaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeCode = ref.watch(currentLocaleProvider).languageCode;

    // Real figures from the loaded list.
    String key(String v) => Countries.find(v)?.code ?? Countries.normalize(v);
    final routeCounts = <String, int>{};
    final routeSample = <String, CargoModel>{};
    for (final c in cargoList) {
      final a = key(c.pickupCountry);
      final b = key(c.destinationCountry);
      final r = '$a>$b';
      routeCounts[r] = (routeCounts[r] ?? 0) + 1;
      routeSample.putIfAbsent(r, () => c);
    }
    final topRoutes = routeCounts.keys.toList()..sort((x, y) => routeCounts[y]!.compareTo(routeCounts[x]!));

    String stat(int n) => loaded ? '$n' : '—';

    // Day mode: title, map and counters stand in one cloud scene (the
    // clouds above / below the map are separate pictures that continue it).
    final day = AppColors.isDay;
    final topPad = MediaQuery.of(context).padding.top + 10;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(top: day ? 0 : topPad, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DayScene(
            show: day,
            asset: 'assets/images/world_map_day_top.jpg',
            alignment: Alignment.bottomCenter,
            child: Padding(
            padding: EdgeInsets.only(top: day ? topPad : 0),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.show_chart, color: AppColors.accentFill, size: 20),
                const SizedBox(width: 4),
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'Freight', style: AppFonts.display(size: 18, color: AppColors.text)),
                  TextSpan(text: 'Link', style: AppFonts.display(size: 18, color: AppColors.accent)),
                ])),
                const Spacer(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(strings.t('home_live_map'), style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2)),
                ]),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${strings.t('home_hero_1')} '),
                    TextSpan(text: strings.t('home_hero_2'), style: TextStyle(color: AppColors.accent)),
                    TextSpan(text: ' ${strings.t('home_hero_3')}'),
                  ]),
                  style: AppFonts.display(size: 20, color: AppColors.text, height: 1.1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
            ]),
            ),
          ),
          // Full width, edge to edge; edges fade into the page colour.
          LiveMap(liveLabel: strings.t('map_live_badge')),
          _DayScene(
            show: day,
            asset: 'assets/images/world_map_day_bottom.jpg',
            alignment: Alignment.topCenter,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          const SizedBox(height: 14),
          // Three live counters (all real numbers from the database).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatCard(
                  icon: Icons.local_shipping,
                  color: AppColors.accent,
                  value: stat(cargoList.length),
                  label: strings.t('home_stat_active'),
                  onTap: () => _scrollToFeed(),
                ),
                const SizedBox(width: 6),
                _StatCard(
                  icon: Icons.groups_2,
                  color: AppColors.blue,
                  value: ref.watch(activeCarriersCountProvider).whenOrNull(data: (n) => '$n') ?? '—',
                  label: strings.t('home_stat_carriers'),
                ),
                const SizedBox(width: 6),
                _StatCard(
                  icon: Icons.bar_chart_rounded,
                  color: AppColors.online,
                  value: ref.watch(newCargo24hCountProvider).whenOrNull(data: (n) => '$n') ?? '—',
                  label: strings.t('home_stat_24h'),
                  onTap: () => _scrollToFeed(),
                ),
                const Spacer(),
                // "Yük əlavə et" — the add-load button (was the orange + in
                // the bottom bar; same form: /cargo/create).
                _AddLoadButton(label: strings.t('nav_add_cargo'), onTap: () => context.pushOnce('/cargo/create')),
              ],
            ),
          ),
            ]),
          ),
          if (topRoutes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(strings.t('home_popular_routes'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSoft)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: MouseDragScroll(child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: topRoutes.length > 5 ? 5 : topRoutes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final r = topRoutes[i];
                  final sample = routeSample[r]!;
                  final from = Countries.find(sample.pickupCountry);
                  final to = Countries.find(sample.destinationCountry);
                  final label = (from != null && to != null)
                      ? '${from.code} → ${to.code}'
                      : '${Countries.label(sample.pickupCountry, localeCode)} → ${Countries.label(sample.destinationCountry, localeCode)}';
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    // Tap a popular route to filter the list to it.
                    onTap: (from != null && to != null)
                        ? () => ref.read(routeFilterProvider.notifier).state = RouteFilter(from: from.code, to: to.code)
                        : null,
                    child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        if (from != null) Text(from.flag, style: const TextStyle(fontSize: 18)),
                        if (from != null && to != null)
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('→', style: TextStyle(color: AppColors.accent))),
                        if (to != null) Text(to.flag, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            Text(strings.t('home_route_count', {'count': '${routeCounts[r]}'}),
                                style: TextStyle(fontSize: 10.5, color: AppColors.textSoft)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  );
                },
              )),
            ),
          ],
        ],
      ),
    );
  }
}

/// Day mode: [child] drawn on a cloud picture shown at the screen width
/// ([alignment] = the edge that touches the map, so the clouds continue the
/// map's own). Night: just [child].
class _DayScene extends StatelessWidget {
  final bool show;
  final String asset;
  final Alignment alignment;
  final Widget child;
  const _DayScene({required this.show, required this.asset, required this.alignment, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(image: AssetImage(asset), fit: BoxFit.fitWidth, alignment: alignment),
      ),
      child: child,
    );
  }
}

/// Key of the "Open loads" header — stat cards scroll to it.
final GlobalKey _feedHeaderKey = GlobalKey();

void _scrollToFeed() {
  final ctx = _feedHeaderKey.currentContext;
  if (ctx != null) {
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }
}

/// Tiny counter pill (~4 mm tall, ~1 cm wide): coloured icon + number.
/// The label is kept as a tooltip / screen-reader text.
/// "Yük əlavə et" + big orange round "+" (under the live map).
class _AddLoadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddLoadButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 14, color: AppColors.textSoft, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accentFill,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Color(0x66D4420E), blurRadius: 14, offset: Offset(0, 4))],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _StatCard({required this.icon, required this.color, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: '$label: $value',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 24,
            constraints: const BoxConstraints(minWidth: 60),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(value,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.text, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyMarketplace extends StatelessWidget {
  final AppStrings strings;
  const _EmptyMarketplace({required this.strings});

  @override
  Widget build(BuildContext context) {
    return Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(strings.t('home_empty_title'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(strings.t('home_empty_body'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.retryLabel, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 44, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
                ],
              ),
            ),
    );
  }
}


/// "Find a load by route": FROM → TO country buttons (with ⇅ swap),
/// one-tap "my routes" chips saved on the device, and a star to save the
/// current route. Filters the list below instantly — no scrolling.
class _RouteSearch extends ConsumerWidget {
  final AppStrings strings;
  const _RouteSearch({required this.strings});

  Future<void> _pick(BuildContext context, WidgetRef ref, {required bool isFrom}) async {
    final lang = ref.read(currentLocaleProvider).languageCode;
    final picked = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CountryPickerSheet(languageCode: lang, strings: strings, anyLabel: strings.t('route_any_country')),
    );
    if (picked == null) return;
    final code = identical(picked, anyCountry) || picked.code == anyCountry.code ? null : picked.code;
    final f = ref.read(routeFilterProvider);
    ref.read(routeFilterProvider.notifier).state =
        isFrom ? RouteFilter(from: code, to: f.to) : RouteFilter(from: f.from, to: code);
  }

  String _label(String? code, String lang, String anyText) {
    if (code == null) return anyText;
    final c = Countries.all.where((x) => x.code == code);
    return c.isEmpty ? code : '${c.first.flag} ${c.first.name(lang)}';
  }

  String _short(String key) {
    final f = RouteFilter.fromKey(key);
    if (f == null) return key;
    String part(String? code) {
      if (code == null) return '🌍';
      final c = Countries.all.where((x) => x.code == code);
      return c.isEmpty ? code : '${c.first.flag} ${c.first.code}';
    }

    return '${part(f.from)} → ${part(f.to)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final filter = ref.watch(routeFilterProvider);
    final saved = ref.watch(savedRoutesProvider);
    final isSaved = saved.contains(filter.key);

    Widget countryButton({required bool isFrom}) {
      final code = isFrom ? filter.from : filter.to;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pick(context, ref, isFrom: isFrom),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.hero,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: code != null ? AppColors.accent : AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(strings.t(isFrom ? 'route_from' : 'route_to'),
                    style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
                Text(
                  _label(code, lang, strings.t('route_any_country')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.search, size: 18, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(strings.t('route_search_title'),
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                  const Spacer(),
                  if (filter.isActive)
                    TextButton(
                      onPressed: () => ref.read(routeFilterProvider.notifier).state = const RouteFilter(),
                      child: Text(strings.t('route_clear')),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  countryButton(isFrom: true),
                  IconButton(
                    tooltip: strings.t('route_swap'),
                    onPressed: () => ref.read(routeFilterProvider.notifier).state =
                        RouteFilter(from: filter.to, to: filter.from),
                    icon: Icon(Icons.swap_horiz, color: AppColors.accent),
                  ),
                  countryButton(isFrom: false),
                ],
              ),
              if (filter.isActive) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      final n = ref.read(savedRoutesProvider.notifier);
                      isSaved ? n.remove(filter.key) : n.add(filter.key);
                    },
                    icon: Icon(isSaved ? Icons.star : Icons.star_border, color: AppColors.accent),
                    label: Text(strings.t(isSaved ? 'route_saved' : 'route_save')),
                  ),
                ),
              ],
              if (saved.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(strings.t('route_my_routes'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final k in saved)
                      InputChip(
                        label: Text(_short(k)),
                        selected: k == filter.key,
                        selectedColor: AppColors.accent.withValues(alpha: 0.2),
                        onPressed: () {
                          final f = RouteFilter.fromKey(k);
                          if (f != null) ref.read(routeFilterProvider.notifier).state = f;
                        },
                        onDeleted: () => ref.read(savedRoutesProvider.notifier).remove(k),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Feed plan: loads, with an ad slot after load [AdFeedLayout.firstAfter],
/// then after every [AdFeedLayout.every] loads — only while more loads
/// follow, so the list never ends on an ad. With [AdFeedLayout.firstAfter]
/// loads or fewer there is one ad slot after the last load, so a live ad is
/// still seen while the marketplace is small. Ad slots are numbered 0, 1, 2…
/// [maxAds] limits the number of ad places (no repeats); null = no limit.
List<({bool isAd, int index})> _feedPlan(int loads, bool adsOn, AdFeedLayout l, {int? maxAds}) {
  final out = <({bool isAd, int index})>[];
  var adSlot = 0;
  for (var i = 0; i < loads; i++) {
    out.add((isAd: false, index: i));
    if (!adsOn) continue;
    final shown = i + 1;
    final atSlot = shown == l.firstAfter || (shown > l.firstAfter && (shown - l.firstAfter) % l.every == 0);
    if (atSlot && shown < loads && (maxAds == null || adSlot < maxAds)) out.add((isAd: true, index: adSlot++));
  }
  if (adsOn && loads > 0 && loads <= l.firstAfter) out.add((isAd: true, index: 0));
  return out;
}

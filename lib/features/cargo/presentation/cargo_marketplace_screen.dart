import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import 'providers/cargo_providers.dart';
import 'widgets/cargo_card.dart';
import 'widgets/cargo_picture.dart';
import 'providers/cargo_media_providers.dart';
import '../../../core/constants/countries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/cargo_model.dart';
import 'widgets/live_map.dart';
import 'widgets/wheel_feed.dart';
import 'providers/route_filter.dart';
import 'providers/category_providers.dart';
import 'widgets/cargo_category_bar.dart';
import 'widgets/route_city_sheet.dart';
import '../../../core/constants/cities.dart';
import '../domain/cargo_categories.dart';
import '../domain/vip_rows.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/layout/desktop_layout.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../repositories/profile_repository.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/providers/group_providers.dart';
import '../../jobs/presentation/job_widgets.dart';

part 'cargo_marketplace_desktop.dart';

/// The "Home" tab body (bottom-nav branch 0) — the real, live cargo
/// marketplace, connected to Supabase via marketplaceProvider. No
/// demo/mock data anywhere in this file.
class CargoMarketplaceScreen extends ConsumerWidget {
  const CargoMarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Wide window: the desktop page (same data and actions, wide layout).
    if (isDesktopLayout(context)) return const _DesktopMarketplace();
    final strings = ref.watch(stringsProvider);
    final marketplaceAsync = ref.watch(marketplaceProvider);
    final cargoList = marketplaceAsync.valueOrNull ?? const <CargoModel>[];
    final filter = ref.watch(routeFilterProvider);
    // The old wide ad banner is gone from the Loads page (owner,
    // 23.10.2026). VIP and normal loads stand in a chessboard instead (0059).
    // Load-type tile / big-small card (0055): the server's answer, or the
    // same rule on the loaded list until it arrives — instant either way.
    final cat = ref.watch(cargoCategoryFilterProvider);
    final catFeed = ref.watch(categoryFeedProvider);
    List<CargoModel> byCategory(List<CargoModel> all) =>
        !cat.isActive ? all : (catFeed.valueOrNull ?? all.where(cat.matches).toList());
    List<CargoModel> visible(List<CargoModel> all) {
      final l = byCategory(all);
      return filter.isActive ? l.where(filter.matches).toList() : l;
    }

    final shown = visible(cargoList);
    final anyFilter = filter.isActive || cat.isActive;
    void resetFilters() {
      ref.read(routeFilterProvider.notifier).state = const RouteFilter();
      ref.read(cargoCategoryFilterProvider.notifier).state = const CargoCategoryFilter();
    }

    return Scaffold(
      // "Add load" moved to the bottom navigation bar.
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketplaceProvider);
          ref.invalidate(activeCarriersCountProvider);
          ref.invalidate(newCargo24hCountProvider);
          ref.invalidate(categoryFeedProvider);
        },
        // Open Loads feed: plain scroll, no card animation (owner,
        // 22.10.2026); only the detent haptic stays.
        child: WheelScope(
          child: CustomScrollView(
          // iOS-style momentum everywhere: long, soft glide and no hard stop.
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _Hero(strings: strings, cargoList: cargoList, loaded: marketplaceAsync.hasValue)),
            // Load types + big / small loads (owner, 21.10.2026).
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                // "Böyük / Kiçik yüklər" removed (owner, 21.10.2026): the choices do it.
                child: CargoTypeTiles(strings: strings, tileHeight: 64, onChanged: _scrollToFeed),
              ),
            ),
            SliverToBoxAdapter(child: _RouteSearch(strings: strings)),
            // QRUPAJ (small loads): the carrier's own road → loads on the way.
            if (cat.groupage)
              SliverToBoxAdapter(child: _EnRouteButton(strings: strings)),
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
                    if (anyFilter)
                      TextButton(
                        key: const ValueKey('cat-reset'),
                        onPressed: resetFilters,
                        child: Text(strings.t('cat_reset')),
                      ),
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
                final list = visible(all);
                if (list.isEmpty && anyFilter) {
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
                              onPressed: resetFilters,
                              child: Text(strings.t('cat_reset')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                }
                if (list.isEmpty) return [SliverToBoxAdapter(child: _EmptyMarketplace(strings: strings))];
                // Two tiles in a row (owner, 22–24.10.2026), chessboard:
                // load–VIP, VIP–load …; the VIP order moves on every few
                // minutes. Scrolling brings the next rows.
                final rows = buildLoadRows(list, columns: 2);
                return [
                  // No panel behind the tiles (owner, 24.10.2026): the page
                  // ground shows between them.
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, kTileGap, 12, 96),
                    sliver: SliverList.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final row = rows[i];
                        return WheelItem(
                          index: i,
                          isAd: false,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: kTileGap),
                            child: _TileRow(
                              children: [
                                for (final cell in row)
                                  CargoTile(
                                    cargo: list[cell.index],
                                    strings: strings,
                                    vip: cell.vip,
                                    onTap: () => context.pushOnce('/cargo/${list[cell.index].id}'),
                                  ),
                              ],
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


/// Dark hero: brand row, live-map title, the animated map and REAL stats
/// computed from the open marketplace (no invented numbers).
class _Hero extends ConsumerWidget {
  final AppStrings strings;
  final List<CargoModel> cargoList;
  final bool loaded;
  const _Hero({required this.strings, required this.cargoList, required this.loaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String stat(int n) => loaded ? '$n' : '—';

    // Title, map and counters stand in one cloud scene (the clouds above /
    // below the map are separate pictures that continue it): the owner's
    // day / night cloud pictures (19.10.2026).
    final day = AppColors.isDay;
    final scene = day ? 'assets/images/world_map_day_v3' : 'assets/images/world_map_night_v4';
    final topPad = MediaQuery.of(context).padding.top + 10;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CloudScene(
            asset: '${scene}_top.jpg',
            alignment: Alignment.bottomCenter,
            child: Padding(
            padding: EdgeInsets.only(top: topPad),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.show_chart, color: AppColors.accentFill, size: 20),
                const SizedBox(width: 4),
                // Full size; only on a very narrow phone (320) it shrinks a
                // little so the İş Mərkəzi button still fits (0069).
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: 'Freight', style: AppFonts.display(size: 18, color: AppColors.text)),
                        TextSpan(text: 'Link', style: AppFonts.display(size: 18, color: AppColors.accent)),
                      ])),
                    ),
                  ),
                ),
                // İş Mərkəzi (owner, 26.10.2026): the approved icon with its
                // name under it, before the two round buttons.
                JobCenterHeaderButton(strings: strings),
                const SizedBox(width: 8),
                // Heart (Seçilmiş yüklər) + profile picture (Profil), two
                // round buttons like on the computer (owner, 22.10.2026).
                HeaderCircles(strings: strings),
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
                  Text(strings.t('home_live_map'),
                      style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2).copyWith(shadows: _readableOnMap())),
                ]),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${strings.t('home_hero_1')} '),
                    TextSpan(text: strings.t('home_hero_2'), style: TextStyle(color: AppColors.accent)),
                    TextSpan(text: ' ${strings.t('home_hero_3')}'),
                  ]),
                  style: AppFonts.display(size: 20, color: AppColors.text, height: 1.1).copyWith(shadows: _readableOnMap()),
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
          _CloudScene(
            asset: '${scene}_bottom.jpg',
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
                const SizedBox(width: 4),
                _StatCard(
                  icon: Icons.groups_2,
                  color: AppColors.blue,
                  value: ref.watch(activeCarriersCountProvider).whenOrNull(data: (n) => '$n') ?? '—',
                  label: strings.t('home_stat_carriers'),
                ),
                const SizedBox(width: 4),
                _StatCard(
                  icon: Icons.bar_chart_rounded,
                  color: AppColors.online,
                  value: ref.watch(newCargo24hCountProvider).whenOrNull(data: (n) => '$n') ?? '—',
                  label: strings.t('home_stat_24h'),
                  onTap: () => _scrollToFeed(),
                ),
                // "Yük hovuzu" (+) — the add-load button (same form:
                // /cargo/create), in line with the counters, right-aligned
                // (owner, 21.10.2026); one line, shrinks on a narrow screen.
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _AddLoadButton(label: strings.t('nav_add_cargo'), onTap: () => context.pushOnce('/cargo/create')),
                  ),
                ),
              ],
            ),
          ),
          // "Populyar marşrutlar" removed (owner, 21.10.2026): the load-type
          // tiles and the big / small cards come under the hero instead.
            ]),
          ),
        ],
      ),
    );
  }
}

/// "Yolüstü yük" entry, shown while "Kiçik yüklər" is chosen.
class _EnRouteButton extends StatelessWidget {
  final AppStrings strings;
  const _EnRouteButton({required this.strings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('enroute-open'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.pushOnce('/cargo/en-route'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
            ),
            child: Row(children: [
              Icon(Icons.alt_route, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(strings.t('enroute_title'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(strings.t('enroute_sub'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ]),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ]),
          ),
        ),
      ),
    );
  }
}

/// [child] drawn on a cloud picture shown at the screen width ([alignment]
/// = the edge that touches the map, so the clouds continue the map's own).
class _CloudScene extends StatelessWidget {
  final String asset;
  final Alignment alignment;
  final Widget child;

  const _CloudScene({required this.asset, required this.alignment, required this.child});

  @override
  Widget build(BuildContext context) {
    // The outer edge (top of the title area, bottom of the counters area)
    // also fades softly into the page colour behind [child], so the clouds
    // never end in a line, whatever the screen width or text size.
    final outerTop = alignment == Alignment.bottomCenter;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(image: AssetImage(asset), fit: BoxFit.fitWidth, alignment: alignment),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: outerTop ? 0 : null,
          bottom: outerTop ? null : 0,
          height: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: outerTop ? Alignment.topCenter : Alignment.bottomCenter,
                end: outerTop ? Alignment.bottomCenter : Alignment.topCenter,
                colors: [AppColors.hero, AppColors.hero.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        child,
      ],
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

/// Shadow in the page colour behind the texts over the map, so they read
/// on any part of it (night and day).
List<Shadow> _readableOnMap() => [
      Shadow(color: AppColors.background.withValues(alpha: 0.95), blurRadius: 10),
      Shadow(color: AppColors.background.withValues(alpha: 0.8), blurRadius: 3),
    ];

/// "Yük hovuzu" on a dark rounded plate with a shadow + big orange round
/// "+" over its right end (under the live map).
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
        // 30 % smaller than before, then 10 % up again (owner, 21.10.2026), so it fits the
        // counters' row; the plate runs under the "+" circle.
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 26, 8),
                decoration: BoxDecoration(
                  color: AppColors.card.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(color: AppColors.line),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                // One line ("Yük hovuzu" side by side); shrinks instead of wrapping.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontSize: 13.2, color: AppColors.text, fontWeight: FontWeight.w400)),
                ),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentFill,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Color(0x66D4420E), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny counter pill (~4 mm tall, ~1 cm wide): coloured icon + number.
/// The label is kept as a tooltip / screen-reader text.
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
            // Half the earlier size (owner, 21.10.2026); the number stays readable.
            height: 18,
            constraints: const BoxConstraints(minWidth: 30),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 10, color: color),
                const SizedBox(width: 3),
                Text(value,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.text, height: 1)),
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
    // Owner, 24.10.2026: inside the country, a city or district (or the
    // whole country). Closing the list keeps the whole country.
    String? city;
    if (code != null && context.mounted) {
      final loads = ref.read(marketplaceProvider).valueOrNull ?? const <CargoModel>[];
      final v = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => RouteCitySheet(
          country: picked,
          cities: routeCitiesOf(code, loads, isFrom: isFrom, lang: lang),
          languageCode: lang,
          strings: strings,
        ),
      );
      city = (v == null || v == kWholeCountry) ? null : v;
    }
    final f = ref.read(routeFilterProvider);
    ref.read(routeFilterProvider.notifier).state = isFrom
        ? RouteFilter(from: code, fromCity: city, to: f.to, toCity: f.toCity)
        : RouteFilter(from: f.from, fromCity: f.fromCity, to: code, toCity: city);
  }

  String _label(String? code, String? city, String lang, String anyText) {
    if (code == null) return anyText;
    final c = Countries.all.where((x) => x.code == code);
    if (c.isEmpty) return code;
    return city == null ? '${c.first.flag} ${c.first.name(lang)}' : '${c.first.flag} ${Cities.label(city, lang)}';
  }

  String _short(String key, String lang) {
    final f = RouteFilter.fromKey(key);
    if (f == null) return key;
    String part(String? code, String? city) {
      if (code == null) return '🌍';
      final c = Countries.all.where((x) => x.code == code);
      if (c.isEmpty) return code;
      return city == null ? '${c.first.flag} ${c.first.code}' : '${c.first.flag} ${Cities.label(city, lang)}';
    }

    return '${part(f.from, f.fromCity)} → ${part(f.to, f.toCity)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final filter = ref.watch(routeFilterProvider);
    final saved = ref.watch(savedRoutesProvider);
    final isSaved = saved.contains(filter.key);

    Widget countryButton({required bool isFrom}) {
      final code = isFrom ? filter.from : filter.to;
      final city = isFrom ? filter.fromCity : filter.toCity;
      return Expanded(
        child: InkWell(
          key: ValueKey(isFrom ? 'route-from' : 'route-to'),
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
                  _label(code, city, lang, strings.t('route_any_country')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: AppColors.text),
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
                      style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
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
                    onPressed: () => ref.read(routeFilterProvider.notifier).state = filter.swapped,
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
                        label: Text(_short(k, lang)),
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



/// Space between all load cards, across and down: 3 mm (owner,
/// 23.10.2026; about 19 points on a phone).
const kTileGap = 19.0;

/// Width of a load card on a phone (owner, 24.10.2026: 15 % bigger than
/// the 147-point picture): 169 points on a 390-point phone; smaller phones
/// shrink it to fit.
const kTileWidth = 169.0;

/// Two tiles side by side with space on both sides (owner's drawing):
/// 2 cm wide each, 3 mm apart; a last single tile keeps its place on the
/// left. Same height per row.
class _TileRow extends StatelessWidget {
  final List<Widget> children;
  const _TileRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = kTileGap;
      final w = ((c.maxWidth - gap) / 2).clamp(0.0, kTileWidth);
      return Center(
        child: SizedBox(
          width: w * 2 + gap,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: w, child: children.isNotEmpty ? children[0] : null),
              const SizedBox(width: gap),
              SizedBox(width: w, child: children.length > 1 ? children[1] : null),
            ]),
          ),
        ),
      );
    });
  }
}

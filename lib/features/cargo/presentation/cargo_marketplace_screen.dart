import '../../favorites/favorites.dart' show openFavorites, FavTab;
import '../../notices/notices.dart' show NoticeBell;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../promo/promo_cross.dart' show PlaceCrossStrip;
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
import '../domain/cargo_feed_first.dart';
import '../domain/cargo_feed_pages.dart';
import 'providers/cargo_feed_pager.dart';
import '../domain/vip_rows.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/layout/desktop_layout.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../repositories/profile_repository.dart';
import '../../jobs/presentation/job_widgets.dart';
import '../../empty_trucks/data/empty_truck_repository.dart';
import '../../empty_trucks/domain/empty_truck.dart';
import '../../empty_trucks/presentation/empty_truck_widgets.dart';
import '../../../core/widgets/tirlink_wordmark.dart';

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
    final filter = ref.watch(routeFilterProvider);
    final cat = ref.watch(cargoCategoryFilterProvider);
    final anyFilter = filter.isActive || cat.isActive;
    // Yüklər | Daşıyıcılar (owner, 13.11.2026): the loads below work exactly
    // as before; Daşıyıcılar shows only the empty truck ads (0118).
    final carriers = ref.watch(loadsSectionProvider) == LoadsSection.carriers;
    final trucks = carriers ? ref.watch(emptyTrucksShownProvider) : const AsyncValue<List<EmptyTruck>>.loading();
    // Page by page from the server (owner, 09.11.2026, SQL 0109, "Turbo.az
    // kimi"): without a filter the page shows the promoted loads + one page
    // at a time and never downloads the whole feed. With a filter on (or
    // before the owner has run 0109) it uses the full feed as before.
    final feed = ref.watch(cargoFeedPagerProvider);
    final usePages = !anyFilter && !feed.legacy;
    final marketplaceAsync = usePages ? const AsyncValue<List<CargoModel>>.loading() : ref.watch(marketplaceProvider);
    final cargoList = marketplaceAsync.valueOrNull ?? const <CargoModel>[];
    // The old wide ad banner is gone from the Loads page (owner,
    // 23.10.2026). VIP and normal loads stand in a chessboard instead (0059).
    // Load-type tile / big-small card (0055): the server's answer, or the
    // same rule on the loaded list until it arrives — instant either way.
    final catFeed = cat.isActive ? ref.watch(categoryFeedProvider) : const AsyncValue<List<CargoModel>>.loading();
    List<CargoModel> byCategory(List<CargoModel> all) =>
        !cat.isActive ? all : (catFeed.valueOrNull ?? all.where(cat.matches).toList());
    List<CargoModel> visible(List<CargoModel> all) {
      final l = byCategory(all);
      return filter.isActive ? l.where(filter.matches).toList() : l;
    }

    final shown = visible(cargoList);
    // Staged loading (owner, 09.11.2026): until the full feed is here, the
    // first rows come from a small first answer — the very same rows, VIP /
    // Premium order included (cargo_feed_first.dart). With a filter on, the
    // page waits for the full feed as before.
    final firstPart = usePages || marketplaceAsync.hasValue || anyFilter ? null : ref.watch(marketplaceFirstProvider).valueOrNull;
    // The admin's load-type pictures: asked for once, with the page.
    ref.listen(allCargoTemplatesProvider, (_, __) {});
    void resetFilters() {
      ref.read(routeFilterProvider.notifier).state = const RouteFilter();
      ref.read(cargoCategoryFilterProvider.notifier).state = const CargoCategoryFilter();
    }

    // The load tiles (and the Premium places card above them) for [list]
    // in [rows]; [more] = the rest of the feed is still on its way.
    List<Widget> tiles(List<CargoModel> list, List<List<LoadCell>> rows, {bool more = false, VoidCallback? onMore}) => [

      // Parks, services and shops whose Premium chose Yüklər (owner, 07.11.2026, 0103).
      // As wide as the two load cards under it (owner, 07.11.2026:
      // never past their left / right edges).
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TileRowWidth(child: PlaceCrossStrip(s: strings, place: 'loads')),
        ),
      ),
      // No panel behind the tiles (owner, 24.10.2026): the page
      // ground shows between them.
      // Room under the last row: never under the floating bar.
      SliverPadding(
        padding: EdgeInsets.fromLTRB(12, kRowGap, 12, more ? 0 : math.max(96, MediaQuery.paddingOf(context).bottom + 16)),
        sliver: SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            // One load per row (owner's picture, 17.11.2026); the rows are
            // as wide as the Premium places card above them.
            return WheelItem(
              index: i,
              isAd: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: kRowGap),
                child: TileRowWidth(
                  child: Column(children: [
                    for (final cell in row)
                      CargoListRow(
                        cargo: list[cell.index],
                        strings: strings,
                        vip: cell.vip,
                        onTap: () => context.pushOnce('/cargo/${list[cell.index].id}'),
                      ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      if (more)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(32, 8, 32, math.max(96, MediaQuery.paddingOf(context).bottom + 16)),
            // Near the end of the list: the next page (page by page, 0109).
            child: _MoreSpinner(onShown: onMore),
          ),
        ),
    ];

    // Page by page (0109): the rows that are already final; the next page
    // comes when the end of the list is near.
    List<Widget> pagedSlivers() {
      if (!feed.ready) {
        return [
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
        ];
      }
      if (feed.error != null && feed.loads.isEmpty) {
        return [
          SliverToBoxAdapter(
            child: _ErrorState(
              message: strings.t('home_error_loading'),
              retryLabel: strings.t('home_retry'),
              onRetry: () => ref.invalidate(cargoFeedPagerProvider),
            ),
          ),
        ];
      }
      if (feed.loads.isEmpty) return [SliverToBoxAdapter(child: _EmptyMarketplace(strings: strings))];
      return tiles(feed.loads, pagedRows(feed.loads, complete: feed.complete, columns: kPhoneLoadColumns),
          more: !feed.complete, onMore: () => ref.read(cargoFeedPagerProvider.notifier).loadMore());
    }

    return Scaffold(
      // "Add load" moved to the bottom navigation bar.
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketplaceProvider);
          ref.invalidate(cargoFeedPagerProvider);
          ref.invalidate(registeredUsersCountProvider);
          ref.invalidate(truckAdsCountProvider);
          ref.invalidate(categoryFeedProvider);
          ref.invalidate(emptyTrucksProvider);
          ref.invalidate(myEmptyTrucksProvider);
        },
        // Open Loads feed: plain scroll, no card animation (owner,
        // 22.10.2026); only the detent haptic stays.
        child: WheelScope(
          child: CustomScrollView(
          // iOS-style momentum everywhere: long, soft glide and no hard stop.
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
                child: _Hero(
                    strings: strings,
                    count: usePages ? (feed.count ?? 0) : cargoList.length,
                    loaded: usePages ? feed.count != null : marketplaceAsync.hasValue)),
            // The load types stand open on the page again (owner, 17.11.2026:
            // "yük növü bölməsini geri qaytar, açıqda dursun").
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: CargoTypeTiles(strings: strings, tileHeight: 64, onChanged: _scrollToFeed),
              ),
            ),
            SliverToBoxAdapter(child: _RouteSearch(strings: strings)),
            // Yüklər | Daşıyıcılar (owner's picture, 13.11.2026).
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: LoadsSectionSwitch(strings: strings, onChanged: _scrollToFeed),
              ),
            ),
            // QRUPAJ (small loads): the carrier's own road → loads on the way.
            if (cat.groupage && !carriers)
              SliverToBoxAdapter(child: _EnRouteButton(strings: strings)),
            SliverToBoxAdapter(
              child: Padding(
                key: _feedHeaderKey,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(strings.t(carriers ? 'et_list_title' : 'home_open_loads'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.display(size: 22, color: AppColors.text)),
                    ),
                    if (anyFilter)
                      TextButton(
                        key: const ValueKey('cat-reset'),
                        onPressed: resetFilters,
                        child: Text(strings.t('cat_reset')),
                      ),
                    if (carriers ? trucks.hasValue : (usePages ? feed.count != null : marketplaceAsync.hasValue))
                      Text(
                          strings.t('home_results', {
                            'count': '${carriers ? trucks.value!.length : (usePages ? feed.count : shown.length)}',
                          }),
                          style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                  ],
                ),
              ),
            ),
            if (carriers)
              ..._carrierSlivers(context, ref, strings, trucks, anyFilter: anyFilter, onReset: resetFilters)
            else if (usePages) ...pagedSlivers() else ...marketplaceAsync.when<List<Widget>>(
              loading: () => [
                if (firstPart != null && firstPart.loads.isNotEmpty) ...[
                  // The first rows at once; the rest of the feed follows.
                  ...tiles(firstPart.loads, stableFirstRows(firstPart, columns: kPhoneLoadColumns), more: !firstPart.complete),
                ] else
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
                // One load per row (owner's picture, 17.11.2026; was two
                // tiles, 22–24.10.2026): load, VIP, load, VIP …; the VIP
                // order moves on every few minutes.
                return tiles(list, buildLoadRows(list, columns: kPhoneLoadColumns));
              },
            ),
          ],
        ),
        ),
      ),
    );
  }
}


/// Daşıyıcılar (owner, 13.11.2026): the empty truck ads, two in a row like
/// the loads; the owner's own ads one tap away; the Loads page's route search
/// and load-type tile filter them.
List<Widget> _carrierSlivers(BuildContext context, WidgetRef ref, AppStrings strings, AsyncValue<List<EmptyTruck>> trucks,
    {required bool anyFilter, required VoidCallback onReset}) {
  final bottom = math.max(96.0, MediaQuery.paddingOf(context).bottom + 16);
  final mine = ref.watch(myEmptyTrucksProvider).valueOrNull ?? const <EmptyTruck>[];
  // Boş maşın əlavə et right above the cards, easy to find (owner,
  // 17.11.2026), with "Mənim elanlarım (n)" beside it when there are any.
  // The orange + under the map keeps its place too.
  final mineRow = SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(children: [
        Expanded(
          child: _OutlinedAddButton(
            key: const ValueKey('empty-truck-add-top'),
            label: strings.t('et_add_button'),
            onTap: () => context.pushOnce('/trucks/new'),
          ),
        ),
        if (mine.isNotEmpty) ...[
          const SizedBox(width: 8),
          Flexible(
            child: TextButton.icon(
              key: const ValueKey('empty-truck-mine'),
              onPressed: () => context.pushOnce('/trucks/mine'),
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: Text(strings.t('et_mine_count', {'n': '${mine.length}'}), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ]),
    ),
  );
  return trucks.when<List<Widget>>(
    loading: () => [
      mineRow,
      const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))),
    ],
    error: (e, _) => [
      mineRow,
      SliverToBoxAdapter(
        child: e is EmptyTruckNotReady
            ? Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, bottom),
                child: Text(strings.t('et_not_ready'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
              )
            : _ErrorState(
                message: strings.t('home_error_loading'),
                retryLabel: strings.t('home_retry'),
                onRetry: () => ref.invalidate(emptyTrucksProvider),
              ),
      ),
    ],
    data: (list) {
      if (list.isEmpty) {
        return [
          mineRow,
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, bottom),
              child: Column(children: [
                Icon(anyFilter ? Icons.search_off : Icons.local_shipping_outlined, size: 40, color: AppColors.textSoft),
                const SizedBox(height: 10),
                Text(strings.t(anyFilter ? 'route_no_results' : 'et_empty'), textAlign: TextAlign.center),
                if (anyFilter) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: onReset, child: Text(strings.t('cat_reset'))),
                ],
              ]),
            ),
          ),
        ];
      }
      return [
        mineRow,
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, bottom),
          // The carrier cards of the owner's picture 1 (17.11.2026).
          sliver: SliverList.builder(
            itemCount: list.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: EmptyTruckCarrierCard(
                  truck: list[i], strings: strings, onTap: () => context.pushOnce('/trucks/${list[i].id}')),
            ),
          ),
        ),
      ];
    },
  );
}

/// Dark hero: brand row, live-map title, the animated map and REAL stats
/// computed from the open marketplace (no invented numbers).
class _Hero extends ConsumerWidget {
  final AppStrings strings;
  // Open loads (the counter; page by page it comes from the server, 0109).
  final int count;
  final bool loaded;
  const _Hero({required this.strings, required this.count, required this.loaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String stat(int n) => loaded ? statCount(n) : '—';
    // The slogan, also measured: the counters never run past its right end
    // (owner's picture, 23.11.2026: "Yüklər dünya üzrə hərəkətdədir yazısını
    // keçməməlidir").
    final sloganStyle = TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.2).copyWith(shadows: _readableOnMap());
    final slogan = TextSpan(children: [
      TextSpan(text: '${strings.t('home_hero_1')} '),
      TextSpan(text: strings.t('home_hero_2'), style: TextStyle(color: AppColors.accent)),
      TextSpan(text: ' ${strings.t('home_hero_3')}'),
    ]);
    final sloganWidth = statRowMaxWidth(context, slogan, sloganStyle);
    final vLoads = stat(count);
    final vUsers = ref.watch(registeredUsersCountProvider).whenOrNull(data: statCount) ?? '—';
    final vCarriers = ref.watch(truckAdsCountProvider).whenOrNull(data: statCount) ?? '—';
    // One scale for the counters AND "CANLI", so all four keep one size.
    final rowWidth = [vLoads, vUsers, vCarriers].fold<double>(10, (w, v) => w + StatCapsule.widthOf(context, v));
    final statScale = rowWidth > sloganWidth ? sloganWidth / rowWidth : 1.0;

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
                // Logo with the slogan under it in one small line (owner,
                // 27.10.2026 — the big headline over the map is gone).
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    // The TIR Link logo left of TırLink (owner, 14.11.2026; it
                    // replaced the orange chart icon), www.tirlink.app under it.
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: TirLinkWordmark(size: 18, showLogo: true),
                    ),
                    const SizedBox(height: 2),
                    Text.rich(
                      key: const ValueKey('home-slogan'),
                      slogan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sloganStyle,
                    ),
                  ]),
                ),
                HeaderCircles(strings: strings),
              ],
            ),
          ),
          // The counters and "CANLI" on one line right under the slogan,
          // above the map (owner's picture, 23.11.2026: "sol tərəfə … yazının
          // həmən altında, Canlı sağ tərəfdə eyni hizada"). Three live
          // counters (real numbers from the database): aktiv yük · qeydiyyatlı
          // istifadəçi · Daşıyıcılar bölməsindəki daşıyıcı (22.11.2026); never
          // cut, a long number only shrinks the row on a very narrow phone.
          const SizedBox(height: kStatRowTop),
          Padding(
            key: const ValueKey('stat-row'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                    key: const ValueKey('stat-row-limit'),
                    width: rowWidth * statScale,
                    height: StatCapsule.height * statScale,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        StatCapsule(
                          key: const ValueKey('stat-loads'),
                          icon: Icons.local_shipping,
                          color: AppColors.accent,
                          value: vLoads,
                          label: strings.t('home_stat_active'),
                          onTap: () => _scrollToFeed(),
                        ),
                        const SizedBox(width: 5),
                        StatCapsule(
                          key: const ValueKey('stat-users'),
                          icon: Icons.groups_2_outlined,
                          color: AppColors.blue,
                          value: vUsers,
                          label: strings.t('home_stat_users'),
                        ),
                        const SizedBox(width: 5),
                        StatCapsule(
                          key: const ValueKey('stat-carriers'),
                          icon: Icons.local_shipping_outlined,
                          color: AppColors.online,
                          value: vCarriers,
                          label: strings.t('et_section_carriers'),
                          onTap: () {
                            ref.read(loadsSectionProvider.notifier).state = LoadsSection.carriers;
                            _scrollToFeed();
                          },
                        ),
                      ]),
                    ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: StatCapsule.minWidth * statScale,
                  height: StatCapsule.height * statScale,
                  child: FittedBox(
                    child: LiveCapsule(label: strings.t('map_live_badge'), height: StatCapsule.height, width: StatCapsule.minWidth),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
            ]),
            ),
          ),
          // Full width, edge to edge; edges fade into the page colour.
          // Only the city lights blink (owner, 17.11.2026: "animasiyanı azalt,
          // sadəcə şəhərlərdə işıqlar yanıb sönsün, hərəkət edən marşrutları sil").
          LiveMap(liveLabel: strings.t('map_live_badge'), routes: false, showBadge: false),
          _CloudScene(
            asset: '${scene}_bottom.jpg',
            alignment: Alignment.topCenter,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          const SizedBox(height: 14),
          // İş Mərkəzi where the counters were (owner, 28.10.2026) and
          // "Yük hovuzu" (+), the add-load button (/cargo/create),
          // right-aligned (owner, 21.10.2026).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                JobCenterMapButton(strings: strings),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    // Same place; the name and the form follow Yüklər |
                    // Daşıyıcılar (owner, 13.11.2026).
                    child: ref.watch(loadsSectionProvider) == LoadsSection.carriers
                        ? _AddLoadButton(
                            key: const ValueKey('add-empty-truck'),
                            label: strings.t('et_add_button'),
                            onTap: () => context.pushOnce('/trucks/new'))
                        : // "Yük əlavə et" (owner, 17.11.2026: was "Yük hovuzu"; the second
                        // button over the list is gone).
                        _AddLoadButton(label: strings.t('home_add_load'), onTap: () => context.pushOnce('/cargo/create')),
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

/// "Yük hovuzu" on a dark rounded plate with a shadow + big orange round
/// "+" over its right end (under the live map).
class _AddLoadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddLoadButton({super.key, required this.label, required this.onTap});

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
/// One of the map's live counters (owner's picture, 22.11.2026): a dark
/// capsule with a thick border in its colour, the icon in a tinted circle on
/// the left and the number in white on the right. Its size on the picture is
/// the least it takes (a short number keeps it); a longer number widens it.
/// The name shows on a long press / hover (Tooltip) and to screen readers.
/// The gap between the slogan and the counters' line (the capsules and
/// "CANLI" share it, above the map; owner 23.11.2026).
const double kStatRowTop = 5;

/// How wide the counters may be: the slogan's own width (as drawn, with the
/// page's font and text size), so they never run past its right end.
double statRowMaxWidth(BuildContext context, InlineSpan slogan, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(style: DefaultTextStyle.of(context).style.merge(style), children: [slogan]),
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

class StatCapsule extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const StatCapsule({super.key, required this.icon, required this.color, required this.value, required this.label, this.onTap});

  static const double height = 22;
  static const double minWidth = 66;
  static const _valueStyle =
      TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1, fontFeatures: [FontFeature.tabularFigures()]);

  /// The capsule's width for [value] as drawn (paddings 3 + 9, border 2 ×
  /// 1.6, icon 16, gap 5, the number), never under [minWidth].
  static double widthOf(BuildContext context, String value) {
    final tp = TextPainter(
      text: TextSpan(text: value, style: DefaultTextStyle.of(context).style.merge(_valueStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return math.max(minWidth, 3 + 9 + 3.2 + 16 + 5 + w);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: '$label: $value',
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onTap,
          child: Container(
            height: height,
            constraints: const BoxConstraints(minWidth: minWidth),
            padding: const EdgeInsets.fromLTRB(3, 0, 9, 0),
            decoration: BoxDecoration(
              color: AppColors.card.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: color, width: 1.6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.24), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 10, color: color),
                ),
                const SizedBox(width: 5),
                // The number stands in the middle of what is left.
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: minWidth - 3 - 9 - 16 - 5 - 3.2),
                  child: Text(value,
                    textAlign: TextAlign.center,
                    style: _valueStyle.copyWith(color: AppColors.text)),
                ),
              ],
            ),
          ),
        ),
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
      // The towns of the loads in that country (page by page the screen
      // does not hold every load: read them now, once).
      var loads = ref.read(marketplaceProvider).valueOrNull ?? const <CargoModel>[];
      if (loads.isEmpty) {
        try {
          loads = await ref.read(marketplaceProvider.future);
        } catch (_) {}
      }
      if (!context.mounted) return;
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

/// The phone's Loads page: one load per row (owner's picture, 17.11.2026).
const kPhoneLoadColumns = 1;

/// Space between two rows of the phone's Loads / Daşıyıcılar list.
const kRowGap = 10.0;

/// Width of a load card on a phone (owner, 24.10.2026: 15 % bigger than
/// the 147-point picture): 169 points on a 390-point phone; smaller phones
/// shrink it to fit.
const kTileWidth = 169.0;

/// The width of a row of two load cards ([_TileRow]), centred the same
/// way: what stands above the cards (the ad card) never goes past their
/// edges (owner, 07.11.2026).
double tileRowWidth(double maxWidth) => ((maxWidth - kTileGap) / 2).clamp(0.0, kTileWidth) * 2 + kTileGap;

class TileRowWidth extends StatelessWidget {
  final Widget child;
  const TileRowWidth({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Center(child: SizedBox(width: tileRowWidth(c.maxWidth), child: child)),
      );
}

/// "+ Yük əlavə et" / "+ Boş maşın əlavə et" over the list: an accent
/// outline, full width (owner's design, 17.11.2026).
class _OutlinedAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlinedAddButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          foregroundColor: AppColors.accent,
          side: BorderSide(color: AppColors.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.add, size: 22),
        label: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      );
}

/// The spinner at the end of the list; when it comes into view (near the
/// end) it asks for the next page (page by page, 0109).
class _MoreSpinner extends StatelessWidget {
  final VoidCallback? onShown;
  const _MoreSpinner({this.onShown});

  @override
  Widget build(BuildContext context) {
    if (onShown != null) WidgetsBinding.instance.addPostFrameCallback((_) => onShown!());
    return const Center(child: CircularProgressIndicator());
  }
}

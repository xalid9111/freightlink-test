part of 'cargo_marketplace_screen.dart';

// Desktop "Yüklər" page (owner's desktop design, 19.10.2026): a wide hero
// with the live map in clouds, top search / bell / account, the counters
// and "Yük əlavə et"; then the load types + big / small loads, the route
// search and the open loads as a grid. Same data, providers and actions as the mobile page —
// only the layout is different. Shown from kDesktopMinWidth on.

/// Text typed in the desktop top search: filters the open loads below.
final _deskQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// A load matches the top search when every word is found in its cities,
/// countries (names and codes) or cargo / truck type.
bool deskLoadMatches(CargoModel c, String query, String lang) {
  final words = query.trim().toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final hay = [
    c.pickupCity,
    c.destinationCity,
    c.pickupCountry,
    c.destinationCountry,
    Countries.label(c.pickupCountry, lang),
    Countries.label(c.destinationCountry, lang),
    Countries.find(c.pickupCountry)?.code ?? '',
    Countries.find(c.destinationCountry)?.code ?? '',
    c.cargoType ?? '',
    c.truckType ?? '',
  ].join(' ').toLowerCase();
  return words.every(hay.contains);
}

/// Width the desktop page content never grows beyond (very wide screens).
const double _kDeskMaxContent = 1640;
const double _kDeskPad = 40;

/// Centres [child] at the desktop content width with the page side padding.
class _DeskBody extends StatelessWidget {
  final Widget child;
  const _DeskBody({required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kDeskMaxContent + 2 * _kDeskPad),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: _kDeskPad), child: child),
        ),
      );
}

class _DesktopMarketplace extends ConsumerWidget {
  const _DesktopMarketplace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final marketplaceAsync = ref.watch(marketplaceProvider);
    final cargoList = marketplaceAsync.valueOrNull ?? const <CargoModel>[];
    final filter = ref.watch(routeFilterProvider);
    final query = ref.watch(_deskQueryProvider);
    // No wide ad banner any more; VIP rows instead, as on the phone (0059).
    // Load-type tile / big-small card (0055), as on the phone.
    final cat = ref.watch(cargoCategoryFilterProvider);
    final catFeed = ref.watch(categoryFeedProvider);
    List<CargoModel> visible(List<CargoModel> all) {
      final base = !cat.isActive ? all : (catFeed.valueOrNull ?? all.where(cat.matches).toList());
      return base.where((c) => (!filter.isActive || filter.matches(c)) && deskLoadMatches(c, query, lang)).toList();
    }

    final shown = visible(cargoList);
    final searching = filter.isActive || query.trim().isNotEmpty || cat.isActive;
    // Yüklər | Daşıyıcılar (owner, 13.11.2026), the same as on the phone.
    final carriers = ref.watch(loadsSectionProvider) == LoadsSection.carriers;
    final trucks = carriers ? ref.watch(emptyTrucksShownProvider) : const AsyncValue<List<EmptyTruck>>.loading();
    void resetFilters() {
      ref.read(routeFilterProvider.notifier).state = const RouteFilter();
      ref.read(_deskQueryProvider.notifier).state = '';
      ref.read(cargoCategoryFilterProvider.notifier).state = const CargoCategoryFilter();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketplaceProvider);
          ref.invalidate(registeredUsersCountProvider);
          ref.invalidate(truckAdsCountProvider);
          ref.invalidate(categoryFeedProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: AppColors.neumorph
                    ? _DeskNeuHero(strings: strings, cargoList: cargoList, loaded: marketplaceAsync.hasValue)
                    : _DeskHero(strings: strings, cargoList: cargoList, loaded: marketplaceAsync.hasValue)),
            // "Populyar marşrutlar" → the load-type choices (owner, 21.10.2026).
            SliverToBoxAdapter(
              child: _DeskBody(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  // Neumorf: the phone's raised squares with the types' own pictures.
                  child: CargoTypeTiles(strings: strings, tileHeight: AppColors.neumorph ? 92 : 64),
                ),
              ),
            ),
            if (cat.groupage && !carriers)
              SliverToBoxAdapter(child: _DeskBody(child: _EnRouteButton(strings: strings))),
            SliverToBoxAdapter(child: _DeskBody(child: _DeskRouteSearch(strings: strings))),
            SliverToBoxAdapter(
              child: _DeskBody(
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: LoadsSectionSwitch(strings: strings),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _DeskBody(
                child: Padding(
                  key: _feedHeaderKey,
                  padding: const EdgeInsets.fromLTRB(2, 26, 2, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                          child: Text(strings.t(carriers ? 'et_list_title' : 'home_open_loads'),
                              style: AppFonts.display(size: 24, color: AppColors.text))),
                      if (searching)
                        TextButton(
                          key: const ValueKey('cat-reset'),
                          onPressed: resetFilters,
                          child: Text(strings.t('cat_reset')),
                        ),
                      if (carriers ? trucks.hasValue : marketplaceAsync.hasValue)
                        Text(strings.t('home_results', {'count': '${carriers ? trucks.value!.length : shown.length}'}),
                            style: TextStyle(fontSize: 16, color: AppColors.textSoft)),
                    ],
                  ),
                ),
              ),
            ),
            if (carriers)
              ..._deskCarrierSlivers(context, ref, strings, trucks, anyFilter: searching, onReset: resetFilters)
            else ...marketplaceAsync.when<List<Widget>>(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
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
                if (list.isEmpty && searching) {
                  return [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
                        child: Column(
                          children: [
                            Icon(Icons.search_off, size: 44, color: AppColors.textSoft),
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
                return [
                  SliverToBoxAdapter(
                    child: _DeskBody(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 48),
                        child: LayoutBuilder(
                          // Same picture tiles as the phone (owner, 22.10.2026),
                          // as many as fit at about 200 px each.
                          builder: (context, c) {
                            // Neumorf (owner approved 27.11.2026): the phone's load
                            // rows as raised cards, three (two to four) in a row.
                            if (AppColors.neumorph) {
                              final n = (c.maxWidth / 420).floor().clamp(2, 4);
                              return Padding(
                                key: const ValueKey('desk-neu-rows'),
                                padding: const EdgeInsets.only(top: 6),
                                child: _DeskLoadGrid(
                                  columns: n,
                                  gap: 22,
                                  rows: buildLoadRows(list, columns: n),
                                  buildLoad: (i, vip) => CargoListRow(
                                    cargo: list[i],
                                    strings: strings,
                                    vip: vip,
                                    onTap: () => context.pushOnce('/cargo/${list[i].id}'),
                                  ),
                                ),
                              );
                            }
                            final columns = ((c.maxWidth - 2 * kTileGap + kTileGap) / (200 + kTileGap)).floor().clamp(3, 8);
                            // No panel behind the tiles (owner, 24.10.2026).
                            return Padding(
                                padding: const EdgeInsets.fromLTRB(kTileGap, kTileGap, kTileGap, 0),
                                child: _DeskLoadGrid(
                              columns: columns,
                              rows: buildLoadRows(list, columns: columns),
                              buildLoad: (i, vip) {
                                final cargo = list[i];
                                return CargoTile(
                                  cargo: cargo,
                                  strings: strings,
                                  vip: vip,
                                  onTap: () => context.pushOnce('/cargo/${cargo.id}'),
                                );
                              },
                                ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Daşıyıcılar on the computer: the same empty truck cards in rows of as
/// many as fit (the phone's list logic, _carrierSlivers, for the states).
List<Widget> _deskCarrierSlivers(BuildContext context, WidgetRef ref, AppStrings strings, AsyncValue<List<EmptyTruck>> trucks,
    {required bool anyFilter, required VoidCallback onReset}) {
  final list = trucks.valueOrNull;
  if (list == null || list.isEmpty) {
    return [for (final w in _carrierSlivers(context, ref, strings, trucks, anyFilter: anyFilter, onReset: onReset)) w];
  }
  final mine = ref.watch(myEmptyTrucksProvider).valueOrNull ?? const <EmptyTruck>[];
  return [
    SliverToBoxAdapter(
      child: _DeskBody(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (mine.isNotEmpty)
              TextButton.icon(
                key: const ValueKey('empty-truck-mine'),
                onPressed: () => context.pushOnce('/trucks/mine'),
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(strings.t('et_mine_count', {'n': '${mine.length}'})),
              ),
            LayoutBuilder(builder: (context, c) {
              final columns = ((c.maxWidth - 2 * kTileGap + kTileGap) / (200 + kTileGap)).floor().clamp(3, 8);
              final rows = <List<LoadCell>>[
                for (var i = 0; i < list.length; i += columns)
                  [for (var k = i; k < i + columns && k < list.length; k++) (index: k, vip: false)],
              ];
              return Padding(
                padding: const EdgeInsets.fromLTRB(kTileGap, kTileGap, kTileGap, 0),
                child: _DeskLoadGrid(
                  columns: columns,
                  rows: rows,
                  buildLoad: (i, _) => EmptyTruckTile(
                      truck: list[i], strings: strings, onTap: () => context.pushOnce('/trucks/${list[i].id}')),
                ),
              );
            }),
          ]),
        ),
      ),
    ),
  ];
}

/// Open loads in rows of [columns] equal cards (same height per row), 3 mm
/// apart; VIP cards (0059) join the same flow, same size.
class _DeskLoadGrid extends StatelessWidget {
  final int columns;
  final List<List<LoadCell>> rows;
  final Widget Function(int index, bool vip) buildLoad;
  final double gap;
  const _DeskLoadGrid({required this.columns, required this.rows, required this.buildLoad, this.gap = kTileGap});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in rows)
        Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var k = 0; k < columns; k++) ...[
                if (k > 0) SizedBox(width: gap),
                Expanded(child: k < r.length ? buildLoad(r[k].index, r[k].vip) : const SizedBox.shrink()),
              ],
            ]),
          ),
        ),
    ]);
  }
}

/// Wide hero: the live map in the cloud scene, title, top search / bell /
/// account, the three live counters and "Yük əlavə et".
class _DeskHero extends ConsumerWidget {
  final AppStrings strings;
  final List<CargoModel> cargoList;
  final bool loaded;
  const _DeskHero({required this.strings, required this.cargoList, required this.loaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = AppColors.isDay;
    final clouds = day ? 'assets/images/world_map_day_v3_bottom.jpg' : 'assets/images/world_map_night_v4_bottom.jpg';
    String stat(int n) => loaded ? statCount(n) : '—';
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = (w * 0.27).clamp(390.0, 470.0);
        final mapW = math.min(w * 0.64, (h - 40) * 2.96).floorToDouble();
        // Whole-pixel box around the map: the fade layer then has no
        // half-pixel edge (which showed as a thin line on the web).
        final mapBoxH = (mapW / 2.96).ceilToDouble() + 2;
        return SizedBox(
          height: h,
          child: Stack(
            children: [
              // Cloud ground of the whole hero (the same clouds as the map's).
              Positioned.fill(child: Image.asset(clouds, fit: BoxFit.cover, alignment: Alignment.topCenter, gaplessPlayback: true)),
              // The live map, its edges melting into the clouds.
              Positioned(
                left: (w - mapW).floorToDouble(),
                top: 36,
                width: mapW,
                height: mapBoxH,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    // Fully clear for the first 2 %, so the map's own edge never shows as a line.
                    colors: [Color(0x00000000), Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                    stops: [0, 0.02, 0.16, 0.9, 1],
                  ).createShader(r),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
                      stops: [0, 0.02, 0.14, 0.82, 1],
                    ).createShader(r),
                    child: Align(alignment: Alignment.topCenter, child: LiveMap(liveLabel: strings.t('map_live_badge'))),
                  ),
                ),
              ),
              // Soft fade into the page below (no line where the hero ends).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.background, AppColors.background.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _kDeskPad,
                top: 96,
                // Only the free space left of the map (owner: the title never
                // runs onto the map).
                width: math.max(300, w - mapW - _kDeskPad - 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(strings.t('home_live_map'),
                          style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2, size: 15).copyWith(shadows: _readableOnMap())),
                    ]),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${strings.t('home_hero_1')} '),
                        TextSpan(text: strings.t('home_hero_2'), style: TextStyle(color: AppColors.accent)),
                        // Second line (owner, 19.10.2026): "Yüklər dünya üzrə / hərəkətdədir".
                        TextSpan(text: '\n${strings.t('home_hero_3')}'),
                      ]),
                      style: AppFonts.display(size: (w * 0.026).clamp(30.0, 42.0), color: AppColors.text, height: 1.15)
                          .copyWith(shadows: _readableOnMap()),
                    ),
                  ],
                ),
              ),
              Positioned(top: 20, right: 28, left: w * 0.42, child: _DeskTopBar(strings: strings, hint: 'desk_search_loads_hint')),
              Positioned(
                left: _kDeskPad,
                bottom: 40,
                child: Row(
                  children: [
                    _DeskStat(
                      icon: Icons.local_shipping,
                      color: AppColors.accent,
                      value: stat(cargoList.length),
                      label: strings.t('home_stat_active'),
                      onTap: _scrollToFeed,
                    ),
                    const SizedBox(width: 14),
                    // The same three as the phone (owner, 22.11.2026).
                    _DeskStat(
                      icon: Icons.groups_2,
                      color: AppColors.blue,
                      value: ref.watch(registeredUsersCountProvider).whenOrNull(data: statCount) ?? '—',
                      label: strings.t('home_stat_users'),
                    ),
                    const SizedBox(width: 14),
                    _DeskStat(
                      icon: Icons.local_shipping_outlined,
                      color: AppColors.online,
                      value: ref.watch(truckAdsCountProvider).whenOrNull(data: statCount) ?? '—',
                      label: strings.t('et_section_carriers'),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 28,
                bottom: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [BoxShadow(color: AppColors.accentFill.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 6))],
                  ),
                  child: FilledButton.icon(
                    key: const ValueKey('desk-add-load'),
                    onPressed: () => context.pushOnce(ref.watch(loadsSectionProvider) == LoadsSection.carriers ? '/trucks/new' : '/cargo/create'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentFill,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    icon: const Icon(Icons.add, size: 26),
                    label: Text(strings.t(ref.watch(loadsSectionProvider) == LoadsSection.carriers ? 'et_add_button' : 'nav_add_cargo')),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Neumorf top of the computer's Yüklər page (owner's picture, approved
/// 27.11.2026): the title, a pressed-in search, the round bell · heart ·
/// profile picture; the counters + CANLI as raised capsules with İş
/// Mərkəzi on the right; the live map in a pressed-in frame with "Yük
/// əlavə et +" on its lower right edge. Same numbers, keys and taps.
class _DeskNeuHero extends ConsumerWidget {
  final AppStrings strings;
  final List<CargoModel> cargoList;
  final bool loaded;
  const _DeskNeuHero({required this.strings, required this.cargoList, required this.loaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String stat(int n) => loaded ? statCount(n) : '—';
    final carriers = ref.watch(loadsSectionProvider) == LoadsSection.carriers;
    return _DeskBody(
      child: Padding(
        key: const ValueKey('desk-neu-hero'),
        padding: const EdgeInsets.only(top: 26),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${strings.t('home_hero_1')} '),
                  TextSpan(text: strings.t('home_hero_2'), style: TextStyle(color: AppColors.accent)),
                  TextSpan(text: ' ${strings.t('home_hero_3')}'),
                ]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.2),
              ),
            ),
            const SizedBox(width: 24),
            Flexible(child: _DeskTopBar(strings: strings, hint: 'desk_search_loads_hint')),
          ]),
          const SizedBox(height: 22),
          Row(children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _NeuStat(
                        key: const ValueKey('stat-loads'),
                        dot: AppColors.accent,
                        value: stat(cargoList.length),
                        unit: strings.t('neu_unit_loads'),
                        label: strings.t('home_stat_active'),
                        onTap: _scrollToFeed),
                    const SizedBox(width: 14),
                    _NeuStat(
                        key: const ValueKey('stat-users'),
                        dot: AppColors.blue,
                        value: ref.watch(registeredUsersCountProvider).whenOrNull(data: statCount) ?? '—',
                        unit: strings.t('neu_unit_users'),
                        label: strings.t('home_stat_users')),
                    const SizedBox(width: 14),
                    _NeuStat(
                      key: const ValueKey('stat-carriers'),
                      dot: AppColors.online,
                      value: ref.watch(truckAdsCountProvider).whenOrNull(data: statCount) ?? '—',
                      unit: strings.t('neu_unit_carriers'),
                      label: strings.t('et_section_carriers'),
                      onTap: () {
                        ref.read(loadsSectionProvider.notifier).state = LoadsSection.carriers;
                        _scrollToFeed();
                      },
                    ),
                    const SizedBox(width: 14),
                    _NeuStat(dot: AppColors.online, value: strings.t('map_live_badge'), label: strings.t('map_live_badge'), live: true),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // İş Mərkəzi as a raised card on the counters' line.
            Tooltip(
              message: strings.t('job_center'),
              child: Container(
                decoration: neuRaisedDecoration(radius: 22, depth: 0.8),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const ValueKey('desk-job-center'),
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => context.pushOnce('/jobs'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const JobCenterIcon(height: 30),
                        const SizedBox(width: 10),
                        Text(strings.t('job_center'), style: TextStyle(color: AppColors.text, fontSize: 15)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          LayoutBuilder(builder: (context, c) {
            final h = (c.maxWidth * 0.26).clamp(240.0, 360.0);
            return Stack(clipBehavior: Clip.none, children: [
              Container(
                key: const ValueKey('desk-neu-map'),
                padding: const EdgeInsets.all(10),
                decoration: neuInsetDecoration(radius: 28),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: h,
                    width: double.infinity,
                    // The whole map's width, its middle shown (cover).
                    child: FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(width: c.maxWidth, child: LiveMap(liveLabel: strings.t('map_live_badge'), showBadge: false)),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -2,
                child: _AddLoadButton(
                  key: const ValueKey('desk-add-load'),
                  label: strings.t(carriers ? 'et_add_button' : 'home_add_load'),
                  onTap: () => context.pushOnce(carriers ? '/trucks/new' : '/cargo/create'),
                ),
              ),
            ]);
          }),
        ]),
      ),
    );
  }
}

/// Big counter pill of the desktop hero (tinted, icon + number).
class _DeskStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;
  const _DeskStat({required this.icon, required this.color, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        label: '$label: $value',
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 100, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: AppColors.isDay ? 0.10 : 0.14), AppColors.background.withValues(alpha: 0.85)),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 10),
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top bar of a desktop page: search field (filters this page), the bell
/// (Bildirişlər) and the account chip (→ Profil).
class _DeskTopBar extends ConsumerStatefulWidget {
  final AppStrings strings;
  final String hint;
  const _DeskTopBar({required this.strings, required this.hint});

  @override
  ConsumerState<_DeskTopBar> createState() => _DeskTopBarState();
}

class _DeskTopBarState extends ConsumerState<_DeskTopBar> {
  // Made in initState (not lazily) so dispose() never reads ref.
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(_deskQueryProvider));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    // Cleared elsewhere (e.g. "Təmizlə" under no results) → empty field too.
    ref.listen<String>(_deskQueryProvider, (_, next) {
      if (next != _text.text) _text.text = next;
    });
    final glass = AppColors.isDay ? Colors.white.withValues(alpha: 0.92) : AppColors.card.withValues(alpha: 0.82);
    final favCount = ref.watch(cargoFavoriteIdsProvider).length;
    final uid = ref.watch(currentUserIdProvider);
    final me = ref.watch(currentUserProvider);
    final profile = uid == null ? null : ref.watch(publicProfileProvider(uid)).valueOrNull;
    final name = (profile?.fullName ?? me?.fullName ?? '').trim();
    final first = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final initials = name.isEmpty
        ? '?'
        : name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p.characters.first.toUpperCase()).join();
    BoxDecoration pill() => BoxDecoration(
          color: glass,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.line),
        );
    if (AppColors.neumorph) {
      // Neumorf (owner approved 27.11.2026): a pressed-in search, the bell,
      // the heart and the profile picture as round raised buttons
      // (HeaderCircles, as on the phone); İş Mərkəzi on the counters' line.
      return Row(
        key: const ValueKey('desk-topbar-neu'),
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                decoration: neuInsetDecoration(radius: 26),
                child: TextField(
                  key: const ValueKey('desk-search'),
                  controller: _text,
                  onChanged: (v) => ref.read(_deskQueryProvider.notifier).state = v,
                  onSubmitted: (_) => _scrollToFeed(),
                  style: TextStyle(fontSize: 15, color: AppColors.text),
                  decoration: InputDecoration(
                    filled: false,
                    isDense: true,
                    hintText: s.t(widget.hint),
                    hintStyle: TextStyle(color: AppColors.textSoft, fontSize: 15),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSoft, size: 24),
                    suffixIcon: _text.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: s.t('route_clear'),
                            icon: Icon(Icons.close, color: AppColors.textSoft),
                            onPressed: () {
                              _text.clear();
                              ref.read(_deskQueryProvider.notifier).state = '';
                            },
                          ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          HeaderCircles(strings: s),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              decoration: pill(),
              child: TextField(
                key: const ValueKey('desk-search'),
                controller: _text,
                onChanged: (v) => ref.read(_deskQueryProvider.notifier).state = v,
                onSubmitted: (_) => _scrollToFeed(),
                style: TextStyle(fontSize: 15.5, color: AppColors.text),
                decoration: InputDecoration(
                  filled: false,
                  isDense: true,
                  hintText: s.t(widget.hint),
                  hintStyle: TextStyle(color: AppColors.textSoft, fontSize: 15.5),
                  prefixIcon: Icon(Icons.search, color: AppColors.textSoft, size: 26),
                  suffixIcon: _text.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: s.t('route_clear'),
                          icon: Icon(Icons.close, color: AppColors.textSoft),
                          onPressed: () {
                            _text.clear();
                            ref.read(_deskQueryProvider.notifier).state = '';
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // İş Mərkəzi (owner, 26.10.2026): the approved icon in a pill.
        Tooltip(
          message: s.t('job_center'),
          child: InkWell(
            key: const ValueKey('desk-job-center'),
            borderRadius: BorderRadius.circular(28),
            onTap: () => context.pushOnce('/jobs'),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: pill(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const JobCenterIcon(height: 28),
                const SizedBox(width: 8),
                Text(s.t('job_center'), style: TextStyle(color: AppColors.text, fontSize: 14.5)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // "Bildirişlər" (owner, 17.11.2026): left of the heart; every notice
        // except chat messages (Mesajlar keeps its count in the sidebar).
        NoticeBell(
          strings: s,
          size: 26,
          frame: (icon, onTap, tip) => Tooltip(
            message: tip,
            child: InkWell(
              key: const ValueKey('desk-bell'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Container(width: 54, height: 54, decoration: pill(), alignment: Alignment.center, child: icon),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // "Seçilmiş yüklər" (owner, 22.10.2026): the heart right of the bell.
        HeaderCircle(
          key: const ValueKey('desk-favorites'),
          tooltip: s.t('fav_cargo_title'),
          size: 54,
          onTap: () => openFavorites(context, FavTab.loads),
          child: Badge(
            isLabelVisible: favCount > 0,
            label: Text(favCount > 99 ? '99+' : '$favCount'),
            backgroundColor: AppColors.accentFill,
            child: Icon(favCount > 0 ? Icons.favorite : Icons.favorite_border, color: AppColors.accent, size: 26),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          key: const ValueKey('desk-account'),
          borderRadius: BorderRadius.circular(28),
          onTap: () => context.go('/profile'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: pill(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(imageUrl: profile?.avatarUrl, initials: initials, radius: 21),
                if (first.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.text)),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(Icons.expand_more, color: AppColors.textSoft),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


/// Wide "Marşrut üzrə yük axtar": FROM ⇄ TO and "Yükləri axtar" in one row;
/// the same filter, save-route star and "my routes" as on mobile.
class _DeskRouteSearch extends ConsumerWidget {
  final AppStrings strings;
  const _DeskRouteSearch({required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final filter = ref.watch(routeFilterProvider);
    final saved = ref.watch(savedRoutesProvider);
    final isSaved = saved.contains(filter.key);
    final mobile = _RouteSearch(strings: strings);

    Widget field({required bool isFrom}) {
      final code = isFrom ? filter.from : filter.to;
      final city = isFrom ? filter.fromCity : filter.toCity;
      return Expanded(
        child: InkWell(
          key: ValueKey(isFrom ? 'desk-from' : 'desk-to'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => mobile._pick(context, ref, isFrom: isFrom),
          child: Container(
            constraints: const BoxConstraints(minHeight: 66),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.isDay ? AppColors.card : AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: code != null ? AppColors.accent : AppColors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: AppColors.textSoft, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(strings.t(isFrom ? 'route_from' : 'route_to'), style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
                      Text(
                        mobile._label(code, city, lang, strings.t('route_any_country')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.text),
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

    if (AppColors.neumorph) {
      // Neumorf (owner approved 27.11.2026): Haradan ⇄ Haraya as one
      // pressed-in pill and the orange "Yükləri axtar"; the same pickers,
      // swap, save / clear and saved routes.
      Widget neuField({required bool isFrom}) {
        final code = isFrom ? filter.from : filter.to;
        final city = isFrom ? filter.fromCity : filter.toCity;
        return Expanded(
          child: InkWell(
            key: ValueKey(isFrom ? 'desk-from' : 'desk-to'),
            borderRadius: BorderRadius.circular(24),
            onTap: () => mobile._pick(context, ref, isFrom: isFrom),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${strings.t(isFrom ? 'route_from' : 'route_to')} · ', style: TextStyle(color: AppColors.textSoft)),
                      TextSpan(
                          text: mobile._label(code, city, lang, strings.t('route_any_country')),
                          style: TextStyle(color: code != null ? AppColors.accent : AppColors.text)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ]),
            ),
          ),
        );
      }

      return Padding(
        key: const ValueKey('desk-route-neu'),
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Container(
                height: 62,
                padding: const EdgeInsets.only(left: 18, right: 8),
                decoration: neuInsetDecoration(radius: 31),
                child: Row(children: [
                  Icon(Icons.search, color: AppColors.textSoft, size: 22),
                  const SizedBox(width: 6),
                  neuField(isFrom: true),
                  IconButton(
                    tooltip: strings.t('route_swap'),
                    onPressed: () => ref.read(routeFilterProvider.notifier).state = filter.swapped,
                    icon: Icon(Icons.swap_horiz, color: AppColors.accent, size: 26),
                  ),
                  neuField(isFrom: false),
                  if (filter.isActive) ...[
                    IconButton(
                      tooltip: strings.t(isSaved ? 'route_saved' : 'route_save'),
                      onPressed: () {
                        final n = ref.read(savedRoutesProvider.notifier);
                        isSaved ? n.remove(filter.key) : n.add(filter.key);
                      },
                      icon: Icon(isSaved ? Icons.star : Icons.star_border, color: AppColors.accent),
                    ),
                    IconButton(
                      tooltip: strings.t('route_clear'),
                      onPressed: () => ref.read(routeFilterProvider.notifier).state = const RouteFilter(),
                      icon: Icon(Icons.close, color: AppColors.textSoft),
                    ),
                  ],
                ]),
              ),
            ),
            const SizedBox(width: 18),
            SizedBox(
              width: 240,
              child: FilledButton.icon(
                key: const ValueKey('desk-find-loads'),
                onPressed: _scrollToFeed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentFill,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 58),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
                ),
                icon: const Icon(Icons.search, size: 24),
                label: Text(strings.t('desk_find_loads'), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          if (saved.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(strings.t('route_my_routes'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                for (final k in saved)
                  InputChip(
                    label: Text(mobile._short(k, lang)),
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
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.line)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.search, size: 28, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(strings.t('route_search_title'),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                  if (filter.isActive) ...[
                    TextButton.icon(
                      onPressed: () {
                        final n = ref.read(savedRoutesProvider.notifier);
                        isSaved ? n.remove(filter.key) : n.add(filter.key);
                      },
                      icon: Icon(isSaved ? Icons.star : Icons.star_border, color: AppColors.accent),
                      label: Text(strings.t(isSaved ? 'route_saved' : 'route_save')),
                    ),
                    TextButton(
                      onPressed: () => ref.read(routeFilterProvider.notifier).state = const RouteFilter(),
                      child: Text(strings.t('route_clear')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  field(isFrom: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: IconButton(
                      tooltip: strings.t('route_swap'),
                      onPressed: () => ref.read(routeFilterProvider.notifier).state = filter.swapped,
                      icon: Icon(Icons.swap_horiz, color: AppColors.accent, size: 30),
                    ),
                  ),
                  field(isFrom: false),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 270,
                    child: FilledButton.icon(
                      key: const ValueKey('desk-find-loads'),
                      onPressed: _scrollToFeed,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentFill,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 66),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                      icon: const Icon(Icons.search, size: 26),
                      label: Text(strings.t('desk_find_loads'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
              if (saved.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(strings.t('route_my_routes'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                    for (final k in saved)
                      InputChip(
                        label: Text(mobile._short(k, lang)),
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

part of 'cargo_marketplace_screen.dart';

// Desktop "Yüklər" page (owner's desktop design, 19.10.2026): a wide hero
// with the live map in clouds, top search / bell / account, the counters
// and "Yük əlavə et"; then popular routes, the route search and the open
// loads as a grid. Same data, providers and actions as the mobile page —
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
    final allAds = ref.watch(liveAdsProvider).valueOrNull ?? const <Ad>[];
    final adsOn = ref.watch(homeAdsEnabledProvider).valueOrNull ?? false;
    final layout = ref.watch(adsFeedLayoutProvider).valueOrNull ?? AdFeedLayout.defaults;
    final minute = layout.rotateMinutes > 0 ? (ref.watch(adMinuteTickProvider).valueOrNull ?? 0) : 0;
    final rotation = layout.rotateMinutes > 0 ? minute ~/ layout.rotateMinutes : 0;
    List<CargoModel> visible(List<CargoModel> all) =>
        all.where((c) => (!filter.isActive || filter.matches(c)) && deskLoadMatches(c, query, lang)).toList();
    final shown = visible(cargoList);
    final searching = filter.isActive || query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketplaceProvider);
          ref.invalidate(liveAdsProvider);
          ref.invalidate(homeAdsEnabledProvider);
          ref.invalidate(adsFeedLayoutProvider);
          ref.invalidate(activeCarriersCountProvider);
          ref.invalidate(newCargo24hCountProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _DeskHero(strings: strings, cargoList: cargoList, loaded: marketplaceAsync.hasValue)),
            SliverToBoxAdapter(child: _DeskBody(child: _DeskPopularRoutes(strings: strings, cargoList: cargoList))),
            SliverToBoxAdapter(child: _DeskBody(child: _DeskRouteSearch(strings: strings))),
            SliverToBoxAdapter(
              child: _DeskBody(
                child: Padding(
                  key: _feedHeaderKey,
                  padding: const EdgeInsets.fromLTRB(2, 26, 2, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: Text(strings.t('home_open_loads'), style: AppFonts.display(size: 24, color: AppColors.text))),
                      if (marketplaceAsync.hasValue)
                        Text(strings.t('home_results', {'count': '${shown.length}'}),
                            style: TextStyle(fontSize: 16, color: AppColors.textSoft)),
                    ],
                  ),
                ),
              ),
            ),
            ...marketplaceAsync.when<List<Widget>>(
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
                              onPressed: () {
                                ref.read(routeFilterProvider.notifier).state = const RouteFilter();
                                ref.read(_deskQueryProvider.notifier).state = '';
                              },
                              child: Text(strings.t('route_clear')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ];
                }
                if (list.isEmpty) return [SliverToBoxAdapter(child: _EmptyMarketplace(strings: strings))];
                final ads = allAds.where((ad) => _adMatchesLoads(ad, list)).toList()
                  ..sort((a, b) => a.priority != b.priority ? a.priority.compareTo(b.priority) : a.startsAt.compareTo(b.startsAt));
                final showAds = adsOn && ads.isNotEmpty;
                final plan = _feedPlan(list.length, showAds, layout, maxAds: layout.repeat ? null : ads.length);
                return [
                  SliverToBoxAdapter(
                    child: _DeskBody(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 48),
                        child: LayoutBuilder(
                          builder: (context, c) => _DeskLoadGrid(
                            columns: c.maxWidth >= 1440 ? 4 : 3,
                            plan: plan,
                            buildLoad: (i) {
                              final cargo = list[i];
                              return CargoCard(
                                cargo: cargo,
                                strings: strings,
                                compact: true,
                                onTap: () => context.pushOnce('/cargo/${cargo.id}'),
                              );
                            },
                            buildAd: (slot) {
                              final ad = ads[(slot - rotation) % ads.length];
                              return SponsoredBanner(key: ValueKey('ad-$slot-${ad.id}'), ad: ad, strings: strings);
                            },
                          ),
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

/// Open loads in rows of [columns] equal cards (same height per row); an
/// ad slot of the feed plan takes a row of its own, at a readable width.
class _DeskLoadGrid extends StatelessWidget {
  final int columns;
  final List<({bool isAd, int index})> plan;
  final Widget Function(int index) buildLoad;
  final Widget Function(int slot) buildAd;
  const _DeskLoadGrid({required this.columns, required this.plan, required this.buildLoad, required this.buildAd});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var pending = <int>[];
    void flush() {
      if (pending.isEmpty) return;
      final cells = <Widget>[];
      for (var k = 0; k < columns; k++) {
        if (k > 0) cells.add(const SizedBox(width: 16));
        cells.add(Expanded(child: k < pending.length ? buildLoad(pending[k]) : const SizedBox.shrink()));
      }
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)),
      ));
      pending = <int>[];
    }

    for (final slot in plan) {
      if (slot.isAd) {
        flush();
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: buildAd(slot.index))),
        ));
      } else {
        pending.add(slot.index);
        if (pending.length == columns) flush();
      }
    }
    flush();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
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
    String stat(int n) => loaded ? '$n' : '—';
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
                      Text(strings.t('home_live_map'), style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2, size: 15)),
                    ]),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${strings.t('home_hero_1')} '),
                        TextSpan(text: strings.t('home_hero_2'), style: TextStyle(color: AppColors.accent)),
                        // Second line (owner, 19.10.2026): "Yüklər dünya üzrə / hərəkətdədir".
                        TextSpan(text: '\n${strings.t('home_hero_3')}'),
                      ]),
                      style: AppFonts.display(size: (w * 0.026).clamp(30.0, 42.0), color: AppColors.text, height: 1.15),
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
                    _DeskStat(
                      icon: Icons.groups_2,
                      color: AppColors.blue,
                      value: ref.watch(activeCarriersCountProvider).whenOrNull(data: (n) => '$n') ?? '—',
                      label: strings.t('home_stat_carriers'),
                    ),
                    const SizedBox(width: 14),
                    _DeskStat(
                      icon: Icons.bar_chart_rounded,
                      color: AppColors.online,
                      value: ref.watch(newCargo24hCountProvider).whenOrNull(data: (n) => '$n') ?? '—',
                      label: strings.t('home_stat_24h'),
                      onTap: _scrollToFeed,
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
                    onPressed: () => context.pushOnce('/cargo/create'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentFill,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.add, size: 26),
                    label: Text(strings.t('nav_add_cargo')),
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
                Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top bar of a desktop page: search field (filters this page), the bell
/// (unread messages → Mesajlar) and the account chip (→ Profil).
class _DeskTopBar extends ConsumerStatefulWidget {
  final AppStrings strings;
  final String hint;
  const _DeskTopBar({required this.strings, required this.hint});

  @override
  ConsumerState<_DeskTopBar> createState() => _DeskTopBarState();
}

class _DeskTopBarState extends ConsumerState<_DeskTopBar> {
  late final TextEditingController _text = TextEditingController(text: ref.read(_deskQueryProvider));

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
    final unread = (ref.watch(unreadCountProvider).valueOrNull ?? 0) + ref.watch(groupUnreadTotalProvider);
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
        Tooltip(
          message: s.t('nav_messages'),
          child: InkWell(
            key: const ValueKey('desk-bell'),
            customBorder: const CircleBorder(),
            onTap: () => context.go('/messages'),
            child: Container(
              width: 54,
              height: 54,
              decoration: pill(),
              alignment: Alignment.center,
              child: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                backgroundColor: AppColors.danger,
                child: Icon(Icons.notifications_none, color: AppColors.text, size: 26),
              ),
            ),
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
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

/// "Populyar marşrutlar": the most common routes of the open loads, five
/// cards at a time; the arrow shows the next ones. Tap = filter the loads.
class _DeskPopularRoutes extends ConsumerStatefulWidget {
  final AppStrings strings;
  final List<CargoModel> cargoList;
  const _DeskPopularRoutes({required this.strings, required this.cargoList});

  @override
  ConsumerState<_DeskPopularRoutes> createState() => _DeskPopularRoutesState();
}

class _DeskPopularRoutesState extends ConsumerState<_DeskPopularRoutes> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    String key(String v) => Countries.find(v)?.code ?? Countries.normalize(v);
    final counts = <String, int>{};
    final sample = <String, CargoModel>{};
    for (final c in widget.cargoList) {
      final r = '${key(c.pickupCountry)}>${key(c.destinationCountry)}';
      counts[r] = (counts[r] ?? 0) + 1;
      sample.putIfAbsent(r, () => c);
    }
    final routes = counts.keys.toList()..sort((x, y) => counts[y]!.compareTo(counts[x]!));
    if (routes.isEmpty) return const SizedBox(height: 8);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 14),
          child: Text(s.t('home_popular_routes'), style: AppFonts.display(size: 21, color: AppColors.text)),
        ),
        LayoutBuilder(
          builder: (context, c) {
            const gap = 16.0;
            // 5 cards on a wide window, 4 on a narrower one, so the codes always fit.
            final perView = c.maxWidth >= 1200 ? 5 : 4;
            final more = routes.length > perView;
            final cardW = (c.maxWidth - (perView - 1) * gap - (more ? 40 : 0)) / perView;
            return SizedBox(
              height: 80,
              child: Stack(
                children: [
                  MouseDragScroll(child: ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    itemCount: routes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: gap),
                    itemBuilder: (context, i) {
                      final r = routes[i];
                      final from = Countries.find(sample[r]!.pickupCountry);
                      final to = Countries.find(sample[r]!.destinationCountry);
                      final label = (from != null && to != null)
                          ? '${from.code} → ${to.code}'
                          : '${Countries.label(sample[r]!.pickupCountry, lang)} → ${Countries.label(sample[r]!.destinationCountry, lang)}';
                      return SizedBox(
                        width: cardW,
                        child: Material(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: (from != null && to != null)
                                ? () {
                                    ref.read(routeFilterProvider.notifier).state = RouteFilter(from: from.code, to: to.code);
                                    _scrollToFeed();
                                  }
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: Row(
                                children: [
                                  if (from != null) Text(from.flag, style: const TextStyle(fontSize: 26)),
                                  if (from != null && to != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('→', style: TextStyle(color: AppColors.accent, fontSize: 18)),
                                    ),
                                  if (to != null) Text(to.flag, style: const TextStyle(fontSize: 26)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
                                        const SizedBox(height: 2),
                                        Text(s.t('home_route_count', {'count': '${counts[r]}'}),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 14, color: AppColors.textSoft)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )),
                  if (more)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Material(
                          color: AppColors.card,
                          shape: CircleBorder(side: BorderSide(color: AppColors.line)),
                          elevation: 2,
                          child: IconButton(
                            key: const ValueKey('desk-routes-next'),
                            icon: Icon(Icons.chevron_right, color: AppColors.text),
                            onPressed: () {
                              final p = _scroll.position;
                              final next = p.pixels >= p.maxScrollExtent - 1
                                  ? 0.0
                                  : math.min(p.pixels + (cardW + gap) * (perView - 1), p.maxScrollExtent);
                              _scroll.animateTo(next, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
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
                        mobile._label(code, lang, strings.t('route_any_country')),
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
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text)),
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
                      onPressed: () => ref.read(routeFilterProvider.notifier).state = RouteFilter(from: filter.to, to: filter.from),
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
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                        label: Text(mobile._short(k)),
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

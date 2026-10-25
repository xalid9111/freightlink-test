import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/desktop_layout.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/vip_chessboard.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../../../core/widgets/page_hero.dart';
import '../../auth/data/activities_repository.dart';
import '../../auth/domain/activities.dart';
import '../../cargo/domain/vip_rows.dart' show vipRotation;
import '../domain/market_catalog.dart';
import '../domain/market_models.dart';
import 'market_brand_picker.dart';
import 'market_card.dart';
import 'market_home_desktop.dart';
import 'market_providers.dart';

IconData marketCategoryIcon(MarketCategory c) => switch (c) {
      MarketCategory.truck => Icons.local_shipping,
      MarketCategory.mediumTruck => Icons.fire_truck,
      MarketCategory.lightTruck => Icons.local_shipping_outlined,
      MarketCategory.trailer => Icons.rv_hookup,
      MarketCategory.semitrailer => Icons.airport_shuttle,
      MarketCategory.construction => Icons.construction,
      MarketCategory.other => Icons.more_horiz,
    };

/// "Satış elanı yerləşdir": a user without the "Satış" activity turns it
/// on with one tap first (owner's decision), then the form opens.
Future<void> openNewMarketAd(BuildContext context, WidgetRef ref, AppStrings s) async {
  final acts = ref.read(myActivitiesProvider).valueOrNull ?? const <Activity>{};
  if (!acts.contains(Activity.seller)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('mk_enable_seller_title')),
        content: Text(s.t('mk_enable_seller_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('act_enable'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(myActivitiesProvider.notifier).enable(Activity.seller);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('act_save_failed'))));
      return;
    }
  }
  if (context.mounted) context.pushOnce('/market/new');
}

/// TIR Bazarı (Şəkil 2): banner, "Satış elanı
/// yerləşdir", categories, search + filters, all ads in two columns loaded
/// page by page. Loaded as a separate part of the app (deferred).
class MarketHomeScreen extends ConsumerStatefulWidget {
  const MarketHomeScreen({super.key});

  @override
  ConsumerState<MarketHomeScreen> createState() => _MarketHomeScreenState();
}

class _MarketHomeScreenState extends ConsumerState<MarketHomeScreen> {
  // Made in initState, not lazily: on a computer build() returns the desktop
  // page without touching it, and a lazy controller first touched in
  // dispose() would read ref after the widget was disposed.
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: _searchLabel(ref.read(marketFilterProvider)));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(MarketFilter f) => ref.read(marketFilterProvider.notifier).state = f;

  Future<void> _refresh() async {
    ref.invalidate(marketFeedProvider);
    ref.invalidate(marketVipQueueProvider);
  }

  @override
  Widget build(BuildContext context) {
    // Wide window: the computer page (same data and actions, wide layout).
    if (isDesktopLayout(context)) return const MarketHomeDesktop();
    final s = ref.watch(stringsProvider);
    final filter = ref.watch(marketFilterProvider);
    final feed = ref.watch(marketFeedProvider);
    final vip = ref.watch(marketVipQueueProvider(filter.category)).valueOrNull ?? const <MarketListing>[];
    // VIP ads among the ads, as on the Loads page (owner, 24.10.2026): no
    // VIP row under the banner any more; ad–VIP, VIP–ad … and the VIP
    // order moves on every few minutes so each VIP comes to the front.
    // Columns exactly as the grid below lays them out (2 on a phone).
    final columns = ((MediaQuery.sizeOf(context).width - 32) / (260 + 12)).ceil().clamp(1, 8);
    final entries = vipChessboard([for (final l in feed.items) if (!l.vipActive()) l], vip,
        columns: columns, rotation: vipRotation(DateTime.now()));
    // Filter changed elsewhere ("Hamısına bax", reset): show its text.
    ref.listen<MarketFilter>(marketFilterProvider, (_, next) {
      final label = _searchLabel(next);
      if (_search.text != label) _search.text = label;
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) ref.read(marketFeedProvider.notifier).loadMore();
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  sliver: SliverList.list(children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping, color: AppColors.accent, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(s.t('nav_market'),
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.text)),
                        ),
                        IconButton(
                          tooltip: s.t('mk_favorites'),
                          onPressed: () => context.pushOnce('/market/favorites'),
                          icon: const Icon(Icons.favorite_border, size: 28),
                        ),
                      ],
                    ),
                    // Banner (owner, 21.10.2026): the same as on the computer,
                    // night / day picture, the admin changes it here too.
                    const SizedBox(height: 8),
                    PageHeroBanner(
                      page: 'market',
                      strings: s,
                      kicker: s.t('nav_market'),
                      defaultTitle: s.t('mk_hero_title'),
                      defaultAccent: s.t('mk_hero_accent'),
                      defaultSubtitle: s.t('mk_hero_subtitle'),
                      icon: Icons.local_shipping,
                      height: 150,
                    ),
                    const SizedBox(height: 14),
                    _SellBanner(s: s, onTap: () => openNewMarketAd(context, ref, s)),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 44,
                      child: MouseDragScroll(child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final c in MarketCategory.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _CategoryChip(
                                icon: marketCategoryIcon(c),
                                label: s.t(c.labelKey),
                                selected: filter.category == c,
                                onTap: () => _setFilter(filter.copyWith(
                                  category: () => filter.category == c ? null : c,
                                  brand: () => null,
                                  model: () => null,
                                )),
                              ),
                            ),
                        ],
                      )),
                    ),
                    const SizedBox(height: 12),
                    _SearchBox(
                      controller: _search,
                      hint: s.t('mk_search_hint'),
                      highlighted: filter.hasDetails,
                      // Owner, 24.10.2026: a tap opens the "Marka" page.
                      onOpen: () => _openSearch(context, s, filter),
                      onClear: filter.brand != null || filter.model != null || (filter.q ?? '').isNotEmpty
                          ? () => _setFilter(filter.copyWith(q: () => null, brand: () => null, model: () => null))
                          : null,
                      onFilters: () => _openFilters(context, s, filter),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: Text(s.t('mk_ads_title'),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                        TextButton(
                          onPressed: () => context.pushOnce('/market/mine'),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(s.t('mk_my_ads'), style: TextStyle(color: AppColors.textSoft)),
                            Icon(Icons.chevron_right, color: AppColors.textSoft),
                          ]),
                        ),
                      ],
                    ),
                    if (filter.brand != null || filter.model != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Wrap(spacing: 6, children: [
                          InputChip(
                            label: Text([filter.brand, filter.model].whereType<String>().join(' ')),
                            onDeleted: () => _setFilter(filter.copyWith(brand: () => null, model: () => null)),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 6),
                  ]),
                ),
                if (feed.items.isEmpty && feed.loading)
                  const SliverToBoxAdapter(
                      child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())))
                else if (feed.items.isEmpty && feed.error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        Text(s.t('home_error_loading'), style: TextStyle(color: AppColors.textSoft)),
                        TextButton(onPressed: _refresh, child: Text(s.t('common_try_again'))),
                      ]),
                    ),
                  )
                else if (feed.items.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                      child: Text(s.t('mk_empty'),
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, height: 1.4)),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 260,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: MarketFeedCard.extent,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => MarketFeedCard(
                            // A VIP ad can come again further down: keys by place.
                            key: ValueKey('${entries[i].$2 ? 'vip' : 'ad'}-$i-${entries[i].$1.id}'),
                            l: entries[i].$1),
                        childCount: entries.length,
                      ),
                    ),
                  ),
                if (feed.items.isNotEmpty && feed.loading)
                  const SliverToBoxAdapter(
                      child: Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Text in the search field: the free text, or "Brand Model".
  static String _searchLabel(MarketFilter f) =>
      (f.q ?? '').isNotEmpty ? f.q! : [f.brand, f.model].whereType<String>().join(' ');

  Future<void> _openSearch(BuildContext context, AppStrings s, MarketFilter f) async {
    final pick = await openMarketSearch(context, s: s, filter: f);
    if (pick == null || !mounted) return;
    final cur = ref.read(marketFilterProvider);
    if (pick.cleared) {
      _setFilter(cur.copyWith(q: () => null, brand: () => null, model: () => null));
    } else if (pick.text != null) {
      _setFilter(cur.copyWith(q: () => pick.text, brand: () => null, model: () => null));
    } else {
      _setFilter(cur.copyWith(q: () => null, brand: () => pick.brand, model: () => pick.model));
    }
  }

  Future<void> _openFilters(BuildContext context, AppStrings s, MarketFilter f) async {
    final res = await showModalBottomSheet<MarketFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Swiping down closes the filters (owner, 25.10.2026): from the
      // handle, or from anywhere once the list is at its top.
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scroll) => MarketFilterSheet(filter: f, s: s, scrollController: scroll),
      ),
    );
    if (res != null) _setFilter(res);
  }
}

class _SellBanner extends StatelessWidget {
  final AppStrings s;
  final VoidCallback onTap;
  const _SellBanner({required this.s, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(child: Text(s.t('mk_buy_sell'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
          FilledButton.icon(
            key: const ValueKey('mk-new-ad'),
            onPressed: onTap,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Text(s.t('mk_new_ad'), style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.local_shipping_outlined, color: AppColors.accent),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.accent : AppColors.text;
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.10) : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.accent : AppColors.line, width: selected ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool highlighted;
  final VoidCallback onOpen;
  final VoidCallback? onClear;
  final VoidCallback onFilters;
  const _SearchBox({
    required this.controller,
    required this.hint,
    required this.highlighted,
    required this.onOpen,
    required this.onClear,
    required this.onFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      child: TextField(
        key: const ValueKey('mk-search-box'),
        controller: controller,
        readOnly: true,
        // Only opens the Marka page: never focused, no cursor and no text
        // selection when the page comes back (owner, 25.10.2026).
        canRequestFocus: false,
        showCursor: false,
        enableInteractiveSelection: false,
        onTap: onOpen,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search, color: AppColors.accent),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (onClear != null)
              IconButton(key: const ValueKey('mk-search-clear'), icon: Icon(Icons.close, color: AppColors.textSoft), onPressed: onClear),
            IconButton(
              icon: Icon(Icons.tune, color: highlighted ? AppColors.accent : AppColors.text),
              onPressed: onFilters,
            ),
          ]),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.line)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.line)),
        ),
      ),
    );
  }
}

/// Ətraflı filtrlər: brand, model, city, price, year, mileage.
class MarketFilterSheet extends StatefulWidget {
  final MarketFilter filter;
  final AppStrings s;
  /// From the draggable sheet, so a swipe down at the top closes it.
  final ScrollController? scrollController;
  const MarketFilterSheet({super.key, required this.filter, required this.s, this.scrollController});

  @override
  State<MarketFilterSheet> createState() => _MarketFilterSheetState();
}

class _MarketFilterSheetState extends State<MarketFilterSheet> {
  late final _brand = TextEditingController(text: widget.filter.brand ?? '');
  late final _model = TextEditingController(text: widget.filter.model ?? '');
  late final _city = TextEditingController(text: widget.filter.city ?? '');
  late final _minPrice = TextEditingController(text: widget.filter.minPrice?.round().toString() ?? '');
  late final _maxPrice = TextEditingController(text: widget.filter.maxPrice?.round().toString() ?? '');
  late final _yearFrom = TextEditingController(text: widget.filter.yearFrom?.toString() ?? '');
  late final _yearTo = TextEditingController(text: widget.filter.yearTo?.toString() ?? '');
  late final _maxKm = TextEditingController(text: widget.filter.maxMileage?.toString() ?? '');
  late String? _body = widget.filter.bodyType;
  late String? _avail = widget.filter.availability;
  late String? _axle = widget.filter.axleFormula;
  late final _equip = {...widget.filter.equipment};
  late bool? _damaged = widget.filter.damaged;

  @override
  void dispose() {
    for (final c in [_brand, _model, _city, _minPrice, _maxPrice, _yearFrom, _yearTo, _maxKm]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  int? _i(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'\s'), ''));

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final brands = widget.filter.category == null
        ? ({for (final c in MarketCategory.values) ...marketBrands(c)}.toList()..sort())
        : marketBrands(widget.filter.category!);
    // Popular brands with logos (owner, 25.10.2026); only those of the
    // chosen type. One tap picks, a second tap clears.
    final cat = widget.filter.category;
    final popular = [for (final b in kMarketPopularBrands) if (cat == null || marketBrands(cat).contains(b)) b];
    final picked = _t(_brand) == null ? null : canonicalMarketBrand(_t(_brand)!);
    // Models of the chosen brand appear at once as choices (owner,
    // 25.10.2026); a brand without catalogue models keeps the text field.
    final models = marketFilterModels(cat, _t(_brand));
    final typedModel = _t(_model);
    void pick(String b) => setState(() {
          _brand.text = picked == b ? '' : b;
          _model.clear();
        });
    Widget label(String key) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s.t(key), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSoft)),
        );
    Widget field(TextEditingController c, String label, {bool number = false}) => TextField(
          controller: c,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label, isDense: true),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.t('mk_filters'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (popular.isNotEmpty) ...[
              label('mk_popular_brands'),
              GridView.count(
                key: const ValueKey('mk-filter-popular'),
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 0.95,
                children: [
                  for (final b in popular) _PopularBrand(brand: b, selected: picked == b, onTap: () => pick(b)),
                ],
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _brand,
              // Typed brand → the popular tile above shows it.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: s.t('mk_brand'),
                isDense: true,
                // Pick from the list or type any brand.
                suffixIcon: PopupMenuButton<String>(
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (v) => setState(() {
                    _brand.text = v;
                    _model.clear();
                  }),
                  itemBuilder: (_) => [for (final b in brands) PopupMenuItem(value: b, child: Text(b))],
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (models.isEmpty)
              field(_model, s.t('mk_model'))
            else ...[
              label('mk_model'),
              Wrap(key: const ValueKey('mk-filter-models'), spacing: 6, runSpacing: 6, children: [
                ChoiceChip(
                  key: const ValueKey('mk-filter-model-all'),
                  label: Text(s.t('svc_all')),
                  selected: typedModel == null,
                  onSelected: (_) => setState(_model.clear),
                ),
                // A model typed earlier that is not in the list stays visible.
                for (final m in [
                  if (typedModel != null && !models.contains(typedModel)) typedModel,
                  ...models,
                ])
                  ChoiceChip(
                    key: ValueKey('mk-filter-model-$m'),
                    label: Text(m),
                    selected: typedModel == m,
                    onSelected: (on) => setState(() => _model.text = on ? m : ''),
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: const ValueKey('mk-filter-body'),
              initialValue: _body,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.t('mk_body_type'), isDense: true),
              items: [
                DropdownMenuItem(value: null, child: Text(s.t('svc_all'))),
                for (final b in kMarketBodyTypes) DropdownMenuItem(value: b, child: Text(s.t('mk_body_$b'))),
              ],
              onChanged: (v) => setState(() => _body = v),
            ),
            // In stock / on order (owner, 25.10.2026, 0065); none = all.
            const SizedBox(height: 12),
            label('mk_availability'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                key: const ValueKey('mk-filter-avail-all'),
                label: Text(s.t('svc_all')),
                selected: _avail == null,
                onSelected: (_) => setState(() => _avail = null),
              ),
              for (final a in kMarketAvailability)
                ChoiceChip(
                  key: ValueKey('mk-filter-avail-$a'),
                  label: Text(s.t('mk_avail_$a')),
                  selected: _avail == a,
                  onSelected: (_) => setState(() => _avail = a),
                ),
            ]),
            // Wheel formula (not for trailers), equipment (the ad has all
            // chosen), damage — owner, 25.10.2026, 0065.
            if (marketHasAxleFormula(cat)) ...[
              const SizedBox(height: 12),
              label('mk_axle_formula'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final a in kMarketAxleFormulas)
                  ChoiceChip(
                    key: ValueKey('mk-filter-axle-$a'),
                    label: Text(a),
                    selected: _axle == a,
                    onSelected: (on) => setState(() => _axle = on ? a : null),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            label('mk_equipment'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in kMarketEquipment)
                FilterChip(
                  key: ValueKey('mk-filter-eq-$e'),
                  label: Text(s.t('mk_eq_$e')),
                  selected: _equip.contains(e),
                  onSelected: (on) => setState(() => on ? _equip.add(e) : _equip.remove(e)),
                ),
            ]),
            const SizedBox(height: 12),
            label('mk_condition'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(
                key: const ValueKey('mk-filter-damage-all'),
                label: Text(s.t('svc_all')),
                selected: _damaged == null,
                onSelected: (_) => setState(() => _damaged = null),
              ),
              for (final d in const [false, true])
                ChoiceChip(
                  key: ValueKey('mk-filter-damage-$d'),
                  label: Text(s.t(d ? 'mk_damage_yes' : 'mk_damage_no')),
                  selected: _damaged == d,
                  onSelected: (_) => setState(() => _damaged = d),
                ),
            ]),
            const SizedBox(height: 10),
            field(_city, s.t('mk_city')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: field(_minPrice, s.t('mk_price_from'), number: true)),
              const SizedBox(width: 10),
              Expanded(child: field(_maxPrice, s.t('mk_price_to'), number: true)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: field(_yearFrom, s.t('mk_year_from'), number: true)),
              const SizedBox(width: 10),
              Expanded(child: field(_yearTo, s.t('mk_year_to'), number: true)),
            ]),
            const SizedBox(height: 10),
            field(_maxKm, s.t('mk_max_km'), number: true),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, MarketFilter(category: widget.filter.category, q: widget.filter.q)),
                  child: Text(s.t('mk_reset')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    widget.filter.copyWith(
                      brand: () => _t(_brand),
                      model: () => _t(_model),
                      bodyType: () => _body,
                      availability: () => _avail,
                      axleFormula: () => marketHasAxleFormula(cat) ? _axle : null,
                      equipment: () => [for (final e in kMarketEquipment) if (_equip.contains(e)) e],
                      damaged: () => _damaged,
                      city: () => _t(_city),
                      minPrice: () => _i(_minPrice)?.toDouble(),
                      maxPrice: () => _i(_maxPrice)?.toDouble(),
                      yearFrom: () => _i(_yearFrom),
                      yearTo: () => _i(_yearTo),
                      maxMileage: () => _i(_maxKm),
                    ),
                  ),
                  child: Text(s.t('mk_apply')),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A popular brand in the filter: its logo (or letters) and its name.
class _PopularBrand extends StatelessWidget {
  final String brand;
  final bool selected;
  final VoidCallback onTap;
  const _PopularBrand({required this.brand, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentFill.withValues(alpha: AppColors.isDay ? 0.12 : 0.16) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.accentFill : Colors.transparent),
      ),
      child: InkWell(
        key: ValueKey('mk-pop-brand-$brand'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            BrandBadge(brand, size: 44),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(brand,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: selected ? AppColors.accent : AppColors.text)),
            ),
          ]),
        ),
      ),
    );
  }
}

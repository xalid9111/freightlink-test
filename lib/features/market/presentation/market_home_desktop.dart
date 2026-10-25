import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/layout/desk_header_actions.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/widgets/vip_frame.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../../../core/widgets/page_hero.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/market_catalog.dart';
import '../domain/market_models.dart';
import 'market_brand_picker.dart' show BrandBadge;
import 'market_card.dart';
import 'market_home_screen.dart' show marketCategoryIcon, openNewMarketAd;
import 'market_providers.dart';

const double _kMaxContent = 1640;
const double _kPad = 40;

/// TIR Bazarı on a computer (owner, 19.10.2026): the admin's banner on top
/// (picture + texts, an admin edits it right on the banner), brand chips,
/// "TIR axtar", then the ads three in a row with three VIP places on each
/// side (the newest VIP ads). Same data, filters and actions as on the
/// phone; the phone page is not changed.
class MarketHomeDesktop extends ConsumerStatefulWidget {
  const MarketHomeDesktop({super.key});

  @override
  ConsumerState<MarketHomeDesktop> createState() => _MarketHomeDesktopState();
}

class _MarketHomeDesktopState extends ConsumerState<MarketHomeDesktop> {
  final _feedKey = GlobalKey();

  void _setFilter(MarketFilter f) => ref.read(marketFilterProvider.notifier).state = f;

  void _toFeed() {
    final c = _feedKey.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final filter = ref.watch(marketFilterProvider);
    final feed = ref.watch(marketFeedProvider);
    final vip = ref.watch(marketVipLatestProvider(filter.category)).valueOrNull ?? const <MarketListing>[];
    final (left, right) = marketVipColumns(vip);
    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical && n.metrics.pixels > n.metrics.maxScrollExtent - 700) {
            ref.read(marketFeedProvider.notifier).loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Body(child: _Hero(s: s, filter: filter, onSearch: (q) {
              _setFilter(filter.copyWith(q: () => q.trim().isEmpty ? null : q.trim()));
              _toFeed();
            }))),
            SliverToBoxAdapter(
              child: _Body(
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _BrandChips(s: s, filter: filter, onChanged: _setFilter),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _Body(
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _SearchPanel(s: s, filter: filter, onSearch: (f) {
                    _setFilter(f);
                    _toFeed();
                  }),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _Body(
                child: Padding(
                  key: _feedKey,
                  padding: const EdgeInsets.fromLTRB(2, 26, 2, 14),
                  child: Row(children: [
                    Expanded(
                      child: Text(s.t('mk_ads_title'),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ),
                    TextButton.icon(
                      onPressed: () => context.pushOnce('/market/favorites'),
                      icon: const Icon(Icons.favorite_border, size: 20),
                      label: Text(s.t('mk_favorites')),
                    ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: () => context.pushOnce('/market/mine'),
                      icon: const Icon(Icons.list_alt, size: 20),
                      label: Text(s.t('mk_my_ads')),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      key: const ValueKey('desk-market-sell'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentFill,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => openNewMarketAd(context, ref, s),
                      icon: const Icon(Icons.add),
                      label: Text(s.t('mk_new_ad')),
                    ),
                  ]),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _Body(
                child: LayoutBuilder(builder: (context, c) {
                  const gap = 18.0;
                  final side = (c.maxWidth * 0.17).clamp(180.0, 270.0);
                  final grid = c.maxWidth - 2 * (side + gap);
                  final cols = grid >= 560 ? 3 : 2;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: side, child: _VipColumn(s: s, items: left, side: 'left')),
                      const SizedBox(width: gap),
                      Expanded(child: _Grid(s: s, feed: feed, cols: cols, onReset: () => _setFilter(const MarketFilter()))),
                      const SizedBox(width: gap),
                      SizedBox(width: side, child: _VipColumn(s: s, items: right, side: 'right')),
                    ],
                  );
                }),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Widget child;
  const _Body({required this.child});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContent),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: _kPad), child: child),
        ),
      );
}

// ---- banner ----------------------------------------------------------------

class _Hero extends ConsumerWidget {
  final AppStrings s;
  final MarketFilter filter;
  final ValueChanged<String> onSearch;
  const _Hero({required this.s, required this.filter, required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = ref.watch(pageHeroProvider('market')).valueOrNull;
    final isAdmin = ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin;
    // Night / day picture for the current theme (0049).
    final img = hero?.imageFor(day: AppColors.isDay);
    final title = hero?.title ?? s.t('mk_hero_title');
    final accent = hero?.titleAccent ?? s.t('mk_hero_accent');
    final subtitle = hero?.subtitle ?? s.t('mk_hero_subtitle');
    // On a photo the text is light; without one it follows the theme.
    final onPhoto = img != null;
    // Picture with its own writing (0050): no texts and no shade on it.
    final texts = !onPhoto || (hero?.showText ?? true);
    final ink = onPhoto ? Colors.white : AppColors.text;
    final soft = onPhoto ? Colors.white.withValues(alpha: 0.85) : AppColors.textSoft;
    final shadow = onPhoto ? const [Shadow(color: Color(0x99000000), blurRadius: 14)] : null;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = (w * 0.26).clamp(320.0, 420.0);
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (img != null)
                  PageHeroImage(
                      url: img,
                      align: hero!.alignmentFor(day: AppColors.isDay),
                      zoom: hero.zoomFor(day: AppColors.isDay),
                      fallback: (_) => const PageHeroGround(icon: Icons.local_shipping))
                else
                  const PageHeroGround(icon: Icons.local_shipping),
                if (onPhoto && texts)
                  // Darker on the left so the texts stay readable on any photo.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xCC000000), Color(0x66000000), Color(0x00000000)],
                        stops: [0, 0.45, 0.8],
                      ),
                    ),
                  ),
                if (texts)
                Positioned(
                  left: 36,
                  top: 92,
                  width: math.max(320, w * 0.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Text(s.t('nav_market').toUpperCase(),
                            style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2, size: 15)),
                      ]),
                      const SizedBox(height: 8),
                      Text.rich(
                        key: const ValueKey('mk-hero-title'),
                        TextSpan(children: [
                          TextSpan(text: '$title\n'),
                          TextSpan(text: accent, style: TextStyle(color: AppColors.accent)),
                        ]),
                        style: AppFonts.display(size: (w * 0.028).clamp(30.0, 44.0), color: ink, height: 1.15)
                            .copyWith(shadows: shadow),
                      ),
                      const SizedBox(height: 10),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.5, color: soft, height: 1.35, shadows: shadow)),
                    ],
                  ),
                ),
                Positioned(
                  top: 18,
                  right: 20,
                  left: w * 0.38,
                  child: DeskHeaderActions(strings: s, search: _HeroSearch(s: s, initial: filter.q ?? '', onSearch: onSearch)),
                ),
                if (isAdmin)
                  Positioned(
                    right: 20,
                    bottom: 18,
                    child: FilledButton.icon(
                      key: const ValueKey('mk-hero-edit'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.55),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => showPageHeroEditor(context, strings: s, page: 'market', hero: hero, icon: Icons.local_shipping),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(s.t('mk_hero_edit')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _HeroSearch extends StatefulWidget {
  final AppStrings s;
  final String initial;
  final ValueChanged<String> onSearch;
  const _HeroSearch({required this.s, required this.initial, required this.onSearch});

  @override
  State<_HeroSearch> createState() => _HeroSearchState();
}

class _HeroSearchState extends State<_HeroSearch> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(covariant _HeroSearch old) {
    super.didUpdateWidget(old);
    // Filter cleared elsewhere → empty field too.
    if (widget.initial != old.initial && widget.initial != _text.text) _text.text = widget.initial;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: DeskHeaderActions.pill(),
      child: TextField(
        key: const ValueKey('desk-market-search'),
        controller: _text,
        onSubmitted: widget.onSearch,
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 15.5, color: AppColors.text),
        decoration: InputDecoration(
          filled: false,
          isDense: true,
          hintText: widget.s.t('mk_desk_search_hint'),
          hintStyle: TextStyle(color: AppColors.textSoft, fontSize: 15.5),
          prefixIcon: Icon(Icons.search, color: AppColors.textSoft, size: 26),
          suffixIcon: IconButton(
            tooltip: widget.s.t('search_apply'),
            icon: Icon(Icons.arrow_forward, color: AppColors.accent),
            onPressed: () => widget.onSearch(_text.text),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

// ---- brands + search ------------------------------------------------------------

/// "Hamısı" + the truck brands of the catalogue (one tap = that brand).
class _BrandChips extends StatelessWidget {
  final AppStrings s;
  final MarketFilter filter;
  final ValueChanged<MarketFilter> onChanged;
  const _BrandChips({required this.s, required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brands = marketBrands(filter.category ?? MarketCategory.truck);
    Widget chip(String label, IconData icon, bool on, VoidCallback tap, {Key? key}) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Material(
            color: on ? AppColors.accentFill.withValues(alpha: AppColors.isDay ? 0.12 : 0.16) : AppColors.card,
            shape: StadiumBorder(side: BorderSide(color: on ? AppColors.accentFill : AppColors.line)),
            child: InkWell(
              key: key,
              customBorder: const StadiumBorder(),
              onTap: tap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 20, color: on ? AppColors.accent : AppColors.textSoft),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: on ? AppColors.accent : AppColors.text)),
                ]),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 48,
      child: MouseDragScroll(child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(s.t('svc_all'), Icons.grid_view_rounded, filter.brand == null,
              () => onChanged(filter.copyWith(brand: () => null, model: () => null)),
              key: const ValueKey('desk-brand-all')),
          for (final b in brands)
            chip(b, Icons.local_shipping_outlined, filter.brand == b,
                () => onChanged(filter.copyWith(brand: () => filter.brand == b ? null : b, model: () => null)),
                key: ValueKey('desk-brand-$b')),
        ],
      )),
    );
  }
}

/// "TIR axtar": type, brand, model, year, price, city → the same filter as
/// the phone's filter sheet.
class _SearchPanel extends StatefulWidget {
  final AppStrings s;
  final MarketFilter filter;
  final ValueChanged<MarketFilter> onSearch;
  const _SearchPanel({required this.s, required this.filter, required this.onSearch});

  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  late MarketCategory? _cat = widget.filter.category;
  late String? _brand = widget.filter.brand;
  late String? _model = widget.filter.model;
  late final _yFrom = TextEditingController(text: widget.filter.yearFrom?.toString() ?? '');
  late final _yTo = TextEditingController(text: widget.filter.yearTo?.toString() ?? '');
  late final _pMin = TextEditingController(text: widget.filter.minPrice?.round().toString() ?? '');
  late final _pMax = TextEditingController(text: widget.filter.maxPrice?.round().toString() ?? '');
  late final _city = TextEditingController(text: widget.filter.city ?? '');
  late String? _avail = widget.filter.availability;
  late String? _axle = widget.filter.axleFormula;
  late final _equip = {...widget.filter.equipment};
  late bool? _damaged = widget.filter.damaged;

  @override
  void didUpdateWidget(covariant _SearchPanel old) {
    super.didUpdateWidget(old);
    // Brand chip / reset elsewhere → the panel shows the same filter.
    if (widget.filter.brand != old.filter.brand || widget.filter.category != old.filter.category) {
      _cat = widget.filter.category;
      _brand = widget.filter.brand;
      _model = widget.filter.model;
    }
    final f = widget.filter, o = old.filter;
    if (f.availability != o.availability || f.axleFormula != o.axleFormula ||
        f.equipment.join(',') != o.equipment.join(',') || f.damaged != o.damaged) {
      _avail = f.availability;
      _axle = f.axleFormula;
      _equip
        ..clear()
        ..addAll(f.equipment);
      _damaged = f.damaged;
    }
  }

  @override
  void dispose() {
    for (final c in [_yFrom, _yTo, _pMin, _pMax, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());
  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.'));

  void _go() => widget.onSearch(widget.filter.copyWith(
        category: () => _cat,
        brand: () => _brand,
        model: () => _model,
        yearFrom: () => _int(_yFrom),
        yearTo: () => _int(_yTo),
        minPrice: () => _num(_pMin),
        maxPrice: () => _num(_pMax),
        city: () => _city.text.trim().isEmpty ? null : _city.text.trim(),
        availability: () => _avail,
        axleFormula: () => marketHasAxleFormula(_cat) ? _axle : null,
        equipment: () => [for (final e in kMarketEquipment) if (_equip.contains(e)) e],
        damaged: () => _damaged,
      ));

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final cat = _cat ?? MarketCategory.truck;
    final brands = marketBrands(cat);
    final models = _brand == null ? const <String>[] : marketModels(cat, _brand);
    InputDecoration deco(String label, {IconData? icon, String? hint}) => InputDecoration(
          labelText: s.t(label),
          hintText: hint,
          isDense: true,
          prefixIcon: icon == null ? null : Icon(icon, size: 20, color: AppColors.textSoft),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
        );
    Widget box(double w, Widget child) => SizedBox(width: w, child: child);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.search, color: AppColors.accent, size: 26),
          const SizedBox(width: 10),
          Text(s.t('mk_find_title'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)),
        ]),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          // One row on a wide screen; on a narrower one two even rows:
          // type · brand · model · city, then years · prices · "Axtar".
          const g = 12.0;
          final oneRow = c.maxWidth >= 1200;
          final unit = oneRow ? ((c.maxWidth - 8 * g - 150) / 8.5) : 0.0;
          final top = (c.maxWidth - 3 * g) / 4 - 0.5;
          final bottom = (c.maxWidth - 4 * g - 150) / 4 - 0.5;
          return Wrap(spacing: g, runSpacing: g, crossAxisAlignment: WrapCrossAlignment.center, children: [
            box(oneRow ? unit * 1.1 : top, DropdownButtonFormField<MarketCategory?>(
              key: const ValueKey('desk-mk-cat'),
              initialValue: _cat,
              isExpanded: true,
              decoration: deco('mk_type'),
              items: [
                DropdownMenuItem(value: null, child: Text(s.t('svc_all'))),
                for (final c in MarketCategory.values)
                  DropdownMenuItem(value: c, child: Row(children: [
                    Icon(marketCategoryIcon(c), size: 18),
                    const SizedBox(width: 6),
                    Flexible(child: Text(s.t(c.labelKey), overflow: TextOverflow.ellipsis)),
                  ])),
              ],
              onChanged: (v) => setState(() {
                _cat = v;
                _brand = null;
                _model = null;
              }),
            )),
            box(oneRow ? unit * 1.1 : top, DropdownButtonFormField<String?>(
              key: ValueKey('desk-mk-brand-$_cat-$_brand'),
              initialValue: brands.contains(_brand) ? _brand : null,
              isExpanded: true,
              decoration: deco('mk_brand'),
              items: [
                DropdownMenuItem(value: null, child: Text(s.t('svc_all'))),
                // Logo (or letters) left of the name (owner, 25.10.2026).
                for (final b in brands)
                  DropdownMenuItem(value: b, child: Row(children: [
                    BrandBadge(b, size: 24),
                    const SizedBox(width: 8),
                    Flexible(child: Text(b, overflow: TextOverflow.ellipsis)),
                  ])),
              ],
              onChanged: (v) => setState(() {
                _brand = v;
                _model = null;
              }),
            )),
            box(oneRow ? unit * 1.1 : top, DropdownButtonFormField<String?>(
              key: ValueKey('desk-mk-model-$_brand'),
              initialValue: models.contains(_model) ? _model : null,
              isExpanded: true,
              decoration: deco('mk_model'),
              items: [
                DropdownMenuItem(value: null, child: Text(s.t('svc_all'))),
                for (final m in models) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _brand == null ? null : (v) => setState(() => _model = v),
            )),
            box(oneRow ? unit * 1.1 : top, TextField(
              controller: _city,
              onSubmitted: (_) => _go(),
              decoration: deco('mk_city', icon: Icons.place_outlined),
            )),
            box(oneRow ? unit * 0.9 : bottom, TextField(controller: _yFrom, keyboardType: TextInputType.number, decoration: deco('mk_year_from'))),
            box(oneRow ? unit * 0.9 : bottom, TextField(controller: _yTo, keyboardType: TextInputType.number, decoration: deco('mk_year_to'))),
            box(oneRow ? unit * 1.1 : bottom, TextField(controller: _pMin, keyboardType: TextInputType.number, decoration: deco('mk_price_from'))),
            box(oneRow ? unit * 1.1 : bottom, TextField(controller: _pMax, keyboardType: TextInputType.number, decoration: deco('mk_price_to'))),
            SizedBox(
              width: 150,
              height: 50,
              child: FilledButton.icon(
                key: const ValueKey('desk-mk-find'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentFill,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _go,
                icon: const Icon(Icons.search),
                label: Text(s.t('search_apply'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ]);
        }),
        // Same choices as the phone's filter (owner, 25.10.2026, 0065): a
        // second click on a chosen one clears it; applied with "Axtar".
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final a in kMarketAvailability)
            ChoiceChip(
              key: ValueKey('desk-mk-avail-$a'),
              label: Text(s.t('mk_avail_$a')),
              selected: _avail == a,
              onSelected: (on) => setState(() => _avail = on ? a : null),
            ),
          const SizedBox(width: 10),
          if (marketHasAxleFormula(_cat))
            for (final a in kMarketAxleFormulas)
              ChoiceChip(
                key: ValueKey('desk-mk-axle-$a'),
                label: Text(a),
                selected: _axle == a,
                onSelected: (on) => setState(() => _axle = on ? a : null),
              ),
          const SizedBox(width: 10),
          for (final e in kMarketEquipment)
            FilterChip(
              key: ValueKey('desk-mk-eq-$e'),
              label: Text(s.t('mk_eq_$e')),
              selected: _equip.contains(e),
              onSelected: (on) => setState(() => on ? _equip.add(e) : _equip.remove(e)),
            ),
          const SizedBox(width: 10),
          for (final d in const [false, true])
            ChoiceChip(
              key: ValueKey('desk-mk-damage-$d'),
              label: Text(s.t(d ? 'mk_damage_yes' : 'mk_damage_no')),
              selected: _damaged == d,
              onSelected: (on) => setState(() => _damaged = on ? d : null),
            ),
        ]),
      ]),
    );
  }
}

// ---- ads + VIP places -------------------------------------------------------------

class _Grid extends StatelessWidget {
  final AppStrings s;
  final MarketFeedState feed;
  final int cols;
  final VoidCallback onReset;
  const _Grid({required this.s, required this.feed, required this.cols, required this.onReset});

  @override
  Widget build(BuildContext context) {
    if (feed.items.isEmpty && feed.loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (feed.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 40),
        child: Column(children: [
          Text(s.t(feed.error != null ? 'home_error_loading' : 'mk_empty'),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, height: 1.4)),
          const SizedBox(height: 8),
          TextButton(onPressed: onReset, child: Text(s.t('route_clear'))),
        ]),
      );
    }
    const gap = 16.0;
    final rows = <Widget>[];
    for (var i = 0; i < feed.items.length; i += cols) {
      final chunk = feed.items.sublist(i, math.min(i + cols, feed.items.length));
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: gap),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: gap),
                Expanded(child: j < chunk.length ? MarketCard(key: ValueKey(chunk[j].id), l: chunk[j]) : const SizedBox()),
              ],
            ],
          ),
        ),
      ));
    }
    if (feed.loading) {
      rows.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
    }
    return Column(children: rows);
  }
}

/// Three VIP places one under the other (left or right of the ads).
class _VipColumn extends StatelessWidget {
  final AppStrings s;
  final List<MarketListing?> items;
  final String side;
  const _VipColumn({required this.s, required this.items, required this.side});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('desk-vip-$side'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(Icons.workspace_premium, color: kVipGold, size: 20),
          const SizedBox(width: 6),
          Text(s.t('mk_vip_ads'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text)),
        ]),
        const SizedBox(height: 10),
        for (final l in items) ...[
          AspectRatio(aspectRatio: 0.92, child: l == null ? _FreeVipPlace(s: s) : _VipPlace(l: l)),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _VipPlace extends StatelessWidget {
  final MarketListing l;
  const _VipPlace({required this.l});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      color: AppColors.card,
      child: InkWell(
        onTap: () => context.pushOnce('/market/l/${l.id}'),
        // Gold VIP frame over the whole picture (owner, 24.10.2026).
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              MarketPhoto(url: l.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xD9000000)],
                    stops: [0.4, 1],
                  ),
                ),
              ),
              const IgnorePointer(child: CustomPaint(painter: VipFramePainter(radius: 16))),
              Positioned(right: 6, top: 6, child: FavoriteHeart(id: l.id, size: 18)),
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text([l.brand, l.model].whereType<String>().join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    if (l.year != null) Text('${l.year}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    Text(marketPrice(l.price, l.currency),
                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 18)),
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

/// A VIP place nobody has taken: tells sellers how to get it (no fake ad).
class _FreeVipPlace extends StatelessWidget {
  final AppStrings s;
  const _FreeVipPlace({required this.s});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kVipGold.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => context.pushOnce('/market/mine'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.workspace_premium_outlined, size: 38, color: kVipGold.withValues(alpha: 0.85)),
            const SizedBox(height: 8),
            Text(s.t('mk_vip_free_title'),
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.text)),
            const SizedBox(height: 4),
            Text(s.t('mk_vip_free_body'),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textSoft, fontSize: 12.5, height: 1.3)),
          ]),
        ),
      ),
    );
  }
}

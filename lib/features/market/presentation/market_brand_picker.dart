import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/market_brand_index.dart';
import '../domain/market_brand_logos.dart';
import '../domain/market_catalog.dart';
import '../domain/market_models.dart';
import 'market_providers.dart';

/// What the TIR Bazarı search page returns: a brand (and model), or a
/// free text, or [cleared] (everything off).
class MarketSearchPick {
  final String? brand;
  final String? model;
  final String? text;
  final bool cleared;
  const MarketSearchPick({this.brand, this.model, this.text, this.cleared = false});
}

/// Opens the full-screen "Marka" page (owner, 24.10.2026, like the brand
/// list of big car markets). One tap on a brand picks it and goes back
/// (owner, 25.10.2026).
Future<MarketSearchPick?> openMarketSearch(BuildContext context, {required AppStrings s, required MarketFilter filter}) =>
    Navigator.of(context, rootNavigator: true).push<MarketSearchPick>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _BrandPage(s: s, filter: filter),
    ));

List<String> _catalogueBrands(MarketCategory? c) => c == null
    ? ({for (final x in MarketCategory.values) ...marketBrands(x)}.toList()..sort())
    : marketBrands(c);

/// Square on the left of a brand: its checked logo on a white plate (day
/// and night alike, owner 25.10.2026), otherwise the brand's letters.
class BrandBadge extends StatelessWidget {
  final String brand;
  /// 44 on the "Marka" page; smaller in the computer's brand list.
  final double size;
  const BrandBadge(this.brand, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final logo = marketBrandLogoAsset(brand);
    if (logo == null) return _letters();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size / 11),
      decoration: BoxDecoration(
        color: AppColors.logoPlate,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: AppColors.tileLine),
      ),
      child: Image.asset(logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _lettersText(AppColors.logoPlateText)),
    );
  }

  Widget _lettersText(Color color) {
    final t = brandInitials(brand);
    final k = size / 44;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(t, style: TextStyle(fontSize: (t.length > 2 ? 12.5 : 15) * k, fontWeight: FontWeight.w900, color: color)),
      ),
    );
  }

  Widget _letters() => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.tileBg,
          borderRadius: BorderRadius.circular(size * 0.18),
          border: Border.all(color: AppColors.tileLine),
        ),
        child: _lettersText(AppColors.tileFg),
      );
}

/// One row: badge, name, (count), selection circle.
class _PickRow extends StatelessWidget {
  final Widget leading;
  final String name;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _PickRow({super.key, required this.leading, required this.name, required this.count, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line.withValues(alpha: 0.6)))),
        child: Row(children: [
          leading,
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: TextStyle(fontSize: 17, color: AppColors.text)),
                if (count > 0) TextSpan(text: '  ($count)', style: TextStyle(fontSize: 16, color: AppColors.textSoft)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? AppColors.accent : AppColors.line, size: 26),
        ]),
      ),
    );
  }
}

/// Shared frame: ✕, big title, search field, then the list.
class _PickFrame extends StatelessWidget {
  final String title;
  final String hint;
  final ValueChanged<String> onQuery;
  final List<Widget> children;
  final Key fieldKey;
  const _PickFrame({required this.title, required this.hint, required this.onQuery, required this.children, required this.fieldKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: const ValueKey('mk-pick-close'),
                icon: Icon(Icons.close, size: 28, color: AppColors.textSoft),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 16),
            TextField(
              key: fieldKey,
              onChanged: onQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: Icon(Icons.search, color: AppColors.textSoft),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.line)),
                enabledBorder:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.line)),
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

Widget _section(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(text, style: TextStyle(fontSize: 15, color: AppColors.textSoft)),
    );

class _BrandPage extends ConsumerStatefulWidget {
  final AppStrings s;
  final MarketFilter filter;
  const _BrandPage({required this.s, required this.filter});

  @override
  ConsumerState<_BrandPage> createState() => _BrandPageState();
}

class _BrandPageState extends ConsumerState<_BrandPage> {
  String _q = '';

  /// One tap on a brand opens its models at once (owner, 25.10.2026);
  /// a brand without models is picked and the page goes back.
  Future<void> _pickBrand(String brand) async {
    final nav = Navigator.of(context);
    final index = ref.read(marketBrandIndexProvider(widget.filter.category)).valueOrNull ?? MarketBrandIndex.empty;
    if (index.models(brand, marketFilterModels(widget.filter.category, brand)).isEmpty) {
      nav.pop(MarketSearchPick(brand: brand));
      return;
    }
    final model = await nav.push<String>(MaterialPageRoute(
      builder: (_) => _ModelPage(s: widget.s, filter: widget.filter, brand: brand),
    ));
    if (!mounted || model == null) return; // back from Model: stay on Marka
    nav.pop(MarketSearchPick(brand: brand, model: model.isEmpty ? null : model));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final f = widget.filter;
    final index = ref.watch(marketBrandIndexProvider(f.category)).valueOrNull ?? MarketBrandIndex.empty;
    final typing = _q.trim().isNotEmpty;
    // Filtered with every letter typed; other spellings too ("мерседес"
    // finds Mercedes-Benz, "qazel" GAZ, "kogel" Kögel). Names that start
    // with the text come first, then the ones that contain it (A–Z).
    final popular = typing ? const <BrandCount>[] : index.popular();
    final all = [
      for (final b in index.all(_catalogueBrands(f.category)))
        if (marketBrandMatch(b.name, _q) case final rank?) (rank, b),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final current = f.brand?.toLowerCase();

    Widget row(BrandCount b, String keyPrefix) => _PickRow(
          key: ValueKey('$keyPrefix-${b.name}'),
          leading: BrandBadge(b.name),
          name: b.name,
          count: b.count,
          selected: current == b.name.toLowerCase(),
          onTap: () => _pickBrand(b.name),
        );

    return _PickFrame(
      title: s.t('mk_brand'),
      hint: s.t('mk_pick_brand_search'),
      fieldKey: const ValueKey('mk-pick-brand-field'),
      onQuery: (v) => setState(() => _q = v),
      children: [
        if (f.brand != null || f.model != null || (f.q ?? '').isNotEmpty)
          _PickRow(
            key: const ValueKey('mk-pick-clear'),
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.tileBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.apps, color: AppColors.textSoft),
            ),
            name: s.t('mk_all_brands'),
            count: 0,
            selected: false,
            onTap: () => Navigator.of(context).pop(const MarketSearchPick(cleared: true)),
          ),
        if (popular.isNotEmpty) ...[
          _section(s.t('mk_popular')),
          for (final b in popular) row(b, 'mk-pop'),
        ],
        if (all.isEmpty)
          Padding(
            key: const ValueKey('mk-brand-none'),
            padding: const EdgeInsets.only(top: 24),
            child: Center(child: Text(s.t('mk_brand_not_found'), style: TextStyle(fontSize: 16, color: AppColors.textSoft))),
          )
        else ...[
          _section(s.t('mk_all_brands')),
          for (final (_, b) in all) row(b, 'mk-brand'),
        ],
      ],
    );
  }
}

/// Models of the chosen brand: catalogue + models that have ads, with
/// their counts; "Bütün modellər" first. Filtered while typing.
class _ModelPage extends ConsumerStatefulWidget {
  final AppStrings s;
  final MarketFilter filter;
  final String brand;
  const _ModelPage({required this.s, required this.filter, required this.brand});

  @override
  ConsumerState<_ModelPage> createState() => _ModelPageState();
}

class _ModelPageState extends ConsumerState<_ModelPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final f = widget.filter;
    final index = ref.watch(marketBrandIndexProvider(f.category)).valueOrNull ?? MarketBrandIndex.empty;
    final q = marketSearchKey(_q.trim());
    final models = index
        .models(widget.brand, marketFilterModels(f.category, widget.brand))
        .where((m) => q.isEmpty || marketSearchKey(m.name).contains(q))
        .toList();
    final sameBrand = f.brand != null && canonicalMarketBrand(f.brand!) == canonicalMarketBrand(widget.brand);
    final current = sameBrand ? f.model?.toLowerCase() : null;

    return _PickFrame(
      title: widget.brand,
      hint: s.t('mk_pick_model_search'),
      fieldKey: const ValueKey('mk-pick-model-field'),
      onQuery: (v) => setState(() => _q = v),
      children: [
        if (q.isEmpty)
          _PickRow(
            key: const ValueKey('mk-model-all'),
            leading: BrandBadge(widget.brand),
            name: s.t('mk_all_models'),
            count: index.countOf(widget.brand),
            selected: sameBrand && current == null,
            onTap: () => Navigator.of(context).pop(''),
          ),
        _section(s.t('mk_model')),
        for (final m in models)
          _PickRow(
            key: ValueKey('mk-model-${m.name}'),
            leading: const SizedBox(width: 44),
            name: m.name,
            count: m.count,
            selected: current == m.name.toLowerCase(),
            onTap: () => Navigator.of(context).pop(m.name),
          ),
        if (models.isEmpty)
          Padding(
            key: const ValueKey('mk-model-none'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(s.t('mk_model_not_found'), style: TextStyle(fontSize: 16, color: AppColors.textSoft)),
          ),
      ],
    );
  }
}

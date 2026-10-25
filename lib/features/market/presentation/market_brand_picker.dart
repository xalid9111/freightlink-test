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
/// list of big car markets), then "Model" for the chosen brand.
Future<MarketSearchPick?> openMarketSearch(BuildContext context, {required AppStrings s, required MarketFilter filter}) =>
    Navigator.of(context, rootNavigator: true).push<MarketSearchPick>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _BrandPage(s: s, filter: filter),
    ));

List<String> _catalogueBrands(MarketCategory? c) => c == null
    ? ({for (final x in MarketCategory.values) ...marketBrands(x)}.toList()..sort())
    : marketBrands(c);

List<String> _catalogueModels(MarketCategory? c, String brand) => c == null
    ? {for (final x in MarketCategory.values) ...marketModels(x, brand)}.toList()
    : marketModels(c, brand);

/// Square on the left of a brand: its checked logo on a white plate (day
/// and night alike, owner 25.10.2026), otherwise the brand's letters.
class BrandBadge extends StatelessWidget {
  final String brand;
  const BrandBadge(this.brand, {super.key});

  @override
  Widget build(BuildContext context) {
    final logo = marketBrandLogoAsset(brand);
    if (logo == null) return _letters();
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.logoPlate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.tileLine),
      ),
      child: Image.asset(logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _lettersText(AppColors.logoPlateText)),
    );
  }

  Widget _lettersText(Color color) {
    final t = brandInitials(brand);
    return Center(
      child: Text(t, style: TextStyle(fontSize: t.length > 2 ? 12.5 : 15, fontWeight: FontWeight.w900, color: color)),
    );
  }

  Widget _letters() => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.tileBg,
          borderRadius: BorderRadius.circular(8),
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
            Text(title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.text)),
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

  Future<void> _pickBrand(String brand) async {
    final nav = Navigator.of(context);
    final model = await nav.push<String>(MaterialPageRoute(
      builder: (_) => _ModelPage(s: widget.s, filter: widget.filter, brand: brand),
    ));
    if (!mounted || model == null) return; // back from Model: stay here
    nav.pop(MarketSearchPick(brand: brand, model: model.isEmpty ? null : model));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final f = widget.filter;
    final index = ref.watch(marketBrandIndexProvider(f.category)).valueOrNull ?? MarketBrandIndex.empty;
    final q = _q.trim().toLowerCase();
    // Also other spellings: "мерседес" finds Mercedes-Benz, "qazel" GAZ.
    bool hit(BrandCount b) =>
        q.isEmpty || marketBrandSearchNames(b.name).any((n) => n.toLowerCase().contains(q));
    final popular = q.isEmpty ? index.popular() : const <BrandCount>[];
    final all = index.all(_catalogueBrands(f.category)).where(hit).toList();
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
        // Any text can still be searched (brand, model, city …), as before.
        if (_q.trim().isNotEmpty)
          _PickRow(
            key: const ValueKey('mk-pick-text'),
            leading: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.search, color: Colors.white),
            ),
            name: s.t('mk_search_for', {'q': _q.trim()}),
            count: 0,
            selected: false,
            onTap: () => Navigator.of(context).pop(MarketSearchPick(text: _q.trim())),
          ),
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
        _section(s.t('mk_all_brands')),
        for (final b in all) row(b, 'mk-brand'),
      ],
    );
  }
}

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
    final q = _q.trim().toLowerCase();
    final models = index
        .models(widget.brand, _catalogueModels(f.category, widget.brand))
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList();
    final sameBrand = f.brand?.toLowerCase() == widget.brand.toLowerCase();
    final current = sameBrand ? f.model?.toLowerCase() : null;

    return _PickFrame(
      title: widget.brand,
      hint: s.t('mk_pick_model_search'),
      fieldKey: const ValueKey('mk-pick-model-field'),
      onQuery: (v) => setState(() => _q = v),
      children: [
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
      ],
    );
  }
}

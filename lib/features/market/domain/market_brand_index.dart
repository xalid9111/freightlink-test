/// Brand / model lists for the TIR Bazarı search (owner, 24.10.2026, like
/// the "Marka" page of big car markets): popular brands first with their
/// real number of active ads, then every brand A–Z; then the models of
/// the chosen brand the same way. Counts come from the active ads only —
/// a brand without ads shows no number (never a made-up one).
class BrandCount {
  final String name;
  final int count;
  const BrandCount(this.name, this.count);
}

class MarketBrandIndex {
  /// lower-case brand → (shown name, ads).
  final Map<String, BrandCount> _brands;
  /// lower-case brand → lower-case model → (shown name, ads).
  final Map<String, Map<String, BrandCount>> _models;
  const MarketBrandIndex._(this._brands, this._models);

  static const empty = MarketBrandIndex._({}, {});

  /// From rows of active ads ({brand, model}); brand / model compared
  /// without case (as the server search does).
  factory MarketBrandIndex.fromRows(Iterable<Map<String, dynamic>> rows) {
    final brands = <String, BrandCount>{};
    final models = <String, Map<String, BrandCount>>{};
    for (final r in rows) {
      final b = '${r['brand'] ?? ''}'.trim();
      if (b.isEmpty) continue;
      final bk = b.toLowerCase();
      final prev = brands[bk];
      brands[bk] = BrandCount(prev?.name ?? b, (prev?.count ?? 0) + 1);
      final m = '${r['model'] ?? ''}'.trim();
      if (m.isEmpty) continue;
      final ms = models.putIfAbsent(bk, () => {});
      final mk = m.toLowerCase();
      final pm = ms[mk];
      ms[mk] = BrandCount(pm?.name ?? m, (pm?.count ?? 0) + 1);
    }
    return MarketBrandIndex._(brands, models);
  }

  int countOf(String brand) => _brands[brand.toLowerCase()]?.count ?? 0;

  /// Brands with the most ads, most first (ties A–Z).
  List<BrandCount> popular({int top = 10}) {
    final l = _brands.values.toList()
      ..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return l.take(top).toList();
  }

  /// [catalogue] brands plus every brand that has ads, A–Z, with counts.
  List<BrandCount> all(Iterable<String> catalogue) => _merge(catalogue, _brands);

  /// Models of [brand]: catalogue ones plus every model that has ads.
  List<BrandCount> models(String brand, Iterable<String> catalogue) =>
      _merge(catalogue, _models[brand.toLowerCase()] ?? const {});

  static List<BrandCount> _merge(Iterable<String> catalogue, Map<String, BrandCount> counted) {
    final out = <String, BrandCount>{};
    for (final c in catalogue) {
      out[c.toLowerCase()] = BrandCount(c, counted[c.toLowerCase()]?.count ?? 0);
    }
    counted.forEach((k, v) => out.putIfAbsent(k, () => v));
    return out.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

/// Letters on a brand's square (no logos: brand marks are not ours):
/// "DAF" → DAF, "Mercedes-Benz" → MB, "Schmitz Cargobull" → SC, "Volvo" → VO.
String brandInitials(String brand) {
  final b = brand.trim();
  if (b.isEmpty) return '?';
  final words = b.split(RegExp(r'[\s\-+]+')).where((w) => w.isNotEmpty).toList();
  if (words.length == 1) {
    final w = words.first;
    return (w.length <= 4 ? w : w.substring(0, 2)).toUpperCase();
  }
  return words.take(2).map((w) => w.substring(0, 1)).join().toUpperCase();
}

/// Brand logos on the TIR Bazarı "Marka" page (owner, 25.10.2026).
///
/// Only original logos whose source and terms of use were checked are
/// packaged (assets/images/brands/, list and sources in
/// docs/brand_logos.md). A brand without one keeps its letter square
/// (brandInitials) — no logo is drawn or guessed.
library;

import 'market_catalog.dart';

/// Catalogue brand → packaged logo file name (assets/images/brands/).
/// Empty until checked logos are added.
const Map<String, String> kMarketBrandLogos = {};

/// Asset path of [brand]'s logo (any spelling), or null.
String? marketBrandLogoAsset(String brand) {
  final file = kMarketBrandLogos[canonicalMarketBrand(brand)];
  return file == null ? null : 'assets/images/brands/$file';
}

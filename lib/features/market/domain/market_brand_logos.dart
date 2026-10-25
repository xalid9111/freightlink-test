/// Brand logos on the TIR Bazarı "Marka" page (owner, 25.10.2026).
///
/// Only original logos whose source and terms of use were checked are
/// packaged (assets/images/brands/, list and sources in
/// docs/brand_logos.md). A brand without one keeps its letter square
/// (brandInitials) — no logo is drawn or guessed.
library;

import 'market_catalog.dart';

/// Catalogue brand → packaged logo file name (assets/images/brands/).
/// Owner, 25.10.2026 (Mərhələ 3): 48 brand marks — Simple Icons, the open
/// car-logos-dataset and three supplied by the owner
/// (source and colour per brand in docs/brand_logos.md); a too light
/// brand colour is drawn in the brand's black version.
const Map<String, String> kMarketBrandLogos = {
  'Caterpillar': 'caterpillar.png',
  'Citroën': 'citroen.png',
  'DAF': 'daf.png',
  'Fiat': 'fiat.png',
  'Ford': 'ford.png',
  'Hitachi': 'hitachi.png',
  'Hyundai': 'hyundai.png',
  'Iveco': 'iveco.png',
  'JCB': 'jcb.png',
  'John Deere': 'johndeere.png',
  'Kia': 'kia.png',
  'MAN': 'man.png',
  'Nissan': 'nissan.png',
  'Opel': 'opel.png',
  'Peugeot': 'peugeot.png',
  'Renault': 'renault.png',
  'Scania': 'scania.png',
  'Tata': 'tata.png',
  'Toyota': 'toyota.png',
  'Volkswagen': 'volkswagen.png',
  // Mərhələ 3, second set: car-logos-dataset (carlogos.org) and the Volvo
  // iron mark (shared by Volvo Cars and Volvo Trucks).
  'Beiben': 'beiben.png',
  'CAMC': 'camc.png',
  'Dongfeng': 'dongfeng.png',
  'FAW': 'faw.png',
  'Foton': 'foton.png',
  'Freightliner': 'freightliner.png',
  'GAZ': 'gaz.png',
  'Hino': 'hino.png',
  'Hongyan': 'hongyan.png',
  'International': 'international.png',
  'Isuzu': 'isuzu.png',
  'JAC': 'jac.png',
  'JMC': 'jmc.png',
  'KAMAZ': 'kamaz.png',
  'Kenworth': 'kenworth.png',
  'Mack': 'mack.png',
  'MAZ': 'maz.png',
  'Mercedes-Benz': 'mercedes_benz.png',
  'Peterbilt': 'peterbilt.png',
  'Shacman': 'shacman.png',
  'Tatra': 'tatra.png',
  'UAZ': 'uaz.png',
  'UD Trucks': 'ud_trucks.png',
  'Western Star': 'western_star.png',
  'Volvo': 'volvo.png',
  // Supplied by the owner (25.10.2026).
  'Krone': 'krone.png',
  'Kögel': 'kogel.png',
  'Schmitz Cargobull': 'schmitz_cargobull.png',
};

/// Asset path of [brand]'s logo (any spelling), or null.
String? marketBrandLogoAsset(String brand) {
  final file = kMarketBrandLogos[canonicalMarketBrand(brand)];
  return file == null ? null : 'assets/images/brands/$file';
}

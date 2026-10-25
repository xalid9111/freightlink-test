// Brands and models offered in the "Satış elanı" form. Anything missing can
// be typed with "Digər" (other), so the list never blocks a seller.
//
// Owner, 25.10.2026 (Mərhələ 2): about 120 commercial vehicle brands —
// heavy TIR, medium and light trucks (Qazel, vans), trailers, construction
// and special machines. Every brand and model of the first list is kept
// as it was (stored ads use these names). Models are series, not guessed
// variants. Brand, model, category and body type are separate things:
// the body (tow truck, crane, reefer …) is MarketBodyType, not a model.
import 'market_models.dart';

const Map<MarketCategory, Map<String, List<String>>> kMarketCatalog = {
  MarketCategory.truck: {
    // Europe
    'DAF': ['XF 105', 'XF 106', 'XF 480', 'XF 530', 'XG', 'XG+', 'CF', 'LF', 'XF', 'XD'],
    'Mercedes-Benz': ['Actros', 'Actros 1845', 'Actros 1848', 'Actros 1851', 'Arocs', 'Atego', 'Axor', 'Actros L', 'Antos', 'eActros', 'Econic', 'Unimog', 'Zetros'],
    'Volvo': ['FH 460', 'FH 500', 'FH 540', 'FH16', 'FM', 'FMX', 'FH', 'FH Electric'],
    'Scania': ['R410', 'R450', 'R500', 'R540', 'S450', 'S500', 'G410', 'P410', 'R-series', 'S-series', 'G-series', 'P-series', 'L-series', '770 S'],
    'MAN': ['TGX 18.440', 'TGX 18.480', 'TGX 18.510', 'TGS', 'TGM', 'TGL', 'TGX'],
    'Iveco': ['S-Way', 'Stralis', 'Eurocargo', 'Trakker', 'X-Way', 'T-Way', 'S-eWay'],
    'Renault': ['T 460', 'T 480', 'T 520', 'C', 'K', 'D', 'T High', 'D Wide', 'Premium', 'Magnum', 'Kerax', 'Midlum'],
    'Ford Trucks': ['F-MAX', '1848T', 'Cargo', 'F-Line'],
    'Tatra': ['Phoenix', 'Force', 'Terra', 'T815', 'T158'],
    'BMC': ['Tuğra', 'Pro', 'Fatih'],
    // CIS
    'KAMAZ': ['5490', '54901', '6520', '65115', '43118', '65206', '6580', '5320', '5511', '53215', '4308'],
    'MAZ': ['5440', '6430', '6501', '5516', '5550', '6312', '6422', '5340'],
    'Ural': ['4320', '5557', '63704', 'Next'],
    'KrAZ': ['65055', '6322', '6510', '255'],
    'GAZ': ['Gazon Next', 'Sadko Next'],
    // China
    'Howo': ['T7H', 'A7', 'TX', 'TH7', 'NX', 'Max'],
    'Sitrak': ['C7H', 'G7', 'C5H'],
    'Shacman': ['X3000', 'F3000', 'X5000', 'X6000', 'H3000', 'M3000'],
    'FAW': ['J6P', 'J7', 'J6L', 'JH6'],
    'Dongfeng': ['KX', 'KL', 'KC', 'GX'],
    'Foton': ['Auman EST', 'Auman GTL', 'Auman ETX'],
    'JAC': ['K7', 'Gallop'],
    'Beiben': ['V3', 'NG80'],
    'Hongyan': ['Genlyon'],
    'CAMC': ['Hanma'],
    // Japan / Korea
    'Isuzu': ['F-Series', 'N-Series', 'Giga', 'Forward'],
    'Hino': ['300', '500', '700'],
    'Mitsubishi Fuso': ['Canter', 'Fighter', 'Super Great'],
    'UD Trucks': ['Quon', 'Croner', 'Quester'],
    'Hyundai': ['Xcient', 'HD', 'HD120', 'HD170', 'Pavise'],
    'Tata Daewoo': ['Novus', 'Prima', 'Maxen'],
    // India
    'Tata': ['Prima', 'Signa', 'Ultra', 'LPT'],
    'Ashok Leyland': ['Ecomet', 'Boss', 'Partner'],
    // North America
    'Freightliner': ['Cascadia', 'Columbia', 'Century', 'Coronado', 'M2'],
    'Kenworth': ['T680', 'T880', 'W900', 'T800'],
    'Peterbilt': ['579', '567', '389'],
    'International': ['LT', 'HV', 'Lonestar', 'ProStar'],
    'Mack': ['Anthem', 'Granite', 'Pinnacle'],
    'Western Star': ['49X', '47X', '5700'],
  },
  // 3.5–16 t (owner, 25.10.2026)
  MarketCategory.mediumTruck: {
    'Mercedes-Benz': ['Atego', 'Vario'],
    'MAN': ['TGL', 'TGM'],
    'DAF': ['LF', 'XB', 'XD'],
    'Volvo': ['FL', 'FE'],
    'Renault': ['D', 'Midlum'],
    'Iveco': ['Eurocargo'],
    'Isuzu': ['Forward', 'NQR', 'NPR'],
    'Hino': ['300', '500'],
    'Mitsubishi Fuso': ['Canter', 'Fighter'],
    'Hyundai': ['HD65', 'HD72', 'HD78', 'HD120', 'Mighty'],
    'KAMAZ': ['4308', '43253'],
    'MAZ': ['4371'],
    'GAZ': ['Gazon Next', 'Valdai', '3307', '3309'],
    'Foton': ['Aumark'],
    'JAC': ['N-series'],
  },
  // Up to 3.5 t: Qazel, vans, light trucks (owner, 25.10.2026)
  MarketCategory.lightTruck: {
    'GAZ': ['GAZelle Business', 'GAZelle Next', 'GAZelle NN', 'GAZelle City', 'Sobol', 'Sobol NN'],
    'Mercedes-Benz': ['Sprinter', 'Vito', 'Citan'],
    'Ford': ['Transit', 'Transit Custom', 'Transit Connect'],
    'Volkswagen': ['Crafter', 'Transporter', 'Caddy', 'LT'],
    'Iveco': ['Daily'],
    'Renault': ['Master', 'Trafic', 'Kangoo'],
    'Fiat': ['Ducato', 'Doblò', 'Fiorino', 'Talento'],
    'Peugeot': ['Boxer', 'Expert', 'Partner'],
    'Citroën': ['Jumper', 'Jumpy', 'Berlingo'],
    'Opel': ['Movano', 'Vivaro', 'Combo'],
    'Nissan': ['NV400', 'NV200', 'Cabstar', 'Interstar', 'Primastar'],
    'Toyota': ['Hiace', 'Dyna', 'Proace'],
    'Hyundai': ['Porter', 'H-1', 'H350', 'HD35'],
    'Kia': ['Bongo', 'K2500', 'K2700'],
    'Isuzu': ['Elf', 'NMR', 'NPR'],
    'Mitsubishi Fuso': ['Canter'],
    'Hino': ['Dutro'],
    'MAN': ['TGE'],
    'Foton': ['Ollin', 'View'],
    'JAC': ['Sunray', 'N-series'],
    'JMC': ['Carrying', 'Conquer'],
    'Dongfeng': ['Captain', 'Duolika'],
    'FAW': ['Tiger V'],
    'UAZ': ['Profi', '3303', '3909'],
  },
  MarketCategory.trailer: {
    'Schmitz Cargobull': ['S.KO', 'S.CS', 'Z.KO'],
    'Krone': ['Profi Liner', 'Cool Liner', 'Box Liner'],
    'Kögel': ['Cargo', 'Mega'],
    'Wielton': ['Curtainsider', 'Tipper'],
    'Tırsan': ['Kässbohrer', 'Tenteli', 'Frigo'],
    'Schwarzmüller': [],
    'Humbaur': [],
    'Fliegl': [],
    'Goldhofer': ['STZ', 'THP'],
    'Faymonville': ['MegaMAX', 'MultiMAX', 'VarioMAX'],
    'Nooteboom': ['MCO', 'OSD', 'Euro', 'Manoovr'],
    'Doll': [],
    'Broshuis': [],
    'Meusburger': [],
    'Langendorf': [],
    'Lohr': ['Eurolohr'],
    'Rolfo': [],
    'Tonar': [],
    'MAZ': [],
  },
  MarketCategory.semitrailer: {
    'Schmitz Cargobull': ['S.CS Mega', 'S.KO Cool', 'S.KI'],
    'Krone': ['SD Profi Liner', 'SD Cool Liner', 'SD Mega Liner'],
    'Kögel': ['Cargo', 'Mega', 'Port'],
    'Wielton': ['NS', 'NW', 'NK'],
    'Tırsan': ['Tenteli', 'Frigo', 'Lowbed'],
    'Kässbohrer': ['Lowbed', 'Tanker', 'Container'],
    'Chereau': ['Inogam', 'Frigo'],
    'Lamberet': ['SR2', 'Frigo'],
    'Fliegl': ['SDS', 'Lowbed'],
    'Schwarzmüller': [],
    'Goldhofer': ['STZ'],
    'Faymonville': ['MegaMAX', 'MultiMAX', 'VarioMAX'],
    'Nooteboom': ['MCO', 'OSD', 'Euro', 'Manoovr'],
    'Lohr': ['Eurolohr'],
    'Rolfo': [],
    'Feldbinder': [],
    'Spitzer': [],
    'Van Hool': [],
    'Fruehauf': [],
    'Lecitrailer': [],
    'Langendorf': [],
    'Meusburger': [],
    'Doll': [],
    'Broshuis': [],
    'Cometto': [],
    'Scheuerle': [],
    'Gray & Adams': [],
    'Özgül': [],
    'Serin': [],
    'Yeksan': [],
    'Tonar': [],
    'MAZ': [],
    'Nefaz': [],
    'CIMC': [],
    'Wabash': [],
    'Great Dane': [],
    'Utility': [],
    'Hyundai Translead': [],
  },
  MarketCategory.construction: {
    'Caterpillar': ['320', '330', '336', '950', '966', 'D6', 'D8'],
    'Komatsu': ['PC200', 'PC300', 'WA380', 'D65'],
    'JCB': ['3CX', '4CX', 'JS220', '540-170'],
    'Hitachi': ['ZX200', 'ZX350'],
    'Volvo CE': ['EC220', 'EC380', 'L120', 'A30G'],
    'Liebherr': ['R 924', 'R 936', 'L 566', 'LTM'],
    'Hyundai CE': ['R220', 'HX300', 'HL960'],
    'Doosan': ['DX225', 'DX300', 'DL420'],
    'XCMG': ['XE215', 'ZL50', 'QY25'],
    'SANY': ['SY215C', 'SY365H', 'SY75C', 'STC250'],
    'Zoomlion': ['ZE215E', 'ZTC250'],
    'LiuGong': ['856H', '922F', '835H'],
    'Shantui': ['SD16', 'SD22', 'SD32'],
    'SDLG': ['L956F', 'L958F'],
    'Case': ['580ST', '695ST', 'CX210'],
    'New Holland': ['B110', 'B115'],
    'John Deere': ['310L', '210G', '644L'],
    'Bobcat': ['S510', 'S650', 'E35', 'T770'],
    'Kubota': ['KX057', 'KX080', 'U55'],
    'Takeuchi': ['TB216', 'TB290'],
    'Yanmar': ['ViO17', 'ViO57'],
    'Kobelco': ['SK140', 'SK210', 'SK350'],
    'Terex': ['TA300'],
    'Manitou': ['MT', 'MRT', 'MLT'],
    'Merlo': ['Panoramic', 'Roto', 'Turbofarmer'],
    'JLG': ['600S', '860SJ'],
    'Genie': ['S-65', 'Z-45', 'GS-1930'],
    'Tadano': ['ATF', 'GR'],
    'Grove': ['GMK', 'RT'],
    'Palfinger': ['PK'],
    'Hiab': ['X-HiPro', 'X-CLX', 'iX'],
    'Fassi': ['F'],
    'Effer': [],
    'Unic': ['URV'],
    'Soosan': ['SCS'],
    'Kanglim': ['KS'],
    'Wirtgen': ['W 100', 'W 210'],
    'Bomag': ['BW 120', 'BW 213'],
    'Hamm': ['HD', 'H'],
    'Dynapac': ['CA', 'CC'],
    'Putzmeister': ['M'],
    'Schwing': ['S'],
    'BELAZ': ['7540', '7555', '75131'],
    'Hidromek': ['HMK 102B', 'HMK 220LC'],
    'MST': ['M 542', 'M 544'],
    'Mecalac': [],
    'Sennebogen': [],
    'Atlas': [],
  },
  MarketCategory.other: {},
};

/// Other spellings of a brand (owner, 25.10.2026): ads typed this way are
/// counted and found under the catalogue name. Stored ads never change.
const Map<String, List<String>> kMarketBrandAliases = {
  'Mercedes-Benz': ['Mercedes', 'MB', 'Mersedes', 'Merc', 'Мерседес', 'Мерседес-Бенц'],
  'Volkswagen': ['VW', 'Фольксваген'],
  'GAZ': ['ГАЗ', 'Qazel', 'Gazel', 'Gazelle', 'Газель'],
  'KAMAZ': ['КАМАЗ', 'Камаз'],
  'MAZ': ['МАЗ'],
  'Ural': ['УРАЛ', 'Урал'],
  'KrAZ': ['КрАЗ'],
  'UAZ': ['УАЗ'],
  'Howo': ['Sinotruk', 'Sinotruk Howo', 'Sino Truk', 'Хово'],
  'Shacman': ['Shaanxi', 'Shaanxi Shacman', 'Shacman Shaanxi', 'Шакман'],
  'FAW': ['Jiefang', 'FAW Jiefang', 'ФАВ'],
  'Renault': ['Renault Trucks', 'Рено'],
  'Ford Trucks': ['Ford Otosan'],
  'Ford': ['Форд'],
  'Mitsubishi Fuso': ['Fuso', 'Mitsubishi', 'Мицубиси'],
  'Caterpillar': ['CAT'],
  'Doosan': ['Develon'],
  'Hyundai CE': ['Hyundai Construction Equipment', 'HD Hyundai CE'],
  'Volvo CE': ['Volvo Construction Equipment'],
  'Citroën': ['Citroen', 'Ситроен'],
  'Kögel': ['Kogel', 'Koegel'],
  'Tırsan': ['Tirsan'],
  'Kässbohrer': ['Kassbohrer', 'Kaessbohrer'],
  'Schmitz Cargobull': ['Schmitz', 'Шмитц'],
  'Schwarzmüller': ['Schwarzmuller', 'Schwarzmueller'],
  'Chereau': ['Chéreau'],
  'Scania': ['Скания', 'Skania'],
  'Volvo': ['Вольво'],
  'DAF': ['Даф'],
  'MAN': ['МАН'],
  'Iveco': ['Ивеко'],
  'Hyundai': ['Хендай', 'Хёндай', 'Hyundai Trucks'],
  'Isuzu': ['Исузу'],
  'Hino': ['Хино'],
  'Toyota': ['Тойота'],
  'Nissan': ['Ниссан'],
  'Peugeot': ['Пежо'],
  'Fiat': ['Фиат'],
  'Opel': ['Опель'],
  'Kia': ['Киа'],
  'BELAZ': ['БелАЗ'],
  'Tonar': ['Тонар'],
  'Nefaz': ['НефАЗ'],
  'Tata Daewoo': ['Daewoo Trucks', 'Daewoo'],
  'Hidromek': ['Hidromak'],
};

/// Other spellings of a model, per catalogue brand (the comparison also
/// ignores letter case, spaces, "-", "." and "/": "FH-16" = "FH16").
const Map<String, Map<String, List<String>>> kMarketModelAliases = {
  'GAZ': {
    'GAZelle Next': ['Gazelle Next', 'Qazel Next', 'Газель Next', 'Газель Некст'],
    'GAZelle Business': ['Gazelle Business', 'Qazel Biznes', 'Газель Бизнес'],
    'GAZelle NN': ['Газель NN'],
    'GAZelle City': ['Газель City', 'Газель Сити'],
    'Sobol': ['Соболь'],
    'Sobol NN': ['Соболь NN'],
    'Gazon Next': ['Газон Next', 'Газон Некст'],
    'Sadko Next': ['Садко Next'],
    'Valdai': ['Валдай'],
  },
  'Mercedes-Benz': {'Actros': ['Aktros', 'Актрос'], 'Sprinter': ['Спринтер']},
  'Ford': {'Transit': ['Транзит']},
  'Hyundai': {'Porter': ['Портер']},
  'Ural': {'Next': ['Некст']},
};

String _fold(String s) => s.trim().replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();

/// Key for comparing two spellings: no case, spaces or punctuation.
String marketNameKey(String s) => _fold(s).replaceAll(RegExp(r'[\s\-./_]+'), '');

final Map<String, String> _brandByKey = () {
  final m = <String, String>{};
  for (final cat in kMarketCatalog.values) {
    for (final b in cat.keys) {
      m[marketNameKey(b)] = b;
    }
  }
  kMarketBrandAliases.forEach((brand, aliases) {
    for (final a in aliases) {
      m.putIfAbsent(marketNameKey(a), () => brand);
    }
  });
  return m;
}();

/// The catalogue name of a typed brand ("mercedes" → Mercedes-Benz,
/// "КАМАЗ" → KAMAZ); an unknown brand comes back as typed (trimmed).
String canonicalMarketBrand(String brand) => _brandByKey[marketNameKey(brand)] ?? brand.trim();

/// The catalogue name of a typed model of [brand] ("FH-16" → FH16,
/// "Газель Next" → GAZelle Next); unknown → as typed.
String canonicalMarketModel(String brand, String model) {
  final b = canonicalMarketBrand(brand);
  final k = marketNameKey(model);
  for (final cat in kMarketCatalog.values) {
    for (final m in cat[b] ?? const <String>[]) {
      if (marketNameKey(m) == k) return m;
    }
  }
  for (final e in (kMarketModelAliases[b] ?? const <String, List<String>>{}).entries) {
    if (e.value.any((a) => marketNameKey(a) == k)) return e.key;
  }
  return model.trim();
}

/// Every spelling that means [brand] (catalogue name + aliases) — sent to
/// the server search (0064) so ads typed another way are found too.
List<String> marketBrandSpellings(String brand) {
  final b = canonicalMarketBrand(brand);
  return {b, brand.trim(), ...?kMarketBrandAliases[b]}.toList();
}

/// Every spelling of [model] of [brand].
List<String> marketModelSpellings(String brand, String model) {
  final b = canonicalMarketBrand(brand);
  final m = canonicalMarketModel(b, model);
  return {m, model.trim(), ...?kMarketModelAliases[b]?[m]}.toList();
}

/// Search words of a brand for the "Marka" page (name + aliases).
List<String> marketBrandSearchNames(String brand) => [brand, ...?kMarketBrandAliases[brand]];

/// Typed text folded for the "Marka" search (owner, 25.10.2026): no
/// letter case, spaces or punctuation, and Azerbaijani / Turkish letters
/// read as plain Latin ("Kögel" = "kogel", "Tırsan" = "tirsan").
String marketSearchKey(String s) {
  const map = {'ə': 'e', 'ı': 'i', 'ö': 'o', 'ü': 'u', 'ş': 's', 'ç': 'c', 'ğ': 'g', 'ä': 'a', 'é': 'e', 'ë': 'e', 'ò': 'o'};
  final lower = s.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(map[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[\s\-./_&+]+'), '');
}

/// 0 = a name or other spelling starts with [query], 1 = contains it,
/// null = no match. Empty query matches everything.
int? marketBrandMatch(String brand, String query) {
  final q = marketSearchKey(query);
  if (q.isEmpty) return 0;
  var best = -1;
  for (final n in marketBrandSearchNames(brand)) {
    final k = marketSearchKey(n);
    if (k.startsWith(q)) return 0;
    if (k.contains(q)) best = 1;
  }
  return best < 0 ? null : best;
}

/// Brands of a category (alphabetical).
/// Popular brands on top of the filter, with their logos (owner,
/// 25.10.2026): tractors first, then semitrailers.
const kMarketPopularBrands = [
  'Mercedes-Benz', 'DAF', 'Scania', 'Volvo', 'MAN', 'Renault', 'Iveco', 'KAMAZ', //
  'Schmitz Cargobull', 'Krone', 'Kögel', 'MAZ',
];

List<String> marketBrands(MarketCategory c) => (kMarketCatalog[c]?.keys.toList() ?? <String>[])..sort();

/// Models of a brand in a category.
List<String> marketModels(MarketCategory c, String? brand) => [...?kMarketCatalog[c]?[brand]];

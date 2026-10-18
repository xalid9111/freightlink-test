// Brands and models offered in the "Satış elanı" form. Anything missing can
// be typed with "Digər" (other), so the list never blocks a seller.
import 'market_models.dart';

const Map<MarketCategory, Map<String, List<String>>> kMarketCatalog = {
  MarketCategory.truck: {
    'DAF': ['XF 105', 'XF 106', 'XF 480', 'XF 530', 'XG', 'XG+', 'CF', 'LF'],
    'Mercedes-Benz': ['Actros', 'Actros 1845', 'Actros 1848', 'Actros 1851', 'Arocs', 'Atego', 'Axor'],
    'Volvo': ['FH 460', 'FH 500', 'FH 540', 'FH16', 'FM', 'FMX'],
    'Scania': ['R410', 'R450', 'R500', 'R540', 'S450', 'S500', 'G410', 'P410'],
    'MAN': ['TGX 18.440', 'TGX 18.480', 'TGX 18.510', 'TGS', 'TGM', 'TGL'],
    'Iveco': ['S-Way', 'Stralis', 'Eurocargo', 'Trakker', 'X-Way'],
    'Renault': ['T 460', 'T 480', 'T 520', 'C', 'K', 'D'],
    'Ford Trucks': ['F-MAX', '1848T', 'Cargo'],
    'KAMAZ': ['5490', '54901', '6520', '65115', '43118'],
    'MAZ': ['5440', '6430', '6501'],
    'Isuzu': ['F-Series', 'N-Series', 'Giga'],
    'Hyundai': ['Xcient', 'HD'],
    'Shacman': ['X3000', 'F3000'],
    'Howo': ['T7H', 'A7', 'TX'],
    'FAW': ['J6P', 'J7'],
  },
  MarketCategory.trailer: {
    'Schmitz Cargobull': ['S.KO', 'S.CS', 'Z.KO'],
    'Krone': ['Profi Liner', 'Cool Liner', 'Box Liner'],
    'Kögel': ['Cargo', 'Mega'],
    'Wielton': ['Curtainsider', 'Tipper'],
    'Tırsan': ['Kässbohrer', 'Tenteli', 'Frigo'],
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
  },
  MarketCategory.other: {},
};

/// Brands of a category (alphabetical).
List<String> marketBrands(MarketCategory c) => (kMarketCatalog[c]?.keys.toList() ?? <String>[])..sort();

/// Models of a brand in a category.
List<String> marketModels(MarketCategory c, String? brand) => [...?kMarketCatalog[c]?[brand]];

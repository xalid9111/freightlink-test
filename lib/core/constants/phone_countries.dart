import 'countries.dart';

/// One country for the phone-number field: ISO 3166-1 alpha-2 code,
/// international calling code (without "+") and English name.
///
/// The phone country only builds the international number (+994 …). It
/// never limits the app language — any language can be used with any
/// country.
class PhoneCountry {
  final String iso;
  final String dial;
  final String en;
  const PhoneCountry(this.iso, this.dial, this.en);

  /// Regional-indicator flag emoji built from the ISO code.
  String get flag => String.fromCharCodes(iso.codeUnits.map((c) => 0x1F1E6 + c - 0x41));

  /// Name in the UI language: the app's own translations for the main
  /// freight countries (Countries.all), English for the rest.
  String name(String languageCode) => Countries.find(iso)?.name(languageCode) ?? en;

  /// Every spelling the search box should match: all known names, the ISO
  /// code and the calling code (with and without "+").
  List<String> get searchTerms {
    final c = Countries.find(iso);
    return [
      en,
      iso,
      dial,
      '+$dial',
      if (c != null) ...[c.en, c.az, c.tr, c.ru, if (countryNamesZh[iso] != null) countryNamesZh[iso]!],
    ];
  }
}

class PhoneCountries {
  PhoneCountries._();

  static const String defaultIso = 'AZ';

  static PhoneCountry? byIso(String? iso) {
    if (iso == null) return null;
    final u = iso.toUpperCase();
    for (final c in all) {
      if (c.iso == u) return c;
    }
    return null;
  }

  /// Splits an international number ("+994501234567") into its country
  /// (longest matching calling code; Azerbaijan preferred on ties) and
  /// the national digits. Returns null when nothing matches.
  static ({PhoneCountry country, String national})? split(String? e164) {
    final digits = (e164 ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    PhoneCountry? best;
    for (final c in ordered) {
      if (digits.startsWith(c.dial) && (best == null || c.dial.length > best.dial.length)) best = c;
    }
    if (best == null) return null;
    // Shared codes (+1, +7, +44 …): keep the first listed country.
    return (country: best, national: digits.substring(best.dial.length));
  }

  /// Main freight countries first (same order as the cargo pickers), then
  /// the rest of the world alphabetically.
  static List<PhoneCountry> get ordered {
    final main = <PhoneCountry>[];
    for (final c in Countries.all) {
      final p = byIso(c.code);
      if (p != null) main.add(p);
    }
    final rest = all.where((p) => !main.contains(p)).toList()..sort((a, b) => a.en.compareTo(b.en));
    return [...main, ...rest];
  }

  static const List<PhoneCountry> all = [
    PhoneCountry('AZ', '994', 'Azerbaijan'),
    PhoneCountry('AF', '93', 'Afghanistan'),
    PhoneCountry('AL', '355', 'Albania'),
    PhoneCountry('DZ', '213', 'Algeria'),
    PhoneCountry('AS', '1684', 'American Samoa'),
    PhoneCountry('AD', '376', 'Andorra'),
    PhoneCountry('AO', '244', 'Angola'),
    PhoneCountry('AI', '1264', 'Anguilla'),
    PhoneCountry('AG', '1268', 'Antigua and Barbuda'),
    PhoneCountry('AR', '54', 'Argentina'),
    PhoneCountry('AM', '374', 'Armenia'),
    PhoneCountry('AW', '297', 'Aruba'),
    PhoneCountry('AU', '61', 'Australia'),
    PhoneCountry('AT', '43', 'Austria'),
    PhoneCountry('BS', '1242', 'Bahamas'),
    PhoneCountry('BH', '973', 'Bahrain'),
    PhoneCountry('BD', '880', 'Bangladesh'),
    PhoneCountry('BB', '1246', 'Barbados'),
    PhoneCountry('BY', '375', 'Belarus'),
    PhoneCountry('BE', '32', 'Belgium'),
    PhoneCountry('BZ', '501', 'Belize'),
    PhoneCountry('BJ', '229', 'Benin'),
    PhoneCountry('BM', '1441', 'Bermuda'),
    PhoneCountry('BT', '975', 'Bhutan'),
    PhoneCountry('BO', '591', 'Bolivia'),
    PhoneCountry('BA', '387', 'Bosnia and Herzegovina'),
    PhoneCountry('BW', '267', 'Botswana'),
    PhoneCountry('BR', '55', 'Brazil'),
    PhoneCountry('BN', '673', 'Brunei'),
    PhoneCountry('BG', '359', 'Bulgaria'),
    PhoneCountry('BF', '226', 'Burkina Faso'),
    PhoneCountry('BI', '257', 'Burundi'),
    PhoneCountry('KH', '855', 'Cambodia'),
    PhoneCountry('CM', '237', 'Cameroon'),
    PhoneCountry('CA', '1', 'Canada'),
    PhoneCountry('CV', '238', 'Cape Verde'),
    PhoneCountry('KY', '1345', 'Cayman Islands'),
    PhoneCountry('CF', '236', 'Central African Republic'),
    PhoneCountry('TD', '235', 'Chad'),
    PhoneCountry('CL', '56', 'Chile'),
    PhoneCountry('CN', '86', 'China'),
    PhoneCountry('CO', '57', 'Colombia'),
    PhoneCountry('KM', '269', 'Comoros'),
    PhoneCountry('CG', '242', 'Congo'),
    PhoneCountry('CD', '243', 'Congo (DR)'),
    PhoneCountry('CR', '506', 'Costa Rica'),
    PhoneCountry('CI', '225', "Côte d'Ivoire"),
    PhoneCountry('HR', '385', 'Croatia'),
    PhoneCountry('CU', '53', 'Cuba'),
    PhoneCountry('CY', '357', 'Cyprus'),
    PhoneCountry('CZ', '420', 'Czechia'),
    PhoneCountry('DK', '45', 'Denmark'),
    PhoneCountry('DJ', '253', 'Djibouti'),
    PhoneCountry('DM', '1767', 'Dominica'),
    PhoneCountry('DO', '1809', 'Dominican Republic'),
    PhoneCountry('EC', '593', 'Ecuador'),
    PhoneCountry('EG', '20', 'Egypt'),
    PhoneCountry('SV', '503', 'El Salvador'),
    PhoneCountry('GQ', '240', 'Equatorial Guinea'),
    PhoneCountry('ER', '291', 'Eritrea'),
    PhoneCountry('EE', '372', 'Estonia'),
    PhoneCountry('SZ', '268', 'Eswatini'),
    PhoneCountry('ET', '251', 'Ethiopia'),
    PhoneCountry('FO', '298', 'Faroe Islands'),
    PhoneCountry('FJ', '679', 'Fiji'),
    PhoneCountry('FI', '358', 'Finland'),
    PhoneCountry('FR', '33', 'France'),
    PhoneCountry('GF', '594', 'French Guiana'),
    PhoneCountry('PF', '689', 'French Polynesia'),
    PhoneCountry('GA', '241', 'Gabon'),
    PhoneCountry('GM', '220', 'Gambia'),
    PhoneCountry('GE', '995', 'Georgia'),
    PhoneCountry('DE', '49', 'Germany'),
    PhoneCountry('GH', '233', 'Ghana'),
    PhoneCountry('GI', '350', 'Gibraltar'),
    PhoneCountry('GR', '30', 'Greece'),
    PhoneCountry('GL', '299', 'Greenland'),
    PhoneCountry('GD', '1473', 'Grenada'),
    PhoneCountry('GP', '590', 'Guadeloupe'),
    PhoneCountry('GU', '1671', 'Guam'),
    PhoneCountry('GT', '502', 'Guatemala'),
    PhoneCountry('GN', '224', 'Guinea'),
    PhoneCountry('GW', '245', 'Guinea-Bissau'),
    PhoneCountry('GY', '592', 'Guyana'),
    PhoneCountry('HT', '509', 'Haiti'),
    PhoneCountry('HN', '504', 'Honduras'),
    PhoneCountry('HK', '852', 'Hong Kong'),
    PhoneCountry('HU', '36', 'Hungary'),
    PhoneCountry('IS', '354', 'Iceland'),
    PhoneCountry('IN', '91', 'India'),
    PhoneCountry('ID', '62', 'Indonesia'),
    PhoneCountry('IR', '98', 'Iran'),
    PhoneCountry('IQ', '964', 'Iraq'),
    PhoneCountry('IE', '353', 'Ireland'),
    PhoneCountry('IL', '972', 'Israel'),
    PhoneCountry('IT', '39', 'Italy'),
    PhoneCountry('JM', '1876', 'Jamaica'),
    PhoneCountry('JP', '81', 'Japan'),
    PhoneCountry('JO', '962', 'Jordan'),
    PhoneCountry('KZ', '7', 'Kazakhstan'),
    PhoneCountry('KE', '254', 'Kenya'),
    PhoneCountry('KI', '686', 'Kiribati'),
    PhoneCountry('XK', '383', 'Kosovo'),
    PhoneCountry('KW', '965', 'Kuwait'),
    PhoneCountry('KG', '996', 'Kyrgyzstan'),
    PhoneCountry('LA', '856', 'Laos'),
    PhoneCountry('LV', '371', 'Latvia'),
    PhoneCountry('LB', '961', 'Lebanon'),
    PhoneCountry('LS', '266', 'Lesotho'),
    PhoneCountry('LR', '231', 'Liberia'),
    PhoneCountry('LY', '218', 'Libya'),
    PhoneCountry('LI', '423', 'Liechtenstein'),
    PhoneCountry('LT', '370', 'Lithuania'),
    PhoneCountry('LU', '352', 'Luxembourg'),
    PhoneCountry('MO', '853', 'Macao'),
    PhoneCountry('MG', '261', 'Madagascar'),
    PhoneCountry('MW', '265', 'Malawi'),
    PhoneCountry('MY', '60', 'Malaysia'),
    PhoneCountry('MV', '960', 'Maldives'),
    PhoneCountry('ML', '223', 'Mali'),
    PhoneCountry('MT', '356', 'Malta'),
    PhoneCountry('MH', '692', 'Marshall Islands'),
    PhoneCountry('MQ', '596', 'Martinique'),
    PhoneCountry('MR', '222', 'Mauritania'),
    PhoneCountry('MU', '230', 'Mauritius'),
    PhoneCountry('MX', '52', 'Mexico'),
    PhoneCountry('FM', '691', 'Micronesia'),
    PhoneCountry('MD', '373', 'Moldova'),
    PhoneCountry('MC', '377', 'Monaco'),
    PhoneCountry('MN', '976', 'Mongolia'),
    PhoneCountry('ME', '382', 'Montenegro'),
    PhoneCountry('MS', '1664', 'Montserrat'),
    PhoneCountry('MA', '212', 'Morocco'),
    PhoneCountry('MZ', '258', 'Mozambique'),
    PhoneCountry('MM', '95', 'Myanmar'),
    PhoneCountry('NA', '264', 'Namibia'),
    PhoneCountry('NR', '674', 'Nauru'),
    PhoneCountry('NP', '977', 'Nepal'),
    PhoneCountry('NL', '31', 'Netherlands'),
    PhoneCountry('NC', '687', 'New Caledonia'),
    PhoneCountry('NZ', '64', 'New Zealand'),
    PhoneCountry('NI', '505', 'Nicaragua'),
    PhoneCountry('NE', '227', 'Niger'),
    PhoneCountry('NG', '234', 'Nigeria'),
    PhoneCountry('KP', '850', 'North Korea'),
    PhoneCountry('MK', '389', 'North Macedonia'),
    PhoneCountry('NO', '47', 'Norway'),
    PhoneCountry('OM', '968', 'Oman'),
    PhoneCountry('PK', '92', 'Pakistan'),
    PhoneCountry('PW', '680', 'Palau'),
    PhoneCountry('PS', '970', 'Palestine'),
    PhoneCountry('PA', '507', 'Panama'),
    PhoneCountry('PG', '675', 'Papua New Guinea'),
    PhoneCountry('PY', '595', 'Paraguay'),
    PhoneCountry('PE', '51', 'Peru'),
    PhoneCountry('PH', '63', 'Philippines'),
    PhoneCountry('PL', '48', 'Poland'),
    PhoneCountry('PT', '351', 'Portugal'),
    PhoneCountry('PR', '1787', 'Puerto Rico'),
    PhoneCountry('QA', '974', 'Qatar'),
    PhoneCountry('RE', '262', 'Réunion'),
    PhoneCountry('RO', '40', 'Romania'),
    PhoneCountry('RU', '7', 'Russia'),
    PhoneCountry('RW', '250', 'Rwanda'),
    PhoneCountry('KN', '1869', 'Saint Kitts and Nevis'),
    PhoneCountry('LC', '1758', 'Saint Lucia'),
    PhoneCountry('VC', '1784', 'Saint Vincent and the Grenadines'),
    PhoneCountry('WS', '685', 'Samoa'),
    PhoneCountry('SM', '378', 'San Marino'),
    PhoneCountry('ST', '239', 'São Tomé and Príncipe'),
    PhoneCountry('SA', '966', 'Saudi Arabia'),
    PhoneCountry('SN', '221', 'Senegal'),
    PhoneCountry('RS', '381', 'Serbia'),
    PhoneCountry('SC', '248', 'Seychelles'),
    PhoneCountry('SL', '232', 'Sierra Leone'),
    PhoneCountry('SG', '65', 'Singapore'),
    PhoneCountry('SK', '421', 'Slovakia'),
    PhoneCountry('SI', '386', 'Slovenia'),
    PhoneCountry('SB', '677', 'Solomon Islands'),
    PhoneCountry('SO', '252', 'Somalia'),
    PhoneCountry('ZA', '27', 'South Africa'),
    PhoneCountry('KR', '82', 'South Korea'),
    PhoneCountry('SS', '211', 'South Sudan'),
    PhoneCountry('ES', '34', 'Spain'),
    PhoneCountry('LK', '94', 'Sri Lanka'),
    PhoneCountry('SD', '249', 'Sudan'),
    PhoneCountry('SR', '597', 'Suriname'),
    PhoneCountry('SE', '46', 'Sweden'),
    PhoneCountry('CH', '41', 'Switzerland'),
    PhoneCountry('SY', '963', 'Syria'),
    PhoneCountry('TW', '886', 'Taiwan'),
    PhoneCountry('TJ', '992', 'Tajikistan'),
    PhoneCountry('TZ', '255', 'Tanzania'),
    PhoneCountry('TH', '66', 'Thailand'),
    PhoneCountry('TL', '670', 'Timor-Leste'),
    PhoneCountry('TG', '228', 'Togo'),
    PhoneCountry('TO', '676', 'Tonga'),
    PhoneCountry('TT', '1868', 'Trinidad and Tobago'),
    PhoneCountry('TN', '216', 'Tunisia'),
    PhoneCountry('TR', '90', 'Türkiye'),
    PhoneCountry('TM', '993', 'Turkmenistan'),
    PhoneCountry('TC', '1649', 'Turks and Caicos Islands'),
    PhoneCountry('TV', '688', 'Tuvalu'),
    PhoneCountry('UG', '256', 'Uganda'),
    PhoneCountry('UA', '380', 'Ukraine'),
    PhoneCountry('AE', '971', 'United Arab Emirates'),
    PhoneCountry('GB', '44', 'United Kingdom'),
    PhoneCountry('US', '1', 'United States'),
    PhoneCountry('UY', '598', 'Uruguay'),
    PhoneCountry('UZ', '998', 'Uzbekistan'),
    PhoneCountry('VU', '678', 'Vanuatu'),
    PhoneCountry('VA', '379', 'Vatican City'),
    PhoneCountry('VE', '58', 'Venezuela'),
    PhoneCountry('VN', '84', 'Vietnam'),
    PhoneCountry('VG', '1284', 'British Virgin Islands'),
    PhoneCountry('VI', '1340', 'U.S. Virgin Islands'),
    PhoneCountry('YE', '967', 'Yemen'),
    PhoneCountry('ZM', '260', 'Zambia'),
    PhoneCountry('ZW', '263', 'Zimbabwe'),
  ];
}

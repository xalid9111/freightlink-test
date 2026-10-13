/// Countries offered by the cargo-create picker, with flag emoji and
/// names in every supported UI language.
///
/// STORAGE: new cargo stores the country's English name ([Country.en])
/// in cargo.pickup_country / destination_country — one canonical value
/// regardless of the poster's UI language, so exact-match search works
/// across languages. The column stays plain text (no migration).
///
/// DISPLAY: [Countries.find] also recognizes older free-text values
/// ("AZERBAYCAN", "Gürcüstan", "Russia", ...) in any of the four
/// languages, case- and diacritic-insensitively, so existing rows get a
/// flag and a localized name too. Unknown text is shown unchanged.
class Country {
  final String code; // ISO 3166-1 alpha-2
  final String en;
  final String az;
  final String tr;
  final String ru;
  const Country(this.code, this.en, this.az, this.tr, this.ru);

  /// Regional-indicator flag emoji built from the ISO code.
  String get flag => String.fromCharCodes(code.codeUnits.map((c) => 0x1F1E6 + c - 0x41));

  String name(String languageCode) => switch (languageCode) {
        'az' => az,
        'tr' => tr,
        'ru' => ru,
        'zh' => countryNamesZh[code] ?? en,
        _ => en,
      };
}

/// Simplified-Chinese country names (zh-CN UI); others fall back to English.
const Map<String, String> countryNamesZh = {
  'AZ': '阿塞拜疆',
  'GE': '格鲁吉亚',
  'TR': '土耳其',
  'RU': '俄罗斯',
  'KZ': '哈萨克斯坦',
  'UZ': '乌兹别克斯坦',
  'TM': '土库曼斯坦',
  'KG': '吉尔吉斯斯坦',
  'TJ': '塔吉克斯坦',
  'IR': '伊朗',
  'UA': '乌克兰',
  'BY': '白俄罗斯',
  'MD': '摩尔多瓦',
  'AM': '亚美尼亚',
  'IQ': '伊拉克',
  'AF': '阿富汗',
  'PK': '巴基斯坦',
  'CN': '中国',
  'IN': '印度',
  'AE': '阿联酋',
  'SA': '沙特阿拉伯',
  'DE': '德国',
  'PL': '波兰',
  'LT': '立陶宛',
  'LV': '拉脱维亚',
  'EE': '爱沙尼亚',
  'FI': '芬兰',
  'NL': '荷兰',
  'BE': '比利时',
  'FR': '法国',
  'IT': '意大利',
  'ES': '西班牙',
  'AT': '奥地利',
  'CH': '瑞士',
  'CZ': '捷克',
  'SK': '斯洛伐克',
  'HU': '匈牙利',
  'RO': '罗马尼亚',
  'BG': '保加利亚',
  'GR': '希腊',
  'RS': '塞尔维亚',
  'SE': '瑞典',
  'GB': '英国',
};

class Countries {
  Countries._();

  /// Order = picker order: the region's main freight partners first.
  static const List<Country> all = [
    Country('AZ', 'Azerbaijan', 'Azərbaycan', 'Azerbaycan', 'Азербайджан'),
    Country('GE', 'Georgia', 'Gürcüstan', 'Gürcistan', 'Грузия'),
    Country('TR', 'Türkiye', 'Türkiyə', 'Türkiye', 'Турция'),
    Country('RU', 'Russia', 'Rusiya', 'Rusya', 'Россия'),
    Country('KZ', 'Kazakhstan', 'Qazaxıstan', 'Kazakistan', 'Казахстан'),
    Country('UZ', 'Uzbekistan', 'Özbəkistan', 'Özbekistan', 'Узбекистан'),
    Country('TM', 'Turkmenistan', 'Türkmənistan', 'Türkmenistan', 'Туркменистан'),
    Country('KG', 'Kyrgyzstan', 'Qırğızıstan', 'Kırgızistan', 'Киргизия'),
    Country('TJ', 'Tajikistan', 'Tacikistan', 'Tacikistan', 'Таджикистан'),
    Country('IR', 'Iran', 'İran', 'İran', 'Иран'),
    Country('UA', 'Ukraine', 'Ukrayna', 'Ukrayna', 'Украина'),
    Country('BY', 'Belarus', 'Belarus', 'Belarus', 'Беларусь'),
    Country('MD', 'Moldova', 'Moldova', 'Moldova', 'Молдова'),
    Country('AM', 'Armenia', 'Ermənistan', 'Ermenistan', 'Армения'),
    Country('IQ', 'Iraq', 'İraq', 'Irak', 'Ирак'),
    Country('AF', 'Afghanistan', 'Əfqanıstan', 'Afganistan', 'Афганистан'),
    Country('PK', 'Pakistan', 'Pakistan', 'Pakistan', 'Пакистан'),
    Country('CN', 'China', 'Çin', 'Çin', 'Китай'),
    Country('IN', 'India', 'Hindistan', 'Hindistan', 'Индия'),
    Country('AE', 'United Arab Emirates', 'Birləşmiş Ərəb Əmirlikləri', 'Birleşik Arap Emirlikleri', 'ОАЭ'),
    Country('SA', 'Saudi Arabia', 'Səudiyyə Ərəbistanı', 'Suudi Arabistan', 'Саудовская Аравия'),
    Country('DE', 'Germany', 'Almaniya', 'Almanya', 'Германия'),
    Country('PL', 'Poland', 'Polşa', 'Polonya', 'Польша'),
    Country('LT', 'Lithuania', 'Litva', 'Litvanya', 'Литва'),
    Country('LV', 'Latvia', 'Latviya', 'Letonya', 'Латвия'),
    Country('EE', 'Estonia', 'Estoniya', 'Estonya', 'Эстония'),
    Country('FI', 'Finland', 'Finlandiya', 'Finlandiya', 'Финляндия'),
    Country('NL', 'Netherlands', 'Niderland', 'Hollanda', 'Нидерланды'),
    Country('BE', 'Belgium', 'Belçika', 'Belçika', 'Бельгия'),
    Country('FR', 'France', 'Fransa', 'Fransa', 'Франция'),
    Country('IT', 'Italy', 'İtaliya', 'İtalya', 'Италия'),
    Country('ES', 'Spain', 'İspaniya', 'İspanya', 'Испания'),
    Country('AT', 'Austria', 'Avstriya', 'Avusturya', 'Австрия'),
    Country('CH', 'Switzerland', 'İsveçrə', 'İsviçre', 'Швейцария'),
    Country('CZ', 'Czechia', 'Çexiya', 'Çekya', 'Чехия'),
    Country('SK', 'Slovakia', 'Slovakiya', 'Slovakya', 'Словакия'),
    Country('HU', 'Hungary', 'Macarıstan', 'Macaristan', 'Венгрия'),
    Country('RO', 'Romania', 'Rumıniya', 'Romanya', 'Румыния'),
    Country('BG', 'Bulgaria', 'Bolqarıstan', 'Bulgaristan', 'Болгария'),
    Country('GR', 'Greece', 'Yunanıstan', 'Yunanistan', 'Греция'),
    Country('RS', 'Serbia', 'Serbiya', 'Sırbistan', 'Сербия'),
    Country('SE', 'Sweden', 'İsveç', 'İsveç', 'Швеция'),
    Country('GB', 'United Kingdom', 'Böyük Britaniya', 'Birleşik Krallık', 'Великобритания'),
  ];

  /// Extra spellings people commonly type that aren't one of the four
  /// official names above.
  static const Map<String, String> _aliases = {
    'turkey': 'TR',
    'turkiye': 'TR',
    'turkiya': 'TR',
    'uae': 'AE',
    'bae': 'AE',
    'uk': 'GB',
    'england': 'GB',
    'ingiltere': 'GB',
    'ingiltera': 'GB',
    'kirgizstan': 'KG',
    'kyrgyzstan': 'KG',
    'czech republic': 'CZ',
    'holland': 'NL',
    'rf': 'RU',
  };

  /// Lower-cases and folds Turkish/Azerbaijani letters to ASCII so
  /// "AZƏRBAYCAN", "Azerbaycan" and "azərbaycan" all compare equal.
  static String normalize(String input) {
    var s = input.trim().replaceAll('İ', 'i').toLowerCase();
    s = s.replaceAll('\u0307', ''); // stray combining dot above
    const fold = {
      'ə': 'e', 'ı': 'i', 'ö': 'o', 'ü': 'u', 'ş': 's', 'ç': 'c', 'ğ': 'g',
      'â': 'a', 'î': 'i', 'û': 'u', 'ё': 'е',
    };
    final b = StringBuffer();
    for (final ch in s.split('')) {
      b.write(fold[ch] ?? ch);
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static final Map<String, Country> _index = () {
    final byCode = {for (final c in all) c.code: c};
    final m = <String, Country>{};
    for (final c in all) {
      for (final n in [c.en, c.az, c.tr, c.ru, c.code, if (countryNamesZh[c.code] != null) countryNamesZh[c.code]!]) {
        m[normalize(n)] = c;
      }
    }
    _aliases.forEach((alias, code) => m[normalize(alias)] = byCode[code]!);
    return m;
  }();

  /// The country a stored/typed value refers to, or null if unknown.
  static Country? find(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _index[normalize(value)];
  }

  /// Flag + localized name for display ("🇦🇿 Azərbaycan"); unknown
  /// values are returned unchanged (no flag). [upperCase] is for the
  /// headline style used on cargo cards/detail.
  static String label(String value, String languageCode, {bool upperCase = false}) {
    final c = find(value);
    if (c == null) return upperCase ? value.toUpperCase() : value;
    final name = c.name(languageCode);
    return '${c.flag} ${upperCase ? name.toUpperCase() : name}';
  }

  /// Value to query the database with: the canonical English name when
  /// the text is a recognized country, otherwise the text as typed.
  static String canonical(String value) => find(value)?.en ?? value.trim();
}

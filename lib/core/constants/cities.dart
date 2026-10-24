import 'countries.dart';

/// Freight cities offered by the city picker, with the country they
/// belong to (ISO code) and names in every UI language.
///
/// STORAGE: a picked city is saved in cargo.pickup_city /
/// destination_city as its English name ([City.en]) — one value for all
/// languages (and the best input for map geocoding). [Cities.label]
/// shows it in the reader's language; any other stored text (older,
/// hand-typed cities) is shown unchanged.
class City {
  final String country; // ISO code, see Countries.all
  final String en;
  final String az;
  final String tr;
  final String ru;
  const City(this.country, this.en, this.az, this.tr, this.ru);

  String name(String languageCode) => switch (languageCode) {
        'az' => az,
        'tr' => tr,
        'ru' => ru,
        _ => en,
      };

  Country? get countryInfo => Countries.find(country);
}

class Cities {
  Cities._();

  /// Shown as quick picks before the user types.
  static const List<String> popular = [
    'Baku', 'Moscow', 'Istanbul', 'Tbilisi', 'Almaty', 'Tashkent', 'Ganja', 'Sumqayit',
    'Ankara', 'Mersin', 'Saint Petersburg', 'Astana', 'Ashgabat', 'Tehran', 'Minsk', 'Poti',
  ];

  static const List<City> all = [
    // Azerbaijan
    City('AZ', 'Baku', 'Bakı', 'Bakü', 'Баку'),
    City('AZ', 'Ganja', 'Gəncə', 'Gence', 'Гянджа'),
    City('AZ', 'Sumqayit', 'Sumqayıt', 'Sumgayıt', 'Сумгаит'),
    City('AZ', 'Mingachevir', 'Mingəçevir', 'Mingeçevir', 'Мингечевир'),
    City('AZ', 'Lankaran', 'Lənkəran', 'Lenkeran', 'Ленкорань'),
    City('AZ', 'Shirvan', 'Şirvan', 'Şirvan', 'Ширван'),
    City('AZ', 'Nakhchivan', 'Naxçıvan', 'Nahçıvan', 'Нахичевань'),
    City('AZ', 'Shaki', 'Şəki', 'Şeki', 'Шеки'),
    City('AZ', 'Yevlakh', 'Yevlax', 'Yevlah', 'Евлах'),
    City('AZ', 'Quba', 'Quba', 'Kuba', 'Губа'),
    City('AZ', 'Khachmaz', 'Xaçmaz', 'Haçmaz', 'Хачмаз'),
    City('AZ', 'Shamakhi', 'Şamaxı', 'Şamahı', 'Шемаха'),
    City('AZ', 'Barda', 'Bərdə', 'Berde', 'Барда'),
    City('AZ', 'Agdam', 'Ağdam', 'Ağdam', 'Агдам'),
    City('AZ', 'Shusha', 'Şuşa', 'Şuşa', 'Шуша'),
    City('AZ', 'Khankendi', 'Xankəndi', 'Hankendi', 'Ханкенди'),
    City('AZ', 'Zaqatala', 'Zaqatala', 'Zakatala', 'Закаталы'),
    City('AZ', 'Qazakh', 'Qazax', 'Kazah', 'Газах'),
    City('AZ', 'Alat', 'Ələt', 'Elet', 'Алят'),
    City('AZ', 'Astara', 'Astara', 'Astara', 'Астара'),
    City('AZ', 'Jalilabad', 'Cəlilabad', 'Celilabad', 'Джалилабад'),
    City('AZ', 'Sabirabad', 'Sabirabad', 'Sabirabad', 'Сабирабад'),
    City('AZ', 'Imishli', 'İmişli', 'İmişli', 'Имишли'),
    City('AZ', 'Tovuz', 'Tovuz', 'Tovuz', 'Товуз'),
    City('AZ', 'Shamkir', 'Şəmkir', 'Şemkir', 'Шамкир'),
    // Azerbaijan — the other districts (rayonlar), owner 24.10.2026:
    // the route search lists every city and district of a country.
    City('AZ', 'Absheron', 'Abşeron', 'Abşeron', 'Апшерон'),
    City('AZ', 'Khirdalan', 'Xırdalan', 'Hırdalan', 'Хырдалан'),
    City('AZ', 'Aghjabadi', 'Ağcabədi', 'Ağcabedi', 'Агджабеди'),
    City('AZ', 'Agdash', 'Ağdaş', 'Ağdaş', 'Агдаш'),
    City('AZ', 'Agstafa', 'Ağstafa', 'Ağstafa', 'Агстафа'),
    City('AZ', 'Agsu', 'Ağsu', 'Ağsu', 'Агсу'),
    City('AZ', 'Babek', 'Babək', 'Babek', 'Бабек'),
    City('AZ', 'Balakan', 'Balakən', 'Balaken', 'Балакен'),
    City('AZ', 'Beylagan', 'Beyləqan', 'Beylegan', 'Бейляган'),
    City('AZ', 'Bilasuvar', 'Biləsuvar', 'Bilesuvar', 'Билясувар'),
    City('AZ', 'Jabrayil', 'Cəbrayıl', 'Cebrail', 'Джебраил'),
    City('AZ', 'Julfa', 'Culfa', 'Culfa', 'Джульфа'),
    City('AZ', 'Dashkasan', 'Daşkəsən', 'Daşkesen', 'Дашкесан'),
    City('AZ', 'Fuzuli', 'Füzuli', 'Füzuli', 'Физули'),
    City('AZ', 'Gadabay', 'Gədəbəy', 'Gedebey', 'Гедабек'),
    City('AZ', 'Goranboy', 'Goranboy', 'Goranboy', 'Геранбой'),
    City('AZ', 'Goychay', 'Göyçay', 'Göyçay', 'Гёйчай'),
    City('AZ', 'Goygol', 'Göygöl', 'Göygöl', 'Гёйгёль'),
    City('AZ', 'Hajigabul', 'Hacıqabul', 'Hacıkabul', 'Гаджигабул'),
    City('AZ', 'Khizi', 'Xızı', 'Hızı', 'Хызы'),
    City('AZ', 'Khojaly', 'Xocalı', 'Hocalı', 'Ходжалы'),
    City('AZ', 'Khojavend', 'Xocavənd', 'Hocavend', 'Ходжавенд'),
    City('AZ', 'Ismayilli', 'İsmayıllı', 'İsmayıllı', 'Исмаиллы'),
    City('AZ', 'Kalbajar', 'Kəlbəcər', 'Kelbecer', 'Кельбаджар'),
    City('AZ', 'Kurdamir', 'Kürdəmir', 'Kürdemir', 'Кюрдамир'),
    City('AZ', 'Lachin', 'Laçın', 'Laçın', 'Лачин'),
    City('AZ', 'Lerik', 'Lerik', 'Lerik', 'Лерик'),
    City('AZ', 'Masally', 'Masallı', 'Masallı', 'Масаллы'),
    City('AZ', 'Naftalan', 'Naftalan', 'Naftalan', 'Нафталан'),
    City('AZ', 'Neftchala', 'Neftçala', 'Neftçala', 'Нефтечала'),
    City('AZ', 'Oghuz', 'Oğuz', 'Oğuz', 'Огуз'),
    City('AZ', 'Ordubad', 'Ordubad', 'Ordubad', 'Ордубад'),
    City('AZ', 'Gabala', 'Qəbələ', 'Kebele', 'Габала'),
    City('AZ', 'Gakh', 'Qax', 'Kah', 'Гах'),
    City('AZ', 'Gobustan', 'Qobustan', 'Gobustan', 'Гобустан'),
    City('AZ', 'Gubadly', 'Qubadlı', 'Kubadlı', 'Губадлы'),
    City('AZ', 'Gusar', 'Qusar', 'Kusar', 'Гусар'),
    City('AZ', 'Saatly', 'Saatlı', 'Saatlı', 'Саатлы'),
    City('AZ', 'Salyan', 'Salyan', 'Salyan', 'Сальяны'),
    City('AZ', 'Samukh', 'Samux', 'Samuh', 'Самух'),
    City('AZ', 'Shabran', 'Şabran', 'Şabran', 'Шабран'),
    City('AZ', 'Shahbuz', 'Şahbuz', 'Şahbuz', 'Шахбуз'),
    City('AZ', 'Sharur', 'Şərur', 'Şerur', 'Шарур'),
    City('AZ', 'Siyazan', 'Siyəzən', 'Siyezen', 'Сиазань'),
    City('AZ', 'Tartar', 'Tərtər', 'Terter', 'Тертер'),
    City('AZ', 'Ujar', 'Ucar', 'Ucar', 'Уджар'),
    City('AZ', 'Yardimli', 'Yardımlı', 'Yardımlı', 'Ярдымлы'),
    City('AZ', 'Zangilan', 'Zəngilan', 'Zengilan', 'Зангилан'),
    City('AZ', 'Zardab', 'Zərdab', 'Zerdab', 'Зардаб'),
    City('AZ', 'Kangarli', 'Kəngərli', 'Kengerli', 'Кенгерли'),
    City('AZ', 'Sadarak', 'Sədərək', 'Sederek', 'Садарак'),
    // Georgia
    City('GE', 'Tbilisi', 'Tbilisi', 'Tiflis', 'Тбилиси'),
    City('GE', 'Batumi', 'Batumi', 'Batum', 'Батуми'),
    City('GE', 'Poti', 'Poti', 'Poti', 'Поти'),
    City('GE', 'Kutaisi', 'Kutaisi', 'Kutaisi', 'Кутаиси'),
    City('GE', 'Rustavi', 'Rustavi', 'Rustavi', 'Рустави'),
    City('GE', 'Marneuli', 'Marneuli', 'Marneuli', 'Марнеули'),
    // Türkiye
    City('TR', 'Istanbul', 'İstanbul', 'İstanbul', 'Стамбул'),
    City('TR', 'Ankara', 'Ankara', 'Ankara', 'Анкара'),
    City('TR', 'Izmir', 'İzmir', 'İzmir', 'Измир'),
    City('TR', 'Mersin', 'Mersin', 'Mersin', 'Мерсин'),
    City('TR', 'Bursa', 'Bursa', 'Bursa', 'Бурса'),
    City('TR', 'Antalya', 'Antalya', 'Antalya', 'Анталья'),
    City('TR', 'Gaziantep', 'Qaziantep', 'Gaziantep', 'Газиантеп'),
    City('TR', 'Kocaeli', 'Kocaeli', 'Kocaeli', 'Коджаэли'),
    City('TR', 'Konya', 'Konya', 'Konya', 'Конья'),
    City('TR', 'Kayseri', 'Kayseri', 'Kayseri', 'Кайсери'),
    City('TR', 'Trabzon', 'Trabzon', 'Trabzon', 'Трабзон'),
    City('TR', 'Samsun', 'Samsun', 'Samsun', 'Самсун'),
    City('TR', 'Erzurum', 'Ərzurum', 'Erzurum', 'Эрзурум'),
    City('TR', 'Kars', 'Qars', 'Kars', 'Карс'),
    City('TR', 'Igdir', 'İğdır', 'Iğdır', 'Ыгдыр'),
    City('TR', 'Adana', 'Adana', 'Adana', 'Адана'),
    City('TR', 'Denizli', 'Denizli', 'Denizli', 'Денизли'),
    // Russia
    City('RU', 'Moscow', 'Moskva', 'Moskova', 'Москва'),
    City('RU', 'Saint Petersburg', 'Sankt-Peterburq', 'Sankt-Peterburg', 'Санкт-Петербург'),
    City('RU', 'Kazan', 'Kazan', 'Kazan', 'Казань'),
    City('RU', 'Novosibirsk', 'Novosibirsk', 'Novosibirsk', 'Новосибирск'),
    City('RU', 'Yekaterinburg', 'Yekaterinburq', 'Yekaterinburg', 'Екатеринбург'),
    City('RU', 'Nizhny Novgorod', 'Nijni Novqorod', 'Nijniy Novgorod', 'Нижний Новгород'),
    City('RU', 'Samara', 'Samara', 'Samara', 'Самара'),
    City('RU', 'Rostov-on-Don', 'Rostov-na-Donu', 'Rostov-na-Donu', 'Ростов-на-Дону'),
    City('RU', 'Krasnodar', 'Krasnodar', 'Krasnodar', 'Краснодар'),
    City('RU', 'Volgograd', 'Volqoqrad', 'Volgograd', 'Волгоград'),
    City('RU', 'Astrakhan', 'Həştərxan', 'Astrahan', 'Астрахань'),
    City('RU', 'Makhachkala', 'Mahaçqala', 'Mahaçkale', 'Махачкала'),
    City('RU', 'Derbent', 'Dərbənd', 'Derbent', 'Дербент'),
    City('RU', 'Grozny', 'Qroznı', 'Grozni', 'Грозный'),
    City('RU', 'Vladikavkaz', 'Vladiqafqaz', 'Vladikavkaz', 'Владикавказ'),
    City('RU', 'Stavropol', 'Stavropol', 'Stavropol', 'Ставрополь'),
    City('RU', 'Novorossiysk', 'Novorossiysk', 'Novorossiysk', 'Новороссийск'),
    City('RU', 'Voronezh', 'Voronej', 'Voronej', 'Воронеж'),
    City('RU', 'Saratov', 'Saratov', 'Saratov', 'Саратов'),
    City('RU', 'Ufa', 'Ufa', 'Ufa', 'Уфа'),
    City('RU', 'Chelyabinsk', 'Çelyabinsk', 'Çelyabinsk', 'Челябинск'),
    City('RU', 'Omsk', 'Omsk', 'Omsk', 'Омск'),
    City('RU', 'Perm', 'Perm', 'Perm', 'Пермь'),
    City('RU', 'Krasnoyarsk', 'Krasnoyarsk', 'Krasnoyarsk', 'Красноярск'),
    City('RU', 'Tyumen', 'Tümen', 'Tümen', 'Тюмень'),
    City('RU', 'Kaliningrad', 'Kaliningrad', 'Kaliningrad', 'Калининград'),
    City('RU', 'Vladivostok', 'Vladivostok', 'Vladivostok', 'Владивосток'),
    // Kazakhstan
    City('KZ', 'Almaty', 'Almatı', 'Almatı', 'Алматы'),
    City('KZ', 'Astana', 'Astana', 'Astana', 'Астана'),
    City('KZ', 'Shymkent', 'Şımkent', 'Çimkent', 'Шымкент'),
    City('KZ', 'Aktau', 'Aktau', 'Aktav', 'Актау'),
    City('KZ', 'Atyrau', 'Atırau', 'Atırav', 'Атырау'),
    City('KZ', 'Karaganda', 'Qaraqanda', 'Karaganda', 'Караганда'),
    City('KZ', 'Aktobe', 'Aktöbe', 'Aktöbe', 'Актобе'),
    City('KZ', 'Kostanay', 'Kostanay', 'Kostanay', 'Костанай'),
    City('KZ', 'Pavlodar', 'Pavlodar', 'Pavlodar', 'Павлодар'),
    // Uzbekistan
    City('UZ', 'Tashkent', 'Daşkənd', 'Taşkent', 'Ташкент'),
    City('UZ', 'Samarkand', 'Səmərqənd', 'Semerkant', 'Самарканд'),
    City('UZ', 'Bukhara', 'Buxara', 'Buhara', 'Бухара'),
    City('UZ', 'Andijan', 'Əndican', 'Andican', 'Андижан'),
    City('UZ', 'Namangan', 'Namanqan', 'Namangan', 'Наманган'),
    City('UZ', 'Fergana', 'Fərqanə', 'Fergana', 'Фергана'),
    City('UZ', 'Nukus', 'Nukus', 'Nukus', 'Нукус'),
    // Turkmenistan
    City('TM', 'Ashgabat', 'Aşqabad', 'Aşkabat', 'Ашхабад'),
    City('TM', 'Turkmenbashi', 'Türkmənbaşı', 'Türkmenbaşı', 'Туркменбаши'),
    City('TM', 'Mary', 'Mari', 'Mari', 'Мары'),
    City('TM', 'Turkmenabat', 'Türkmənabad', 'Türkmenabat', 'Туркменабад'),
    // Kyrgyzstan / Tajikistan
    City('KG', 'Bishkek', 'Bişkek', 'Bişkek', 'Бишкек'),
    City('KG', 'Osh', 'Oş', 'Oş', 'Ош'),
    City('TJ', 'Dushanbe', 'Düşənbə', 'Duşanbe', 'Душанбе'),
    City('TJ', 'Khujand', 'Xocənd', 'Hucend', 'Худжанд'),
    // Iran
    City('IR', 'Tehran', 'Tehran', 'Tahran', 'Тегеран'),
    City('IR', 'Tabriz', 'Təbriz', 'Tebriz', 'Тебриз'),
    City('IR', 'Ardabil', 'Ərdəbil', 'Erdebil', 'Ардебиль'),
    City('IR', 'Mashhad', 'Məşhəd', 'Meşhed', 'Мешхед'),
    City('IR', 'Bandar Abbas', 'Bəndər Abbas', 'Bender Abbas', 'Бендер-Аббас'),
    City('IR', 'Isfahan', 'İsfahan', 'İsfahan', 'Исфахан'),
    City('IR', 'Astara (Iran)', 'Astara (İran)', 'Astara (İran)', 'Астара (Иран)'),
    // Ukraine / Belarus / Moldova / Armenia
    City('UA', 'Kyiv', 'Kiyev', 'Kiev', 'Киев'),
    City('UA', 'Odesa', 'Odessa', 'Odessa', 'Одесса'),
    City('UA', 'Lviv', 'Lvov', 'Lviv', 'Львов'),
    City('UA', 'Kharkiv', 'Xarkov', 'Harkov', 'Харьков'),
    City('BY', 'Minsk', 'Minsk', 'Minsk', 'Минск'),
    City('BY', 'Brest', 'Brest', 'Brest', 'Брест'),
    City('BY', 'Gomel', 'Qomel', 'Gomel', 'Гомель'),
    City('MD', 'Chisinau', 'Kişinyov', 'Kişinev', 'Кишинёв'),
    City('AM', 'Yerevan', 'İrəvan', 'Erivan', 'Ереван'),
    // Middle East / Asia
    City('IQ', 'Baghdad', 'Bağdad', 'Bağdat', 'Багдад'),
    City('IQ', 'Erbil', 'Ərbil', 'Erbil', 'Эрбиль'),
    City('AF', 'Kabul', 'Kabil', 'Kabil', 'Кабул'),
    City('PK', 'Karachi', 'Karaçi', 'Karaçi', 'Карачи'),
    City('CN', 'Urumqi', 'Urumçi', 'Urumçi', 'Урумчи'),
    City('CN', 'Shanghai', 'Şanxay', 'Şanghay', 'Шанхай'),
    City('CN', 'Beijing', 'Pekin', 'Pekin', 'Пекин'),
    City('CN', 'Guangzhou', 'Quançjou', 'Guangzhou', 'Гуанчжоу'),
    City('CN', 'Khorgos', 'Xorqos', 'Horgos', 'Хоргос'),
    City('IN', 'Mumbai', 'Mumbay', 'Mumbai', 'Мумбаи'),
    City('IN', 'Delhi', 'Dehli', 'Delhi', 'Дели'),
    City('AE', 'Dubai', 'Dubay', 'Dubai', 'Дубай'),
    City('AE', 'Abu Dhabi', 'Əbu-Dabi', 'Abu Dabi', 'Абу-Даби'),
    City('AE', 'Jebel Ali', 'Cəbəl Əli', 'Cebel Ali', 'Джебель-Али'),
    City('SA', 'Riyadh', 'Ər-Riyad', 'Riyad', 'Эр-Рияд'),
    City('SA', 'Jeddah', 'Ciddə', 'Cidde', 'Джидда'),
    // Europe
    City('DE', 'Berlin', 'Berlin', 'Berlin', 'Берлин'),
    City('DE', 'Hamburg', 'Hamburq', 'Hamburg', 'Гамбург'),
    City('DE', 'Munich', 'Münhen', 'Münih', 'Мюнхен'),
    City('DE', 'Frankfurt', 'Frankfurt', 'Frankfurt', 'Франкфурт'),
    City('DE', 'Cologne', 'Köln', 'Köln', 'Кёльн'),
    City('PL', 'Warsaw', 'Varşava', 'Varşova', 'Варшава'),
    City('PL', 'Lodz', 'Lodz', 'Lodz', 'Лодзь'),
    City('PL', 'Gdansk', 'Qdansk', 'Gdansk', 'Гданьск'),
    City('PL', 'Poznan', 'Poznan', 'Poznan', 'Познань'),
    City('LT', 'Vilnius', 'Vilnüs', 'Vilnius', 'Вильнюс'),
    City('LT', 'Kaunas', 'Kaunas', 'Kaunas', 'Каунас'),
    City('LT', 'Klaipeda', 'Klaypeda', 'Klaipeda', 'Клайпеда'),
    City('LV', 'Riga', 'Riqa', 'Riga', 'Рига'),
    City('EE', 'Tallinn', 'Tallin', 'Tallinn', 'Таллин'),
    City('FI', 'Helsinki', 'Helsinki', 'Helsinki', 'Хельсинки'),
    City('NL', 'Rotterdam', 'Rotterdam', 'Rotterdam', 'Роттердам'),
    City('NL', 'Amsterdam', 'Amsterdam', 'Amsterdam', 'Амстердам'),
    City('BE', 'Antwerp', 'Antverpen', 'Anvers', 'Антверпен'),
    City('BE', 'Brussels', 'Brüssel', 'Brüksel', 'Брюссель'),
    City('FR', 'Paris', 'Paris', 'Paris', 'Париж'),
    City('FR', 'Lyon', 'Lion', 'Lyon', 'Лион'),
    City('FR', 'Marseille', 'Marsel', 'Marsilya', 'Марсель'),
    City('IT', 'Milan', 'Milan', 'Milano', 'Милан'),
    City('IT', 'Rome', 'Roma', 'Roma', 'Рим'),
    City('IT', 'Genoa', 'Genuya', 'Cenova', 'Генуя'),
    City('ES', 'Madrid', 'Madrid', 'Madrid', 'Мадрид'),
    City('ES', 'Barcelona', 'Barselona', 'Barselona', 'Барселона'),
    City('ES', 'Valencia', 'Valensiya', 'Valensiya', 'Валенсия'),
    City('AT', 'Vienna', 'Vyana', 'Viyana', 'Вена'),
    City('CH', 'Zurich', 'Sürix', 'Zürih', 'Цюрих'),
    City('CZ', 'Prague', 'Praqa', 'Prag', 'Прага'),
    City('SK', 'Bratislava', 'Bratislava', 'Bratislava', 'Братислава'),
    City('HU', 'Budapest', 'Budapeşt', 'Budapeşte', 'Будапешт'),
    City('RO', 'Bucharest', 'Buxarest', 'Bükreş', 'Бухарест'),
    City('RO', 'Constanta', 'Konstansa', 'Köstence', 'Констанца'),
    City('BG', 'Sofia', 'Sofiya', 'Sofya', 'София'),
    City('BG', 'Varna', 'Varna', 'Varna', 'Варна'),
    City('BG', 'Burgas', 'Burqas', 'Burgaz', 'Бургас'),
    City('GR', 'Athens', 'Afina', 'Atina', 'Афины'),
    City('GR', 'Thessaloniki', 'Saloniki', 'Selanik', 'Салоники'),
    City('RS', 'Belgrade', 'Belqrad', 'Belgrad', 'Белград'),
    City('SE', 'Stockholm', 'Stokholm', 'Stokholm', 'Стокгольм'),
    City('GB', 'London', 'London', 'Londra', 'Лондон'),
  ];

  static final Map<String, City> _index = () {
    final m = <String, City>{};
    for (final c in all) {
      for (final n in [c.en, c.az, c.tr, c.ru]) {
        m.putIfAbsent(Countries.normalize(n), () => c);
      }
    }
    return m;
  }();

  /// The catalogue city a stored/typed value refers to, or null.
  static City? find(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return _index[Countries.normalize(value)];
  }

  /// City name in [languageCode]; unknown (hand-typed) values unchanged.
  static String label(String value, String languageCode) => find(value)?.name(languageCode) ?? value;

  static List<City> get popularCities => [for (final n in popular) if (find(n) != null) find(n)!];

  /// Catalogue cities whose name (any language) or country name
  /// contains [query]; names that START with it come first.
  static List<City> search(String query, {int limit = 30}) {
    final q = Countries.normalize(query);
    if (q.isEmpty) return popularCities;
    final starts = <City>[];
    final contains = <City>[];
    for (final c in all) {
      final names = [c.en, c.az, c.tr, c.ru].map(Countries.normalize);
      if (names.any((n) => n.startsWith(q))) {
        starts.add(c);
      } else if (names.any((n) => n.contains(q))) {
        contains.add(c);
      } else {
        final country = c.countryInfo;
        if (country != null && [country.en, country.az, country.tr, country.ru].map(Countries.normalize).any((n) => n.startsWith(q))) {
          contains.add(c);
        }
      }
    }
    return [...starts, ...contains].take(limit).toList();
  }
}

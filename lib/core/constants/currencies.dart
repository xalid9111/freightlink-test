/// Currencies a load price can be given in ("Yük əlavə et"). USD stays the
/// default; the list and cards show whatever currency the load was saved in.
const kCargoCurrencies = <String>['USD', 'EUR', 'AZN', 'TRY', 'RUB', 'GEL'];
const kDefaultCargoCurrency = 'USD';

/// Currency for the form: the saved one (also an older / unlisted code is
/// kept as is), otherwise USD.
String cargoCurrencyOrDefault(String? saved) {
  final c = (saved ?? '').trim().toUpperCase();
  return c.isEmpty ? kDefaultCargoCurrency : c;
}

/// Choices for the picker; a saved code that is not in the list is added
/// so editing an old load never changes its currency by itself.
List<String> cargoCurrencyChoices(String current) =>
    kCargoCurrencies.contains(current) ? kCargoCurrencies : [current, ...kCargoCurrencies];

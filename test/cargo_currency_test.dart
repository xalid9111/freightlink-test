// "Yük əlavə et": the load price can be given in another currency.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/constants/currencies.dart';

void main() {
  test('USD stays the default; the main currencies are offered', () {
    expect(kDefaultCargoCurrency, 'USD');
    expect(kCargoCurrencies.first, 'USD');
    expect(kCargoCurrencies, containsAll(['USD', 'EUR', 'AZN', 'TRY', 'RUB', 'GEL']));
    expect(cargoCurrencyOrDefault(null), 'USD');
    expect(cargoCurrencyOrDefault(''), 'USD');
  });

  test('editing a load keeps its saved currency, also an unlisted one', () {
    expect(cargoCurrencyOrDefault('azn'), 'AZN');
    expect(cargoCurrencyChoices('EUR'), kCargoCurrencies);
    expect(cargoCurrencyChoices('KZT'), ['KZT', ...kCargoCurrencies]);
  });
}

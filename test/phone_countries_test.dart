// Phone country list: unique codes, every freight country present, and
// international numbers split back into country + national digits.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/constants/countries.dart';
import 'package:freightlink/core/constants/phone_countries.dart';

void main() {
  test('ISO codes are unique and every main freight country has a calling code', () {
    final isos = PhoneCountries.all.map((c) => c.iso).toList();
    expect(isos.toSet().length, isos.length);
    for (final c in Countries.all) {
      expect(PhoneCountries.byIso(c.code), isNotNull, reason: '${c.code} has no calling code');
    }
  });

  test('known calling codes', () {
    expect(PhoneCountries.byIso('AZ')!.dial, '994');
    expect(PhoneCountries.byIso('TR')!.dial, '90');
    expect(PhoneCountries.byIso('GE')!.dial, '995');
    expect(PhoneCountries.byIso('CN')!.dial, '86');
    expect(PhoneCountries.byIso('RU')!.dial, '7');
  });

  test('split finds the country by the longest code', () {
    final az = PhoneCountries.split('+994 50 123 45 67')!;
    expect(az.country.iso, 'AZ');
    expect(az.national, '501234567');
    expect(PhoneCountries.split('+79161234567')!.country.iso, 'RU');
    expect(PhoneCountries.split('+8613812345678')!.country.iso, 'CN');
  });

  test('Chinese names exist for the main freight countries', () {
    for (final c in Countries.all) {
      expect(c.name('zh'), isNot(c.en), reason: '${c.code} has no Chinese name');
    }
  });
}

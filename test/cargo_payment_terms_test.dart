// Load form: "Ödəniş və gözləmə şərtləri" (0046). Server rules are
// tested in supabase/tests/local/84_cargo_payment_terms.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/data/cargo_repository_impl.dart';
import 'package:freightlink/models/cargo_model.dart';

CargoModel _load({double? adv, double? cash, double? bank, int? wait}) => CargoModel(
      id: 'c1',
      ownerId: 'o',
      pickupCountry: 'AZ',
      pickupCity: 'Bakı',
      destinationCountry: 'GE',
      destinationCity: 'Tbilisi',
      weightKg: 20000,
      pickupDate: DateTime(2026, 10, 21),
      offeredPrice: 1500,
      currency: 'AZN',
      payAdvance: adv,
      payCash: cash,
      payBank: bank,
      freeWaitHours: wait,
    );

void main() {
  group('amount boxes accept only positive numbers', () {
    test('empty = not offered', () {
      expect(parsePaymentAmount(''), isNull);
      expect(parsePaymentAmount('  '), isNull);
      expect(parsePaymentAmount(null), isNull);
    });
    test('positive numbers, comma or dot', () {
      expect(parsePaymentAmount('500'), 500);
      expect(parsePaymentAmount('250,5'), 250.5);
      expect(parsePaymentAmount('1 500'), 1500);
    });
    test('zero, negative or text refused', () {
      for (final bad in ['0', '-5', 'abc', '1.2.3', '0,00']) {
        expect(() => parsePaymentAmount(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('shown on the load', () {
    test('empty methods are not shown, order advance → cash → bank', () {
      expect(_load(adv: 500, bank: 1000).paymentTerms, [('cargo_pay_advance', 500.0), ('cargo_pay_bank', 1000.0)]);
      expect(_load().paymentTerms, isEmpty);
    });
    test('an old load without terms shows no section', () {
      expect(_load().hasTerms, isFalse);
      expect(_load(wait: 48).hasTerms, isTrue);
      expect(_load(cash: 1).hasTerms, isTrue);
    });
    test('free waiting: 24 / 36 / 48, 48 by default', () {
      expect(kFreeWaitChoices, [24, 36, 48]);
      expect(kDefaultFreeWaitHours, 48);
    });
  });

  group('saved and read back', () {
    test('JSON round trip', () {
      final j = _load(adv: 500, cash: 250.5, wait: 36).toInsertJson();
      expect([j['pay_advance'], j['pay_cash'], j['pay_bank'], j['free_wait_hours']], [500.0, 250.5, null, 36]);
      final back = CargoModel.fromJson({...j, 'id': 'c1', 'pay_advance': 500, 'pay_cash': 250.5});
      expect([back.payAdvance, back.payCash, back.payBank, back.freeWaitHours], [500.0, 250.5, null, 36]);
    });
    test('old rows (no columns) read fine', () {
      final j = _load().toInsertJson(withTerms: false);
      expect(j.keys.any(CargoModel.termsColumns.contains), isFalse);
      final c = CargoModel.fromJson({...j, 'id': 'c1'});
      expect([c.payAdvance, c.payCash, c.payBank, c.freeWaitHours], [null, null, null, null]);
    });
    test('before migration 0046 is run a save retries without the new columns (load posting never breaks)', () {
      expect(isMissingTermsColumn('PGRST204', "Could not find the 'pay_advance' column of 'cargo' in the schema cache"), isTrue);
      expect(isMissingTermsColumn('42703', 'column "free_wait_hours" of relation "cargo" does not exist'), isTrue);
      expect(isMissingTermsColumn('PGRST204', "Could not find the 'weight_kg' column"), isFalse);
      expect(isMissingTermsColumn('23514', 'cargo_pay_cash_positive'), isFalse);
    });
  });

  group('guards', () {
    String read(String p) => File(p).readAsStringSync();
    test('migration is additive and re-runnable', () {
      final sql = read('supabase/migrations/0046_cargo_payment_terms.sql');
      expect(RegExp(r'add column if not exists').allMatches(sql).length, 4);
      expect(sql.contains('free_wait_hours in (24, 36, 48)'), isTrue);
      expect(RegExp(r'\b(drop table|truncate|delete from|default 48)\b', caseSensitive: false).hasMatch(sql), isFalse);
    });
    test('form: section under the price, uses the load currency, no minus sign', () {
      final f = read('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.indexOf('_PaymentTerms(') > f.indexOf("_Label(strings.t('create_price_cur'))"), isTrue);
      expect(f.indexOf('_PaymentTerms(') < f.indexOf("_Label(strings.t('quick_note'))"), isTrue);
      expect(f.contains('currency: _currency,'), isTrue);
      expect(f.contains("FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))"), isTrue);
      expect(f.contains('freeWaitHours: _freeWait,'), isTrue);
    });
    test('load page shows the section only when something is filled', () {
      expect(read('lib/features/cargo/presentation/cargo_detail_screen.dart').contains('if (cargo.hasTerms) ...['), isTrue);
    });
  });
}

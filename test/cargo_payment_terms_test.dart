// Load form: "Ödəniş və gözləmə şərtləri" (0046). Server rules are
// tested in supabase/tests/local/84_cargo_payment_terms.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/cargo/data/cargo_repository_impl.dart';
import 'package:freightlink/features/cargo/domain/truck_types.dart';
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
      // An amount saved for bank before 0047 counts as ticked (no amount shown).
      expect(_load(adv: 500, bank: 1000).paymentTerms, [('cargo_pay_advance', 500.0), ('cargo_pay_bank', null)]);
      expect(_load().paymentTerms, isEmpty);
    });
    test('order: advance (amount) → cash → after delivery → bank (just ticked)', () {
      final c = CargoModel.fromJson({
        ..._load(adv: 300).toInsertJson(),
        'id': 'c1',
        'pay_cash_on': true,
        'pay_on_delivery': true,
        'pay_bank_on': true,
      });
      expect(c.paymentTerms, [
        ('cargo_pay_advance', 300.0),
        ('cargo_pay_cash', null),
        ('cargo_pay_on_delivery', null),
        ('cargo_pay_bank', null),
      ]);
      expect(CargoModel.fromJson({..._load().toInsertJson(), 'id': 'c1', 'pay_on_delivery': true}).hasTerms, isTrue);
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
      expect(isMissingChoiceColumn('PGRST204', "Could not find the 'pay_on_delivery' column of 'cargo' in the schema cache"), isTrue);
      expect(isMissingChoiceColumn('PGRST204', "Could not find the 'pay_advance' column"), isFalse);
      final j = _load(adv: 1).toInsertJson(withChoices: false);
      expect(j.keys.any(CargoModel.choiceColumns.contains), isFalse);
      expect(j.containsKey('pay_advance'), isTrue);
      expect(isMissingTermsColumn('23514', 'cargo_pay_cash_positive'), isFalse);
    });
  });

  group('truck type', () {
    const s = AppStrings({'truck_tent': 'Tent', 'truck_dump': 'Samosval'});
    test('Tent, Ref, Samosval, Konteyner first', () {
      expect(kTruckTypes.take(4), ['tent', 'ref', 'dump', 'container']);
    });
    test('known code → its name; a typed type is shown as typed', () {
      expect(truckTypeLabel(s, 'tent'), 'Tent');
      expect(truckTypeLabel(s, 'dump'), 'Samosval');
      expect(truckTypeLabel(s, 'Lafet 3 ox'), 'Lafet 3 ox');
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
      expect(f.indexOf('_PaymentTerms(') > f.indexOf("title: strings.t('create_price_cur')"), isTrue);
      expect(f.indexOf('_PaymentTerms(') < f.indexOf("_Label(strings.t('quick_note'))"), isTrue);
      expect(f.contains('currency: _currency,'), isTrue);
      expect(f.contains("FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))"), isTrue);
      expect(f.contains('freeWaitHours: _freeWait,'), isTrue);
    });
    test('payment ways: tick box opens the amount box, unticking clears it', () {
      final f = read('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.contains('enabled: ticked,'), isTrue);
      expect(f.contains("payAdvance: _payOn.contains('advance') ? parsePaymentAmount(_advanceCtrl.text) : null,"), isTrue);
      expect(f.contains("if (k == 'advance') _advanceCtrl.clear();"), isTrue);
    });
    test('cash, after delivery and bank are only ticked: no amount box', () {
      final f = read('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.contains('_cashCtrl'), isFalse);
      expect(f.contains('_bankCtrl'), isFalse);
      final order = ["row('advance'", "choice('cash'", "choice('delivery'", "choice('bank'"];
      var at = -1;
      for (final o in order) {
        expect(f.indexOf(o) > at, isTrue, reason: o);
        at = f.indexOf(o);
      }
      expect(f.contains("payOnDelivery: _payOn.contains('delivery'),"), isTrue);
      final sql = read('supabase/migrations/0047_cargo_payment_choices.sql');
      expect(RegExp(r'add column if not exists').allMatches(sql).length, 3);
      expect(RegExp(r'\b(drop table|truncate|delete from|update public)\b', caseSensitive: false).hasMatch(sql), isFalse);
    });
    test('pallets instead of volume; an old load keeps its volume', () {
      final f = read('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.contains('_volumeCtrl'), isFalse);
      expect(f.contains('volumeM3: o?.volumeM3,'), isTrue);
      expect(f.contains('palletCount: int.tryParse(_palletCtrl.text.trim()),'), isTrue);
      expect(f.contains('FilteringTextInputFormatter.digitsOnly'), isTrue);
    });
    test('map: "Yük hovuzu" button opens the form; texts over the map have a shadow', () {
      final m = read('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
      expect(m.contains("_AddLoadButton(label: strings.t('nav_add_cargo'), onTap: () => context.pushOnce('/cargo/create'))"), isTrue);
      expect(RegExp(r'shadows: _readableOnMap\(\)').allMatches(m + read('lib/features/cargo/presentation/cargo_marketplace_desktop.dart')).length, 4);
      for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        expect(read('assets/i18n/$l.json').contains('"nav_home"'), isTrue);
      }
      expect(read('assets/i18n/az.json').contains('"nav_add_cargo": "Yük hovuzu"'), isTrue);
      expect(read('assets/i18n/az.json').contains('"nav_home": "Yüklər"'), isTrue);
    });
    test('"Əlavə məlumat" is always open, with "Digər" to type a truck type', () {
      final f = read('lib/features/cargo/presentation/cargo_quick_form.dart');
      expect(f.contains('ExpansionTile'), isFalse);
      expect(f.contains("title: strings.t('quick_more'),"), isTrue);
      expect(f.contains("key: const ValueKey('cargo-truck-other-text'),"), isTrue);
      expect(f.contains('for (final t in kTruckTypes)'), isTrue);
    });
    test('load page shows the section only when something is filled', () {
      expect(read('lib/features/cargo/presentation/cargo_detail_screen.dart').contains('if (cargo.hasTerms) ...['), isTrue);
    });
  });
}

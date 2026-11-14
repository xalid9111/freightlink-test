// "Telefon nömrəmi gizlət" and Kişi / Qadın (owner, 14.11.2026, SQL 0122):
// the switch in Profil → Şəxsi məlumatlarım asks first and shows a green
// notice; ads of a user who hid his phone show "📵 Nömrə gizlidir" instead
// of the call buttons; the server keeps the number apart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/widgets/phone_hidden_note.dart';
import 'package:freightlink/features/admin/data/rpc_migrations.dart';
import 'package:freightlink/repositories/profile_repository.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  test('own row: phone_hidden and gender are read; defaults are off / not given', () {
    final p = PublicProfile.fromJson({'id': 'u1', 'full_name': 'Əli', 'phone_hidden': true, 'gender': 'female'});
    expect(p.phoneHidden, isTrue);
    expect(p.gender, 'female');
    final old = PublicProfile.fromJson({'id': 'u2', 'full_name': 'Vəli'});
    expect(old.phoneHidden, isFalse);
    expect(old.gender, isNull);
  });

  testWidgets('the note on an ad says the number is hidden', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PhoneHiddenNote(strings: _az))));
    expect(find.text('📵 Nömrə gizlidir — Mesaj yazın'), findsOneWidget);
  });

  test('every ad page shows the note instead of the call button', () {
    for (final p in [
      'lib/features/cargo/presentation/cargo_detail_screen.dart',
      'lib/features/market/presentation/market_detail_screen.dart',
      'lib/features/services/presentation/service_widgets.dart',
      'lib/features/empty_trucks/presentation/empty_truck_detail_screen.dart',
    ]) {
      expect(src(p), contains('PhoneHiddenNote(strings:'), reason: p);
    }
    expect(src('lib/repositories/credits_repository.dart'), contains("'phone_hidden'"));
  });

  test('Şəxsi məlumatlarım: switch asks first, green notice, gender chips', () {
    final s = src('lib/features/auth/presentation/profile_screen.dart');
    expect(s, contains("ValueKey('profile-phone-hidden-switch')"));
    expect(s, contains("ValueKey('phone-hide-confirm')"));
    expect(s, contains("showPublishedNotice(context, strings.t(hide ? 'phone_hide_done' : 'phone_show_done'))"));
    expect(s, contains("ValueKey('profile-gender-\$g')"));
    // A second tap takes the gender off.
    expect(s, contains('_setGender(profile?.gender == g ? null : g)'));
  });

  test('RPCs are mapped to 0122 and the texts exist in all six languages', () {
    expect(kRpcMigration['my_set_phone_hidden'], '0122_phone_hidden_gender.sql');
    expect(kRpcMigration['my_set_gender'], '0122_phone_hidden_gender.sql');
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$l.json')) as Map<String, dynamic>;
      for (final k in [
        'profile_gender',
        'gender_male',
        'gender_female',
        'phone_hide_title',
        'phone_hide_confirm_body',
        'phone_hide_done',
        'phone_show_done',
        'phone_hidden_note',
      ]) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
    }
    expect(_az.t('phone_hide_done'), 'Nömrəniz gizlədildi ✓');
  });

  test('the server keeps the number apart (0122)', () {
    final sql = src('supabase/migrations/0122_phone_hidden_gender.sql');
    for (final x in [
      'hidden_ad_phones',
      'my_set_phone_hidden',
      'my_set_gender',
      'zzz_hide_phone',
      'user_phone_privacy',
      'get_cargo_contact',
      'get_user_contact',
    ]) {
      expect(sql, contains(x), reason: x);
    }
    expect(sql.toLowerCase(), isNot(contains('drop table')));
    expect(sql.toLowerCase(), isNot(contains('truncate')));
  });
}

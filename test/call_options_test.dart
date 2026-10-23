// "Zəng et" (owner, 23.10.2026): ONE tap opens the number, copy, a phone
// call and WhatsApp together — shared by Loads, Messages, Services and
// TIR Bazarı.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/chat/presentation/widgets/call_options.dart';

void main() {
  const s = AppStrings({
    'call_number_title': 'Phone number',
    'chat_call_phone': 'Phone call',
    'chat_call_whatsapp': 'Via WhatsApp',
    'chat_call_whatsapp_hint': 'hint',
    'call_no_whatsapp': 'no country code',
    'chat_copy': 'Copy',
  });

  Widget sheet(String phone) => MaterialApp(home: Scaffold(body: CallOptionsSheet(strings: s, phone: phone)));

  testWidgets('number, copy, call and WhatsApp at once — no second tap', (tester) async {
    await tester.pumpWidget(sheet('+994 50 123 45 67'));
    expect(find.text('+994 50 123 45 67'), findsOneWidget);
    expect(find.byKey(const ValueKey('call-copy')), findsOneWidget);
    expect(find.text('Phone call'), findsOneWidget);
    expect(find.text('Via WhatsApp'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('call-whatsapp'))).enabled, isTrue);
  });

  testWidgets('a number without its country code: call yes, WhatsApp off with the reason', (tester) async {
    await tester.pumpWidget(sheet('050 123 45 67'));
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('call-phone'))).onTap, isNotNull);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('call-whatsapp'))).enabled, isFalse);
    expect(find.text('no country code'), findsOneWidget);
  });

  test('phone → tel:, WhatsApp → wa.me with the international digits', () {
    final src = File('lib/features/chat/presentation/widgets/call_options.dart').readAsStringSync();
    expect(src.contains("launchUrl(Uri(scheme: 'tel', path: dial));"), isTrue);
    expect(src.contains("launchUrl(Uri.parse('https://wa.me/\$wa'), mode: LaunchMode.externalApplication);"), isTrue);
    expect(src.contains('final wa = whatsappDigits(shown);'), isTrue);
  });

  test('every call button uses this sheet', () {
    for (final p in [
      'lib/features/market/presentation/market_detail_screen.dart',
      'lib/features/cargo/presentation/cargo_detail_screen.dart',
      'lib/features/services/presentation/service_widgets.dart',
      'lib/features/ads/presentation/public_profile_screen.dart',
      'lib/features/chat/presentation/conversation_thread_screen.dart',
    ]) {
      expect(File(p).readAsStringSync().contains('showCallOptions(context, '), isTrue, reason: p);
    }
  });
}

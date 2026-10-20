// "Zəng et" (owner, 20.10.2026): first the number, then a tap on the
// number offers a phone call or WhatsApp.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/chat/presentation/widgets/call_options.dart';

void main() {
  const s = AppStrings({
    'call_number_title': 'Phone number',
    'call_tap_number': 'Tap the number to call',
    'chat_call_phone': 'Phone call',
    'chat_call_whatsapp': 'Via WhatsApp',
    'chat_call_whatsapp_hint': 'hint',
  });

  testWidgets('number first, choice only after tapping it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CallOptionsSheet(strings: s, phone: '+994 50 123 45 67')),
    ));
    expect(find.text('+994 50 123 45 67'), findsOneWidget);
    expect(find.text('Tap the number to call'), findsOneWidget);
    expect(find.text('Phone call'), findsNothing);
    expect(find.text('Via WhatsApp'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('call-number')));
    await tester.pump();
    expect(find.text('Phone call'), findsOneWidget);
    expect(find.text('Via WhatsApp'), findsOneWidget);
    expect(find.text('Tap the number to call'), findsNothing);
  });

  test('phone → tel:, WhatsApp → wa.me with digits only', () {
    final src = File('lib/features/chat/presentation/widgets/call_options.dart').readAsStringSync();
    expect(src.contains("launchUrl(Uri(scheme: 'tel', path: phone));"), isTrue);
    expect(src.contains("launchUrl(Uri.parse('https://wa.me/\$digits'), mode: LaunchMode.externalApplication);"), isTrue);
    expect(src.contains("phone.replaceAll(RegExp(r'[^0-9]'), '')"), isTrue);
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

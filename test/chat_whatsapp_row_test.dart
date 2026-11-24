import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/utils/whatsapp_open.dart';
import 'package:freightlink/features/chat/presentation/widgets/chat_input_bar.dart';

/// "WhatsApp ilə davam et" first in the chat's attach sheet (owner,
/// 24.11.2026): opens the other person's WhatsApp chat at once.
void main() {
  Future<void> pump(WidgetTester t, String? phone) => t.pumpWidget(MaterialApp(
        home: Scaffold(body: ChatWhatsAppRow(strings: const AppStrings({}), phone: phone, onDone: () {})),
      ));

  testWidgets('a number with its country code = the row works', (t) async {
    await pump(t, '+994 50 123 45 67');
    final tile = t.widget<ListTile>(find.byKey(const ValueKey('chat-attach-whatsapp')));
    expect(tile.enabled, isTrue);
    expect(find.text('chat_attach_whatsapp_hint'), findsOneWidget);
  });

  testWidgets('no number (hidden / not released) = greyed with the reason', (t) async {
    await pump(t, null);
    expect(t.widget<ListTile>(find.byKey(const ValueKey('chat-attach-whatsapp'))).enabled, isFalse);
    expect(find.text('chat_attach_whatsapp_none'), findsOneWidget);
  });

  testWidgets('a number without its country code = the existing reason', (t) async {
    await pump(t, '050 123 45 67');
    expect(t.widget<ListTile>(find.byKey(const ValueKey('chat-attach-whatsapp'))).enabled, isFalse);
    expect(find.text('call_no_whatsapp'), findsOneWidget);
  });

  test('a phone opens the WhatsApp app directly, not the wa.me page', () {
    expect(whatsAppAppUri('994501234567').toString(), 'whatsapp://send?phone=994501234567');
    expect(whatsAppWebUri('994501234567').toString(), 'https://wa.me/994501234567');
    final src = File('lib/core/utils/whatsapp_open.dart').readAsStringSync();
    expect(src, contains("launchUrl(whatsAppAppUri(digits), webOnlyWindowName: '_self');"),
        reason: 'same window, inside the tap (iPhone Home Screen app stays)');
  });

  test('wired: FIRST in the sheet, only in a direct chat, opened inside the tap', () {
    final bar = File('lib/features/chat/presentation/widgets/chat_input_bar.dart').readAsStringSync();
    final sheet = bar.substring(bar.indexOf('void _openAttachMenu()'));
    expect(sheet.indexOf('ChatWhatsAppRow('), lessThan(sheet.indexOf('chat_attach_photo')), reason: 'the first row');
    expect(bar, contains('openWhatsAppChat(wa, onNotOpened:'), reason: 'the app itself, inside the tap');
    expect(bar, contains('whatsAppWebUri(wa)'), reason: 'not installed = wa.me with a new tap');
    final chat = File('lib/features/chat/presentation/conversation_thread_screen.dart').readAsStringSync();
    expect(chat, contains('offerWhatsApp: true'));
    final group = File('lib/features/chat/presentation/group_thread_screen.dart').readAsStringSync();
    expect(group.contains('offerWhatsApp'), isFalse, reason: 'a group has no single number');
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = File('assets/i18n/$l.json').readAsStringSync();
      for (final k in ['chat_attach_whatsapp', 'chat_attach_whatsapp_hint', 'chat_attach_whatsapp_none']) {
        expect(j, contains('"$k"'), reason: '$l $k');
      }
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/phone_utils.dart';

/// Call sheet (owner, 23.10.2026): ONE tap on a number or "Əlaqə saxla"
/// opens it with everything at once — the number, copy, a phone call and
/// WhatsApp. Shared by Loads, Messages, Services and TIR Bazarı. No server
/// needed: both are links handed to the phone / computer.
///
/// WhatsApp offers no public link that starts a *call* directly, so the
/// WhatsApp option opens the chat with that number (wa.me); the call
/// button is one tap away there. wa.me needs the international number as
/// digits only (+994 50 123 45 67 → 994501234567); a number without its
/// country code is still callable, but WhatsApp is then switched off with
/// a short reason instead of opening a wrong chat.
void showCallOptions(BuildContext context, AppStrings strings, String phone) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(child: CallOptionsSheet(strings: strings, phone: phone)),
  );
}

class CallOptionsSheet extends StatelessWidget {
  final AppStrings strings;
  final String phone;
  const CallOptionsSheet({super.key, required this.strings, required this.phone});

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final shown = phone.trim();
    final wa = whatsappDigits(shown);
    final dial = normalizePhone(shown) ?? shown.replaceAll(RegExp(r'[^0-9+]'), '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(s.t('call_number_title'),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
        ),
        // The number and "copy".
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: FittedBox(
                key: const ValueKey('call-number'),
                fit: BoxFit.scaleDown,
                child: SelectableText(shown, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('call-copy'),
              tooltip: s.t('chat_copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shown));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.t('chat_copied'))));
              },
              icon: Icon(Icons.copy, color: AppColors.textSoft),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        ListTile(
          key: const ValueKey('call-phone'),
          leading: Icon(Icons.call, color: AppColors.accent),
          title: Text(s.t('chat_call_phone')),
          onTap: dial.isEmpty
              ? null
              : () {
                  Navigator.of(context).pop();
                  launchUrl(Uri(scheme: 'tel', path: dial));
                },
        ),
        ListTile(
          key: const ValueKey('call-whatsapp'),
          enabled: wa != null,
          leading: Icon(Icons.chat, color: wa != null ? AppColors.whatsapp : AppColors.textSoft),
          title: Text(s.t('chat_call_whatsapp')),
          subtitle: Text(s.t(wa != null ? 'chat_call_whatsapp_hint' : 'call_no_whatsapp')),
          onTap: wa == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  launchUrl(Uri.parse('https://wa.me/$wa'), mode: LaunchMode.externalApplication);
                },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// Call sheet in two steps (owner, 20.10.2026): first the number is shown;
/// a tap on the number offers a normal phone call or WhatsApp. No server
/// needed: both are just links handed to the phone / computer.
///
/// WhatsApp offers no public link that starts a *call* directly, so the
/// WhatsApp option opens the chat with that number (wa.me); the call
/// button is one tap away there. Numbers are passed to wa.me as digits
/// only, in international format (e.g. +994 50 123 45 67 → 994501234567).
void showCallOptions(BuildContext context, AppStrings strings, String phone) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(child: CallOptionsSheet(strings: strings, phone: phone)),
  );
}

class CallOptionsSheet extends StatefulWidget {
  final AppStrings strings;
  final String phone;
  const CallOptionsSheet({super.key, required this.strings, required this.phone});

  @override
  State<CallOptionsSheet> createState() => _CallOptionsSheetState();
}

class _CallOptionsSheetState extends State<CallOptionsSheet> {
  bool _choose = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final phone = widget.phone;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(s.t('call_number_title'),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
        ),
        // Step 1: the number itself; a tap opens the choice below.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('call-number'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accentFill),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => setState(() => _choose = true),
                icon: const Icon(Icons.call),
                label: Text(phone, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: s.t('chat_copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: phone));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.t('chat_copied'))));
              },
              icon: Icon(Icons.copy, color: AppColors.textSoft),
            ),
          ]),
        ),
        if (!_choose)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(s.t('call_tap_number'),
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
          ),
        // Step 2: phone call or WhatsApp.
        if (_choose) ...[
          const SizedBox(height: 4),
          ListTile(
            key: const ValueKey('call-phone'),
            leading: Icon(Icons.call, color: AppColors.accent),
            title: Text(s.t('chat_call_phone')),
            onTap: () {
              Navigator.of(context).pop();
              launchUrl(Uri(scheme: 'tel', path: phone));
            },
          ),
          ListTile(
            key: const ValueKey('call-whatsapp'),
            leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
            title: Text(s.t('chat_call_whatsapp')),
            subtitle: Text(s.t('chat_call_whatsapp_hint')),
            onTap: () {
              Navigator.of(context).pop();
              launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication);
            },
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

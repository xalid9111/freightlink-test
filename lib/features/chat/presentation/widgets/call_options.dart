import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// Call choice sheet: a normal phone call, or WhatsApp. No server needed:
/// both are just links handed to the phone.
///
/// WhatsApp offers no public link that starts a *call* directly, so the
/// WhatsApp option opens the chat with that number (wa.me); the call
/// button is one tap away there. Numbers are passed to wa.me as digits
/// only, in international format (e.g. +994 50 123 45 67 → 994501234567).
void showCallOptions(BuildContext context, AppStrings strings, String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(phone, style: AppFonts.mono(size: 14, color: AppColors.textSoft)),
          ),
          ListTile(
            leading: const Icon(Icons.call, color: AppColors.accent),
            title: Text(strings.t('chat_call_phone')),
            onTap: () {
              Navigator.of(ctx).pop();
              launchUrl(Uri(scheme: 'tel', path: phone));
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
            title: Text(strings.t('chat_call_whatsapp')),
            subtitle: Text(strings.t('chat_call_whatsapp_hint')),
            onTap: () {
              Navigator.of(ctx).pop();
              launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

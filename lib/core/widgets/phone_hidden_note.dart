import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

/// "📵 Nömrə gizlidir — Mesaj yazın" (owner, 14.11.2026, SQL 0122): shown on
/// an ad instead of the call / WhatsApp buttons when its owner hid his phone
/// in Profil → Şəxsi məlumatlarım. The number itself never reaches the app
/// (the server keeps it apart); "Mesaj yaz" on the page still works.
class PhoneHiddenNote extends StatelessWidget {
  final AppStrings strings;
  const PhoneHiddenNote({super.key, required this.strings});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('phone-hidden-note'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(children: [
        Icon(Icons.phone_disabled_outlined, size: 20, color: AppColors.textSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Text(strings.t('phone_hidden_note'), style: TextStyle(fontSize: 14, color: AppColors.textSoft)),
        ),
      ]),
    );
  }
}

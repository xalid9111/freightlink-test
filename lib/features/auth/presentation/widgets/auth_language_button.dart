import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/layout/desktop_layout.dart' show languageFlag;
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../settings_screen.dart' show showLanguagePicker;

/// The language choice on the sign-in pages (owner, 21.11.2026: "dil
/// seçimini yuxarıda göstər, istifadəçi rus dilini bilməyə bilər"): the
/// flag + the code (AZ, RU …) at the top right; a tap opens the same picker
/// as Ayarlar (6 languages, applied at once, kept on the device).
class AuthLanguageButton extends ConsumerWidget {
  const AuthLanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    return Tooltip(
      message: strings.t('settings_app_language'),
      child: InkWell(
        key: const ValueKey('auth-lang'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => showLanguagePicker(context, ref, strings),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(languageFlag(lang), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(lang.toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
            Icon(Icons.expand_more, size: 18, color: AppColors.textSoft),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';

/// "Hesabdan çıxış" asks first (owner, 24.11.2026: "çıxmaq istəyirsən? Hə
/// yada yox … basan kimi anidən çıxmasın"). True only for "Bəli, çıx";
/// "Xeyr", a tap outside or back = stay signed in.
Future<bool> confirmSignOut(BuildContext context, AppStrings s) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('sign-out-confirm'),
      title: Text(s.t('pf_sign_out_q')),
      content: Text(s.t('pf_sign_out_body')),
      actions: [
        TextButton(
          key: const ValueKey('sign-out-no'),
          onPressed: () => Navigator.pop(c, false),
          child: Text(s.t('pf_sign_out_no')),
        ),
        FilledButton(
          key: const ValueKey('sign-out-yes'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(c, true),
          child: Text(s.t('pf_sign_out_yes')),
        ),
      ],
    ),
  );
  return ok == true;
}

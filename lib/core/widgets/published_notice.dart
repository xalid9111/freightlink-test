import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Dərc olundu ✓" (owner, 07.11.2026): after a load, a TIR Bazarı ad, a
/// service / shop or a park request is sent, the page goes back to its
/// section and this clear green notice tells that it worked. It lives on
/// the app's ScaffoldMessenger, so it stays while the page changes.
void showPublishedNotice(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      key: const ValueKey('published-notice'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.online,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w500)),
        ),
      ]),
    ));
}

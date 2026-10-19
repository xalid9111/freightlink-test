import 'package:flutter/widgets.dart';

/// Desktop layout (owner's desktop design, 19.10.2026): from this window
/// width the app shows the left sidebar and the wide desktop pages. Below it
/// (phones, tablets, narrow windows) everything stays exactly the mobile app.
const double kDesktopMinWidth = 1100;

bool isDesktopLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= kDesktopMinWidth;

/// Flag shown next to the app language in the desktop sidebar.
String languageFlag(String code) => switch (code) {
      'az' => '🇦🇿',
      'tr' => '🇹🇷',
      'en' => '🇬🇧',
      'ru' => '🇷🇺',
      'ka' => '🇬🇪',
      'zh' => '🇨🇳',
      _ => '🌐',
    };

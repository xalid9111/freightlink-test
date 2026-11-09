import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Country flags (🇦🇿 🇹🇷 …) drawn from a font shipped with the app.
///
/// Flutter web normally downloads its emoji font from fonts.gstatic.com
/// while the page runs. Where that download does not work (some
/// computers / networks) flags became empty boxes "□□". This font holds
/// only the flag glyphs of Noto Color Emoji (the same pictures as
/// before, SIL OFL 1.1 — see assets/fonts/flags/OFL.txt) and is loaded
/// in the background after the first screen, so start-up is not slower.
const kFlagFontFamily = 'FlagEmoji';
const kFlagFontAsset = 'assets/fonts/flags/NotoColorEmoji-Flags.woff2';

Future<void> loadFlagFont() async {
  if (!kIsWeb) return; // apps use the system emoji font
  try {
    await (FontLoader(kFlagFontFamily)..addFont(rootBundle.load(kFlagFontAsset))).load();
  } catch (_) {
    // Not critical: the downloaded emoji font (as before) still applies.
  }
}

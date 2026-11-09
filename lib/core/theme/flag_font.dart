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

/// Starts downloading the font file (owner, 09.11.2026: at start-up, so
/// it is there before the load cards; nothing waits for it).
Future<ByteData>? startFlagFontDownload() {
  if (!kIsWeb) return null;
  final f = rootBundle.load(kFlagFontAsset);
  f.then((_) {}, onError: (_) {}); // a failure is handled in loadFlagFont
  return f;
}

/// Registers the font — after the first screen, so unpacking it never holds
/// that screen up. [bytes] = a download already started.
Future<void> loadFlagFont([Future<ByteData>? bytes]) async {
  if (!kIsWeb) return; // apps use the system emoji font
  try {
    await (FontLoader(kFlagFontFamily)..addFont(bytes ?? rootBundle.load(kFlagFontAsset))).load();
  } catch (_) {
    // Not critical: the downloaded emoji font (as before) still applies.
  }
}

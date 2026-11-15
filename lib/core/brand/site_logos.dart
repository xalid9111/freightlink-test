import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../config/supabase_config.dart';
import '../widgets/framed_image.dart';
import 'site_logos_js_stub.dart' if (dart.library.js_interop) 'site_logos_js_web.dart' as js;

/// The site's logos (owner, 15.11.2026, SQL 0124): the Baş admin changes them
/// in Admin → Loqolar. Three places:
///   * [appIcon]  — Home Screen / tab icon (square, not transparent);
///   * [homeLogo] — left of "TırLink" (Yüklər, computer sidebar, login page);
///   * [splash]   — the dark start-up screen.
/// null = the app's built-in logo. Read once after start (visitors too);
/// the start-up page and the icon links read the device's last copy
/// (web/site_logos.js) before the app is loaded.
class SiteLogos {
  SiteLogos._();

  static const slots = ['app_icon', 'home_logo', 'splash'];

  static final ValueNotifier<String?> homeLogo = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> appIcon = ValueNotifier<String?>(null);
  static final ValueNotifier<String?> splash = ValueNotifier<String?>(null);

  static ValueNotifier<String?> of(String slot) => switch (slot) {
        'app_icon' => appIcon,
        'home_logo' => homeLogo,
        _ => splash,
      };

  /// Fills the notifiers from rows {slot, url} and updates the page.
  static void applyRows(Iterable<Map<String, dynamic>> rows) {
    for (final r in rows) {
      final slot = '${r['slot']}';
      if (!slots.contains(slot)) continue;
      final url = r['url'];
      of(slot).value = url is String && url.isNotEmpty ? url : null;
    }
    js.applyLogosToPage(jsonEncode({for (final s in slots) s: of(s).value}));
  }

  /// After start: the saved logos (a missing table = the built-in ones).
  static Future<void> load() async {
    try {
      final rows =
          await SupabaseConfig.client.from('site_logos').select('slot,url').timeout(const Duration(seconds: 10));
      applyRows([for (final r in rows as List) Map<String, dynamic>.from(r as Map)]);
    } catch (_) {}
  }

  /// Baş admin: uploads a framed picture and saves it for [slot].
  static Future<String> save(String slot, Uint8List png) async {
    final c = SupabaseConfig.client;
    final path = '${c.auth.currentUser!.id}/logo_${slot}_${DateTime.now().microsecondsSinceEpoch}.png';
    await c.storage
        .from('market-photos')
        .uploadBinary(path, png, fileOptions: const FileOptions(contentType: 'image/png'))
        .timeout(const Duration(minutes: 2));
    final url = c.storage.from('market-photos').getPublicUrl(path);
    await c.rpc('admin_site_logo_set', params: {'p_slot': slot, 'p_url': url});
    applyRows([
      {'slot': slot, 'url': url}
    ]);
    return url;
  }

  /// Baş admin: back to the built-in logo.
  static Future<void> reset(String slot) async {
    await SupabaseConfig.client.rpc('admin_site_logo_set', params: {'p_slot': slot, 'p_url': null});
    applyRows([
      {'slot': slot, 'url': null}
    ]);
  }
}

/// The ground of the phone icon and the start-up page (#02050C, the same as
/// manifest.json's background / theme colour) — the icon must not be
/// transparent.
const Color kAppIconGround = Color(0xFF02050C);

/// The picture as it is framed in the editor (move / zoom, square), drawn
/// into a [size]×[size] PNG. [background] fills first (the app icon must
/// not be transparent).
Future<Uint8List> renderFramedSquare(Uint8List source, ImageFraming f, int size, {Color? background}) async {
  final codec = await ui.instantiateImageCodec(source);
  final img = (await codec.getNextFrame()).image;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = size.toDouble();
  if (background != null) canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = background);
  final r = framedRect(Size(img.width.toDouble(), img.height.toDouble()), s, f);
  canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r,
      Paint()..filterQuality = FilterQuality.high);
  final out = await rec.endRecording().toImage(size, size);
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Where the picture lands in a square frame of side [s]: like BoxFit.cover,
/// zoomed f.z×, placed by f's alignment (the editor's own rule).
@visibleForTesting
Rect framedRect(Size image, double s, ImageFraming f) {
  final cover = (s / image.width) > (s / image.height) ? s / image.width : s / image.height;
  final w = image.width * cover * f.z, h = image.height * cover * f.z;
  final left = (s - w) * (f.ax + 1) / 2;
  final top = (s - h) * (f.ay + 1) / 2;
  return Rect.fromLTWH(left, top, w, h);
}

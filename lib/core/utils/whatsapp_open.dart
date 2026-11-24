import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a WhatsApp chat with [digits] (international number, digits only).
///
/// On a phone (owner, 24.11.2026: "bir başa WhatsApp profilini açsın") the
/// app itself is asked first — whatsapp://send?phone=… in the same window,
/// inside the tap — so there is no wa.me page in between ("Continue to
/// chat"). If the phone did not leave TırLink within [wait] (WhatsApp not
/// installed), [onNotOpened] is called so the page can offer wa.me with a
/// new tap. A computer keeps wa.me (WhatsApp Web / Desktop).
void openWhatsAppChat(
  String digits, {
  VoidCallback? onNotOpened,
  Duration wait = const Duration(milliseconds: 1600),
  TargetPlatform? platform,
}) {
  final p = platform ?? defaultTargetPlatform;
  final phone = p == TargetPlatform.iOS || p == TargetPlatform.android;
  if (!phone) {
    launchUrl(whatsAppWebUri(digits), mode: LaunchMode.externalApplication);
    return;
  }
  var left = false;
  final listener = AppLifecycleListener(
    onHide: () => left = true,
    onPause: () => left = true,
    onInactive: () => left = true,
  );
  launchUrl(whatsAppAppUri(digits), webOnlyWindowName: '_self');
  Timer(wait, () {
    listener.dispose();
    if (!left) onNotOpened?.call();
  });
}

/// The app link: opens the chat in WhatsApp directly.
Uri whatsAppAppUri(String digits) => Uri.parse('whatsapp://send?phone=$digits');

/// The web link (WhatsApp Web / the wa.me page).
Uri whatsAppWebUri(String digits) => Uri.parse('https://wa.me/$digits');

import 'package:url_launcher/url_launcher.dart';

/// Phone apps (not the web build): the app scheme goes straight to the OS.
Future<bool> openAppLink(String link) async {
  try {
    return await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

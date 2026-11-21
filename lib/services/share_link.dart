import 'package:flutter/services.dart';

import 'web_share_stub.dart' if (dart.library.js_interop) 'web_share_web.dart' as impl;

/// Shares a page of the app (owner, 21.11.2026: the "Paylaş" button on a
/// load card): the phone's share sheet where there is one, else the link is
/// copied. Returns true when the link was COPIED (the caller says so).
Future<bool> shareOrCopy({required String title, required String text, required String url}) async {
  if (await impl.shareViaSystem(title: title, text: text, url: url)) return false;
  await Clipboard.setData(ClipboardData(text: '$text\n$url'));
  return true;
}

/// The public address of an app page ("/cargo/123" → "https://tirlink.app/#/cargo/123").
String appPageLink(String path) {
  final b = Uri.base;
  final origin = (b.scheme == 'http' || b.scheme == 'https') ? b.origin : 'https://tirlink.app';
  return '$origin/#$path';
}

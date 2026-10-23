/// Phone numbers for "Zəng et / WhatsApp" (owner, 23.10.2026).
///
/// Numbers are kept in international format (E.164: "+" and 7–15 digits,
/// e.g. +994501234567). WhatsApp (wa.me) needs exactly that, as digits
/// only; a number without its country code cannot be opened there.
library;

/// "+994 50-123 45 67" → "+994501234567"; null when it is not a full
/// international number (empty, no "+", too short / long).
String? normalizePhone(String? raw) {
  final t = (raw ?? '').replaceAll(RegExp(r'[\s().\-]'), '');
  if (t.isEmpty) return null;
  final plus = t.startsWith('+') || t.startsWith('00');
  var digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (t.startsWith('00')) digits = digits.substring(2);
  if (!plus || !RegExp(r'^[1-9][0-9]{6,14}$').hasMatch(digits)) return null;
  return '+$digits';
}

/// Digits for https://wa.me/<digits>; null = WhatsApp cannot be offered.
String? whatsappDigits(String? raw) => normalizePhone(raw)?.substring(1);

/// The number to show for a load: its own contact number when set,
/// otherwise the poster's registered phone (both released by the server
/// only to people allowed to see them — get_cargo_contact, 0019 / 0060).
String? cargoContactNumber({String? contactPhone, String? registeredPhone}) {
  final alt = (contactPhone ?? '').trim();
  if (alt.isNotEmpty) return alt;
  final reg = (registeredPhone ?? '').trim();
  return reg.isEmpty ? null : reg;
}

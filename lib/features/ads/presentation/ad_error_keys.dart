// Ad errors → texts. Pure logic (no Flutter, no Supabase), unit-tested in
// test/ad_error_keys_test.dart.

/// Short code of a failed request, shown in brackets so the real cause can
/// be read from a screenshot: a PostgREST code (`PGRST202` = server
/// function missing), else the server's own word (`ordering_disabled`),
/// else the Postgres code (`42883`), else the storage HTTP status
/// (`storage_403`), `timeout` or `network`. Empty if none.
String adErrorCode(String raw) {
  final pgrst = RegExp(r'\b(PGRST\d{3})\b').firstMatch(raw);
  if (pgrst != null) return pgrst.group(1)!;
  final word = RegExp(r'\b[a-z]+(?:_[a-z]+)+\b').firstMatch(raw);
  if (word != null) return word.group(0)!;
  final pg = RegExp(r'code:\s*"?([0-9A-Z]{5})\b').firstMatch(raw);
  if (pg != null) return pg.group(1)!;
  final st = RegExp(r'statusCode:\s*"?(\d{3})').firstMatch(raw);
  if (st != null) return 'storage_${st.group(1)}';
  final t = raw.toLowerCase();
  if (t.contains('timeoutexception') || t.contains('timed out')) return 'timeout';
  if (t.contains('failed to fetch') || t.contains('clientexception') || t.contains('xmlhttprequest')) return 'network';
  return '';
}

/// Text key for a failed "my own picture" upload (service ad, 0032).
/// Known causes get their own text; anything else the general one (the
/// screen adds [adErrorCode]).
String ownImageErrorKey(String raw) {
  if (raw.contains('ordering_disabled')) return 'adv_err_ordering_disabled';
  if (raw.contains('account_blocked')) return 'adv_err_account_blocked';
  if (raw.contains('too_many_backgrounds')) return 'adv_own_image_too_many';
  final t = raw.toLowerCase();
  if (raw.contains('invalid_image') ||
      t.contains('payload too large') ||
      t.contains('maximum allowed size') ||
      t.contains('mime type') ||
      RegExp(r'statuscode:\s*"?(413|415)').hasMatch(t)) {
    return 'adv_own_image_invalid';
  }
  return 'adv_own_image_failed';
}

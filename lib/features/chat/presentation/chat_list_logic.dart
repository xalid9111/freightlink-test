// Pure logic of the Messages list (no Flutter, no Supabase) — unit-tested
// in test/chat_list_logic_test.dart.

/// Latest activity with one person and whether their row is shown.
///
/// [chats] = every 1-to-1 conversation with that person (id + created at).
/// A chat deleted "for me" (`clears[id]`, migration 0031) stays hidden
/// until something newer than the delete arrives.
({DateTime last, bool visible}) partnerRowState(
  Iterable<({String id, DateTime createdAt})> chats, {
  required Map<String, DateTime> activity,
  required Map<String, DateTime> clears,
}) {
  DateTime? last;
  var visible = false;
  for (final c in chats) {
    final t = activity[c.id] ?? c.createdAt;
    if (last == null || t.isAfter(last)) last = t;
    final cleared = clears[c.id];
    if (cleared == null || t.isAfter(cleared)) visible = true;
  }
  return (last: last ?? DateTime.fromMillisecondsSinceEpoch(0), visible: visible);
}

/// People search results without the people whose chat row is already on
/// the screen (no duplicate rows). Someone whose chat I deleted has no row,
/// so they stay findable and the chat can be opened again.
List<T> peopleWithoutShownChats<T>(Iterable<T> hits, String Function(T) idOf, Set<String> shownPartnerIds) =>
    [for (final h in hits) if (!shownPartnerIds.contains(idOf(h))) h];

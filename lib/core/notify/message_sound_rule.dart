/// When the message sound plays (owner, 15.11.2026: "saytı açarkən bildiriş
/// səsi gəlir, halbuki heç bir bildiriş yoxdur … saytda ikən SMS gələrsə səs
/// gəlməlidir"). Opening the site, the first list can arrive empty (the live
/// connection not ready yet) and the next one with the old unread messages —
/// they looked "new" and rang. Now a message rings only when
///   * its id was never announced before, AND
///   * it was written after this visit started (a short grace for the
///     difference between the phone's and the server's clocks).
/// Old unread messages still show in the counters, silently.
class MessageSoundRule {
  /// When this visit of the site / app started.
  final DateTime sessionStart;

  /// Phone vs server clock difference allowed.
  static const clockGrace = Duration(minutes: 2);

  final Set<String> _announced = {};

  MessageSoundRule({DateTime? sessionStart}) : sessionStart = sessionStart ?? DateTime.now();

  /// [messages]: (id, written at) of the incoming / unread messages now on
  /// the list. True = play the sound once for this update.
  bool shouldRing(Iterable<(String, DateTime)> messages) {
    final from = sessionStart.subtract(clockGrace);
    var ring = false;
    for (final (id, at) in messages) {
      if (_announced.add(id) && at.toUtc().isAfter(from.toUtc())) ring = true;
    }
    return ring;
  }
}

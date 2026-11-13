import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A live list that never depends on realtime alone (owner, 13.11.2026: a
/// saved UTEP job and new messages did not show / made no sound when a
/// realtime message was late or lost): the realtime stream PLUS a plain
/// server read at once and every [every]. A realtime error never empties
/// the list; a failed read is simply tried again on the next tick.
Stream<List<T>> liveWithResync<T>(Ref ref, Stream<List<T>> Function() live, Future<List<T>> Function() read,
    {required Duration every}) {
  final out = StreamController<List<T>>();
  StreamSubscription<List<T>>? sub;
  try {
    sub = live().listen((v) {
      if (!out.isClosed) out.add(v);
    }, onError: (_) {});
  } catch (_) {}
  Future<void> reread() async {
    try {
      final rows = await read();
      if (!out.isClosed) out.add(rows);
    } catch (_) {}
  }

  unawaited(reread());
  final timer = Timer.periodic(every, (_) => reread());
  ref.onDispose(() {
    timer.cancel();
    sub?.cancel();
    out.close();
  });
  return out.stream;
}

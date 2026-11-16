// Faster site, stage 2 (owner, 16.11.2026): opened on Yüklər, the work the
// first screen does not need starts after it, one group at a time; nothing
// is turned off, and every other first page starts everything at once.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/startup/startup_steps.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  tearDown(() => StartupSteps.resetForTest());

  test('not started (tests, other pages): nothing waits', () async {
    StartupSteps.resetForTest();
    for (final n in [1, 2, 3]) {
      expect(StartupSteps.isFree(n), isTrue);
      await StartupSteps.reached(n);
    }
    expect(await StartupSteps.after(3, () => Stream.value(7)).first, 7);
  });

  test('opened on Yüklər: steps free one after another after the first frame', () async {
    StartupSteps.resetForTest();
    final frame = Completer<void>();
    const ms = Duration(milliseconds: 1);
    StartupSteps.start(stagger: true, firstFrame: frame.future, delays: [ms * 40, ms * 120, ms * 200]);
    var opened = 0;
    final sub = StartupSteps.after(1, () {
      opened++;
      return Stream.value(1);
    }).listen((_) {});
    List<bool> free() => [
          for (final n in [1, 2, 3]) StartupSteps.isFree(n)
        ];
    await Future<void>.delayed(ms * 300);
    expect(free(), [false, false, false], reason: 'nothing before the first frame');
    expect(opened, 0, reason: 'the subscription waits');
    frame.complete();
    await Future<void>.delayed(ms * 80);
    expect(free(), [true, false, false]);
    expect(opened, 1);
    await Future<void>.delayed(ms * 80);
    expect(free(), [true, true, false]);
    await Future<void>.delayed(ms * 120);
    expect(free(), [true, true, true]);
    await sub.cancel();
    StartupSteps.releaseAll();
  });

  test('opened on another page: everything at once', () {
    StartupSteps.resetForTest();
    StartupSteps.start(stagger: false);
    expect([
      for (final n in [1, 2, 3]) StartupSteps.isFree(n)
    ], [
      true,
      true,
      true
    ]);
  });

  test('the order: messages → map / online / groups → new-item counters', () {
    expect(src('lib/main.dart'), contains('StartupSteps.start(stagger: CargoFeedPrefetch.opensOnLoads(Uri.base));'));
    expect(src('lib/features/chat/presentation/providers/chat_providers.dart'),
        contains('return StartupSteps.after(\n      1,'));
    final groups = src('lib/features/chat/presentation/providers/group_providers.dart');
    expect(groups, contains('StartupSteps.after(2, () => repo.watchMyMemberships(uid))'));
    expect(groups, contains('StartupSteps.after(2, repo.watchMyGroupMessages)'));
    expect(src('lib/core/presence/online_users.dart'), contains('StartupSteps.reached(2).then'));
    expect(src('lib/features/cargo/presentation/widgets/live_map.dart'), contains('StartupSteps.reached(2).then'));
    expect(src('lib/core/notify/notify_settings.dart'), contains('StartupSteps.reached(3).then'));
    expect(src('lib/core/notify/new_items_badges.dart'), contains('StartupSteps.reached(3).then'));
  });
}

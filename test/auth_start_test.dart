// Owner, 22.11.2026: "ilk açdığımda 0 maşın gəlir, sonra yenidən yüklənir …
// kartlar iki dəfə yüklənməsin". At start-up the user id comes from the
// session restored on the device, so a page's data is read ONCE, with the
// right account, instead of "signed out → empty → read again".
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';

void main() {
  AppUser user(String id) => AppUser(id: id, email: '$id@x.az', fullName: id, role: 'carrier', isVerified: false);

  test('while the auth stream is still loading, the restored session id is used; the same id later fetches nothing again', () async {
    final auth = StreamController<AppUser?>();
    var reads = 0;
    final data = FutureProvider<String>((ref) async {
      final uid = ref.watch(currentUserIdProvider);
      reads++;
      return uid == null ? 'EMPTY' : 'data of $uid';
    });
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      sessionUserIdProvider.overrideWithValue('u1'),
    ]);
    addTearDown(c.dispose);
    c.listen(data, (_, __) {});
    expect(await c.read(data.future), 'data of u1', reason: 'never the empty "signed out" page first');
    auth.add(user('u1'));
    await Future<void>.delayed(Duration.zero);
    await c.read(data.future);
    expect(reads, 1, reason: 'the stream bringing the same account reads nothing twice');
    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(data.future), 'EMPTY', reason: 'a real sign-out still clears it');
    await auth.close();
  });

  test('no session on the device: signed out from the start', () async {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => const Stream<AppUser?>.empty()),
      sessionUserIdProvider.overrideWithValue(null),
    ]);
    addTearDown(c.dispose);
    expect(c.read(currentUserIdProvider), isNull);
  });
}

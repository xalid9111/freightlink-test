// Owner, 23.11.2026 (iPhone 11 Pro, the Home Screen app): coming back from
// another app the page slid up by itself and the place in the list was lost.
// On coming back the token is renewed and the users row can fail to read for
// a moment; that used to count as "signed out", which emptied every list
// (they all follow the signed-in id) and read it again from the top.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/auth/data/auth_repository_impl.dart' show userAfterFailedRead;
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';

void main() {
  AppUser user(String id) => AppUser(id: id, email: '$id@x.az', fullName: id, role: 'carrier', isVerified: false);

  test('a failed read for the same session keeps the known user; nobody known = signed out as before', () {
    expect(userAfterFailedRead(user('u1'), 'u1'), user('u1'));
    expect(userAfterFailedRead(null, 'u1'), isNull);
    expect(userAfterFailedRead(user('u1'), 'u2'), isNull, reason: 'another account is never kept');
  });

  test('coming back: the same user again reads no list again (the page keeps its place)', () async {
    final auth = StreamController<AppUser?>();
    var reads = 0;
    final list = FutureProvider<String>((ref) async {
      final uid = ref.watch(currentUserIdProvider);
      reads++;
      return 'list of $uid';
    });
    final c = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => auth.stream)]);
    addTearDown(c.dispose);
    c.listen(list, (_, __) {});
    auth.add(user('u1'));
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(list.future), 'list of u1');
    final before = reads;
    // Token renewed on coming back: the stream brings the same (kept) user.
    auth.add(userAfterFailedRead(user('u1'), 'u1'));
    await Future<void>.delayed(Duration.zero);
    await c.read(list.future);
    expect(reads, before, reason: 'no "signed out → empty → read again"');
    await auth.close();
  });

  test('wired: both failure paths of the auth stream keep the same user', () {
    final src = File('lib/features/auth/data/auth_repository_impl.dart').readAsStringSync();
    expect('userAfterFailedRead(_cachedUser, authUser.id)'.allMatches(src).length, 2);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/chat/data/user_blocks.dart';

/// Users block one another (owner, 24.11.2026, SQL 0135): Mesajlar → the
/// name → the profile → "Blok et" at its end, always asked first.
void main() {
  test('the server\'s answer is read safely', () {
    final a = UserBlockState.fromJson({'i_blocked': true, 'blocked_me': false});
    expect(a.iBlocked && !a.blockedMe && a.any, isTrue);
    final b = UserBlockState.fromJson({'i_blocked': false, 'blocked_me': true});
    expect(b.blockedMe && b.any, isTrue);
    expect(UserBlockState.fromJson(null).any, isFalse, reason: 'no 0135 / visitor = nothing changes');
    expect(UserBlockState.fromJson('x').any, isFalse);
  });

  testWidgets('"Blok et" asks first; Xeyr changes nothing', (t) async {
    bool? done;
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Consumer(
          builder: (c, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () async => done = await confirmAndSetUserBlock(
                  context: c, ref: ref, s: const AppStrings({}), userId: 'u2', block: true, name: 'Əli'),
              child: const Text('block'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('block'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-block-confirm')), findsOneWidget, reason: 'never at once');
    await t.tap(find.byKey(const ValueKey('user-block-no')));
    await t.pumpAndSettle();
    expect(done, isFalse);
    expect(find.byKey(const ValueKey('user-block-confirm')), findsNothing);
  });

  test('wired: the profile\'s last row, the chat bar, the server, texts in 6 languages', () {
    final prof = File('lib/features/ads/presentation/public_profile_screen.dart').readAsStringSync();
    expect(prof, contains("ValueKey('profile-block')"));
    expect(prof, contains('if (!isMe && me != null)'), reason: 'never on one\'s own profile / for a visitor');
    expect(prof.indexOf("ValueKey('profile-block')"), greaterThan(prof.indexOf('profile_open_loads')),
        reason: 'at the end of the profile');
    final chat = File('lib/features/chat/presentation/conversation_thread_screen.dart').readAsStringSync();
    expect(chat, contains('ChatBlockedBar('));
    expect(chat, contains("onTap: () => context.pushOnce('/user/\$otherId')"), reason: 'the name opens the profile');
    final sql = File('supabase/migrations/0135_user_blocks.sql').readAsStringSync();
    expect(sql, contains('create trigger zz_messages_user_block before insert on public.messages'));
    expect(sql.contains('drop table'), isFalse);
    expect(sql.contains('delete from messages'), isFalse);
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = File('assets/i18n/$l.json').readAsStringSync();
      for (final k in ['ub_block', 'ub_block_q', 'ub_block_yes', 'ub_unblock', 'ub_chat_i_blocked', 'ub_chat_blocked_me']) {
        expect(j, contains('"$k"'), reason: '$l $k');
      }
    }
  });
}

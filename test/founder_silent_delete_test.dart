// Founder deletes a message without a trace (0048). The server rules are
// tested in supabase/tests/local/86_founder_silent_delete.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/models/group_models.dart';
import 'package:freightlink/models/message_model.dart';

void main() {
  test('the flag is read for direct and group messages (old rows: false)', () {
    final base = {'id': 'm1', 'conversation_id': 'c1', 'sender_id': 'a', 'receiver_id': 'b', 'created_at': '2026-10-21T10:00:00Z'};
    expect(MessageModel.fromJson(base).deletedSilent, isFalse);
    expect(MessageModel.fromJson({...base, 'deleted_silent': true}).deletedSilent, isTrue);
    final g = GroupMessage.fromJson({'id': 'g1', 'group_id': 'gr', 'sender_id': 'a', 'created_at': '2026-10-21T10:00:00Z', 'deleted_silent': true});
    expect(g.deletedSilent, isTrue);
    expect(g.asMessage().deletedSilent, isTrue);
  });

  group('guards', () {
    String read(String p) => File(p).readAsStringSync();
    test('silent messages are not shown and not counted', () {
      expect(read('lib/features/chat/presentation/conversation_thread_screen.dart').contains('if (!m.deletedSilent && visibleToMe('), isTrue);
      expect(read('lib/features/chat/presentation/group_thread_screen.dart').contains('if (!m.deletedSilent && visibleToMe('), isTrue);
      final gp = read('lib/features/chat/presentation/providers/group_providers.dart');
      expect(gp.contains('m.senderId == uid || m.deletedSilent'), isTrue);
      expect(gp.contains('if (m.deletedSilent) continue;'), isTrue);
    });
    test('server: only the founder, only his own message, flag not settable directly', () {
      final sql = read('supabase/migrations/0048_founder_silent_delete.sql');
      expect(sql.contains('v_silent := public.is_founder(v_uid);'), isTrue);
      expect(RegExp(r"if v_sender <> v_uid then raise exception 'not_your_message'; end if;\s+v_silent").hasMatch(sql), isTrue);
      expect(sql.contains('new.deleted_silent := old.deleted_silent;'), isTrue);
      expect(RegExp(r'\b(drop table|truncate|delete from)\b', caseSensitive: false).hasMatch(sql), isFalse);
    });
  });
}

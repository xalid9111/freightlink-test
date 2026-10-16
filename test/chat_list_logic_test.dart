// Messages list: a chat deleted "for me" must not hide that person from
// the people search, and a shown chat must not be listed twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/chat/presentation/chat_list_logic.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1, 10);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  group('partnerRowState', () {
    test('chat without delete is shown', () {
      final s = partnerRowState([(id: 'c1', createdAt: at(0))], activity: {'c1': at(5)}, clears: const {});
      expect(s.visible, isTrue);
      expect(s.last, at(5));
    });

    test('chat deleted after the last message is hidden', () {
      final s = partnerRowState([(id: 'c1', createdAt: at(0))], activity: {'c1': at(5)}, clears: {'c1': at(6)});
      expect(s.visible, isFalse);
    });

    test('a new message after the delete shows the chat again', () {
      final s = partnerRowState([(id: 'c1', createdAt: at(0))], activity: {'c1': at(9)}, clears: {'c1': at(6)});
      expect(s.visible, isTrue);
      expect(s.last, at(9));
    });

    test('several chats with one person: one not deleted = shown', () {
      final s = partnerRowState(
        [(id: 'load', createdAt: at(0)), (id: 'direct', createdAt: at(1))],
        activity: {'load': at(3), 'direct': at(4)},
        clears: {'direct': at(5)},
      );
      expect(s.visible, isTrue);
      expect(s.last, at(4));
    });
  });

  group('peopleWithoutShownChats', () {
    String id(String s) => s;

    test('deleted (hidden) chat partner stays findable', () {
      // Admin deleted the chats with Teymur and Novruz: no row is shown.
      expect(peopleWithoutShownChats(['teymur', 'novruz'], id, <String>{}), ['teymur', 'novruz']);
    });

    test('person whose chat row is on screen is not listed twice', () {
      expect(peopleWithoutShownChats(['teymur', 'novruz', 'ali'], id, {'teymur'}), ['novruz', 'ali']);
    });

    test('no results stay empty', () {
      expect(peopleWithoutShownChats(<String>[], id, {'x'}), isEmpty);
    });
  });
}

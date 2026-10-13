import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/group_models.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/group_repository.dart';

/// My group memberships, live (joins / leaves / read markers).
final myMembershipsProvider = StreamProvider<List<GroupMember>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <GroupMember>[]);
  return ref.watch(groupRepositoryProvider).watchMyMemberships(uid);
});

/// The groups I belong to (re-fetched whenever my memberships change).
final myGroupsProvider = FutureProvider<List<ChatGroup>>((ref) async {
  final ids = ref.watch(myMembershipsProvider.select((v) => (v.valueOrNull ?? const <GroupMember>[]).map((m) => m.groupId).join(',')));
  if (ids.isEmpty) return const <ChatGroup>[];
  return ref.read(groupRepositoryProvider).fetchGroups(ids.split(','));
});

/// Latest messages across my groups (live).
final myGroupMessagesProvider = StreamProvider<List<GroupMessage>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <GroupMessage>[]);
  // re-subscribe when I join / leave a group so RLS-visible rows refresh
  ref.watch(myMembershipsProvider.select((v) => v.valueOrNull?.length));
  return ref.watch(groupRepositoryProvider).watchMyGroupMessages();
});

/// Unread messages per group id (from others, after my last read).
final groupUnreadProvider = Provider<Map<String, int>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final members = ref.watch(myMembershipsProvider).valueOrNull ?? const <GroupMember>[];
  final msgs = ref.watch(myGroupMessagesProvider).valueOrNull ?? const <GroupMessage>[];
  if (uid == null || members.isEmpty) return const <String, int>{};
  final lastRead = {for (final m in members) m.groupId: m.lastReadAt};
  final out = <String, int>{};
  for (final m in msgs) {
    final lr = lastRead[m.groupId];
    if (lr == null || m.senderId == uid) continue;
    if (m.createdAt.isAfter(lr)) out[m.groupId] = (out[m.groupId] ?? 0) + 1;
  }
  return out;
});

final groupUnreadTotalProvider = Provider<int>((ref) {
  return ref.watch(groupUnreadProvider).values.fold(0, (a, b) => a + b);
});

/// Last message time per group (for ordering the list).
final groupLastActivityProvider = Provider<Map<String, DateTime>>((ref) {
  final msgs = ref.watch(myGroupMessagesProvider).valueOrNull ?? const <GroupMessage>[];
  final out = <String, DateTime>{};
  for (final m in msgs) {
    final cur = out[m.groupId];
    if (cur == null || m.createdAt.isAfter(cur)) out[m.groupId] = m.createdAt;
  }
  return out;
});

final groupByIdProvider = FutureProvider.family<ChatGroup?, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupRepositoryProvider).fetchGroup(id);
});

final groupMembersProvider = StreamProvider.autoDispose.family<List<GroupMember>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupRepositoryProvider).watchMembers(id);
});

final groupMessagesProvider = StreamProvider.autoDispose.family<List<GroupMessage>, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(groupRepositoryProvider).watchGroupMessages(id);
});

/// People search by name (empty query → empty list).
final userSearchProvider = FutureProvider.autoDispose.family<List<UserHit>, String>((ref, query) async {
  if (query.trim().length < 2) return const <UserHit>[];
  // small debounce so typing doesn't fire a query per keystroke
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return ref.read(groupRepositoryProvider).searchUsers(query);
});

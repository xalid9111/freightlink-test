import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/presence/online_users.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../models/group_models.dart';
import '../../../repositories/profile_repository.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/chat_delete_repository.dart';
import '../data/group_repository.dart';
import 'providers/group_providers.dart';
import 'widgets/attachment_view.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/location_message.dart';
import 'widgets/message_actions.dart';
import 'widgets/people_picker.dart';
import '../../../core/router/safe_navigation.dart';

/// Real-time group chat: same input bar as 1-to-1 chats (text, photo,
/// file, voice, location); each message from others shows the sender.
class GroupThreadScreen extends ConsumerStatefulWidget {
  final String groupId;
  const GroupThreadScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupThreadScreen> createState() => _GroupThreadScreenState();
}

class _GroupThreadScreenState extends ConsumerState<GroupThreadScreen> {
  int _lastMarkedCount = -1;

  Future<void> _sendText(String text) => ref.read(groupRepositoryProvider).sendText(widget.groupId, text);

  Future<void> _sendAttachment({
    required Uint8List bytes,
    required String type,
    required String fileName,
    String? contentType,
    int? audioDurationMs,
  }) =>
      ref.read(groupRepositoryProvider).sendAttachment(
            groupId: widget.groupId,
            bytes: bytes,
            type: type,
            fileName: fileName,
            contentType: contentType,
            audioDurationMs: audioDurationMs,
          );

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final me = ref.watch(currentUserIdProvider);
    final group = ref.watch(groupByIdProvider(widget.groupId)).valueOrNull;
    final members = ref.watch(groupMembersProvider(widget.groupId)).valueOrNull ?? const <GroupMember>[];
    final messagesAsync = ref.watch(groupMessagesProvider(widget.groupId));

    // Mark the group read whenever new messages are on screen.
    ref.listen<AsyncValue<List<GroupMessage>>>(groupMessagesProvider(widget.groupId), (_, next) {
      final n = next.valueOrNull?.length;
      if (n != null && n != _lastMarkedCount) {
        _lastMarkedCount = n;
        ref.read(groupRepositoryProvider).markRead(widget.groupId);
      }
    });

    return Scaffold(
      backgroundColor: ChatColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => _showInfo(context, strings),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.routeSoft,
                child: Icon(Icons.groups_2_outlined, color: AppColors.route, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(group?.name ?? strings.t('chat_group'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
                    Text(strings.t('chat_group_member_count', {'n': '${members.length}'}),
                        style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: strings.t('chat_group_info'),
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfo(context, strings),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ChatWallpaper(
              child: messagesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(child: Text(strings.t('home_error_loading'))),
                data: (all) {
                  // "Delete for me" / "delete chat" only hide from my view (0031).
                  final hidden = ref.watch(hiddenMessagesProvider).valueOrNull ?? const <String>{};
                  final clears = ref.watch(chatClearsProvider).valueOrNull ?? const <String, DateTime>{};
                  final localDel = ref.watch(locallyDeletedProvider);
                  final messages = [
                    for (final m in all)
                      if (visibleToMe(id: m.id, chatId: m.groupId, createdAt: m.createdAt, hidden: hidden, clears: clears, local: localDel)) m,
                  ];
                  if (messages.isEmpty) return Center(child: Text(strings.t('messages_empty_title')));
                  final sorted = [...messages]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(14),
                    itemCount: sorted.length,
                    itemBuilder: (context, i) {
                      final idx = sorted.length - 1 - i;
                      final m = sorted[idx];
                      final prev = idx > 0 ? sorted[idx - 1] : null;
                      final mine = m.senderId == me;
                      final goneForAll = deletedForAll(m.id, m.isDeleted, localDel);
                      final bubble = _GroupBubble(
                        message: m,
                        isMine: mine,
                        deletedLocally: goneForAll,
                        showSender: !mine && (prev == null || prev.senderId != m.senderId),
                        strings: strings,
                        onLongPress: () => showMessageActions(
                          context: context,
                          ref: ref,
                          strings: strings,
                          messageId: m.id,
                          kind: 'group',
                          isMine: mine,
                          isDeleted: goneForAll,
                          text: m.message,
                        ),
                      );
                      if (prev == null || !ChatDateChip.sameDay(prev.createdAt, m.createdAt)) {
                        return Column(children: [ChatDateChip(day: m.createdAt, strings: strings), bubble]);
                      }
                      return bubble;
                    },
                  );
                },
              ),
              ),
            ),
            ChatInputBar(strings: strings, onSendText: _sendText, onSendAttachment: _sendAttachment),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, AppStrings strings) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _GroupInfoSheet(groupId: widget.groupId, strings: strings),
    );
  }
}

class _SenderName extends ConsumerWidget {
  final String userId;
  const _SenderName(this.userId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(publicProfileProvider(userId)).valueOrNull;
    return GestureDetector(
      onTap: () => context.pushOnce('/user/$userId'),
      child: Text(p?.fullName ?? '…',
          style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _GroupBubble extends StatelessWidget {
  final GroupMessage message;
  final bool isMine;
  final bool showSender;
  final AppStrings strings;
  final VoidCallback onLongPress;
  final bool deletedLocally;
  const _GroupBubble({required this.message, required this.isMine, required this.showSender, required this.strings, required this.onLongPress, this.deletedLocally = false});

  static bool _isBareLocation(String text) {
    final loc = ChatLocation.parse(text);
    if (loc == null) return false;
    return text.replaceAll(loc.url, '').replaceAll('📍', '').trim().isEmpty;
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = message.message;
    final deleted = message.isDeleted || deletedLocally;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
        margin: EdgeInsets.only(top: showSender ? 8 : 3, bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isMine ? ChatColors.mine : ChatColors.theirs,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender) ...[_SenderName(message.senderId), const SizedBox(height: 3)],
            if (deleted) DeletedMessageText(strings: strings),
            if (!deleted && message.hasAttachment)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AttachmentView(message: message.asMessage(), isMine: isMine, strings: strings),
              ),
            if (!deleted)
            if (ChatLocation.parse(text) case final loc?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: LocationCard(location: loc, isMine: isMine, strings: strings),
              ),
            if (!deleted && (text ?? '').isNotEmpty && !_isBareLocation(text!))
              Text(text!, style: TextStyle(color: ChatColors.text, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(_hhmm(message.createdAt), style: TextStyle(fontSize: 11, color: ChatColors.meta)),
          ],
        ),
      ),
      ),
    );
  }
}

/// Members list + admin actions (add, remove, rename) + leave.
class _GroupInfoSheet extends ConsumerWidget {
  final String groupId;
  final AppStrings strings;
  const _GroupInfoSheet({required this.groupId, required this.strings});

  Future<bool> _confirm(BuildContext context, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.t('chat_group_yes'))),
        ],
      ),
    );
    return ok == true;
  }

  void _toast(BuildContext context, String key) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t(key))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final group = ref.watch(groupByIdProvider(groupId)).valueOrNull;
    final members = [...(ref.watch(groupMembersProvider(groupId)).valueOrNull ?? const <GroupMember>[])]
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    final iAmAdmin = members.any((m) => m.userId == me && m.isAdmin);
    final repo = ref.read(groupRepositoryProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(group?.name ?? '', style: AppFonts.display(size: 24, color: AppColors.text)),
              ),
              if (iAmAdmin)
                IconButton(
                  tooltip: strings.t('chat_group_rename'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final ctrl = TextEditingController(text: group?.name ?? '');
                    final name = await showDialog<String>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: Text(strings.t('chat_group_rename')),
                        content: TextField(controller: ctrl, autofocus: true, maxLength: 80),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dctx), child: Text(strings.t('common_cancel'))),
                          FilledButton(onPressed: () => Navigator.pop(dctx, ctrl.text.trim()), child: Text(strings.t('chat_group_save'))),
                        ],
                      ),
                    );
                    ctrl.dispose();
                    if (name == null || name.isEmpty) return;
                    try {
                      await repo.rename(groupId, name);
                      ref.invalidate(groupByIdProvider(groupId));
                      ref.invalidate(myGroupsProvider);
                    } catch (_) {
                      if (context.mounted) _toast(context, 'chat_group_action_failed');
                    }
                  },
                ),
            ],
          ),
          Text(strings.t('chat_group_member_count', {'n': '${members.length}'}),
              style: TextStyle(color: AppColors.textSoft)),
          const SizedBox(height: 12),
          if (iAmAdmin)
            FilledButton.icon(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(strings.t('chat_group_add_members')),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _AddMembersSheet(
                  groupId: groupId,
                  strings: strings,
                  exclude: members.map((m) => m.userId).toSet(),
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final m in members)
            _MemberRow(
              member: m,
              isMe: m.userId == me,
              strings: strings,
              onRemove: (iAmAdmin && m.userId != me)
                  ? () async {
                      if (!await _confirm(context, strings.t('chat_group_remove_confirm'))) return;
                      try {
                        await repo.removeMember(groupId, m.userId);
                      } catch (_) {
                        if (context.mounted) _toast(context, 'chat_group_action_failed');
                      }
                    }
                  : null,
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.danger)),
            icon: const Icon(Icons.logout),
            label: Text(strings.t('chat_group_leave')),
            onPressed: me == null
                ? null
                : () async {
                    if (!await _confirm(context, strings.t('chat_group_leave_confirm'))) return;
                    if (!context.mounted) return;
                    final router = GoRouter.of(context);
                    final nav = Navigator.of(context);
                    try {
                      await repo.removeMember(groupId, me);
                      ref.invalidate(myGroupsProvider);
                      nav.pop();
                      router.go('/messages');
                    } catch (_) {
                      if (context.mounted) _toast(context, 'chat_group_action_failed');
                    }
                  },
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final GroupMember member;
  final bool isMe;
  final AppStrings strings;
  final VoidCallback? onRemove;
  const _MemberRow({required this.member, required this.isMe, required this.strings, this.onRemove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(publicProfileProvider(member.userId)).valueOrNull;
    final online = ref.watch(isUserOnlineProvider(member.userId));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.pushOnce('/user/${member.userId}'),
      leading: UserAvatar(imageUrl: p?.avatarUrl, initials: p?.initials ?? '?', online: online),
      title: Text(isMe ? '${p?.fullName ?? ''} (${strings.t('chat_group_you')})' : (p?.fullName ?? '…'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: member.isAdmin ? Text(strings.t('chat_group_admin'), style: TextStyle(color: AppColors.accent)) : null,
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: strings.t('chat_group_remove'),
              icon: Icon(Icons.remove_circle_outline, color: AppColors.danger),
              onPressed: onRemove,
            ),
    );
  }
}

class _AddMembersSheet extends ConsumerStatefulWidget {
  final String groupId;
  final AppStrings strings;
  final Set<String> exclude;
  const _AddMembersSheet({required this.groupId, required this.strings, required this.exclude});

  @override
  ConsumerState<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends ConsumerState<_AddMembersSheet> {
  final Map<String, UserHit> _selected = {};
  bool _busy = false;

  Future<void> _add() async {
    if (_selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(groupRepositoryProvider).addMembers(widget.groupId, _selected.keys.toList());
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.strings.t('chat_group_action_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
        children: [
          Row(
            children: [
              Expanded(child: Text(s.t('chat_group_add_members'), style: Theme.of(context).textTheme.titleMedium)),
              FilledButton(
                onPressed: _busy || _selected.isEmpty ? null : _add,
                child: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s.t('chat_group_add_n', {'n': '${_selected.length}'})),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PeoplePicker(
            strings: s,
            selected: _selected,
            exclude: widget.exclude,
            onToggle: (u) => setState(() {
              if (_selected.containsKey(u.id)) {
                _selected.remove(u.id);
              } else {
                _selected[u.id] = u;
              }
            }),
          ),
        ],
      ),
    );
  }
}

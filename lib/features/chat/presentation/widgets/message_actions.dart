import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/chat_delete_repository.dart';
import '../providers/chat_providers.dart';
import '../providers/group_providers.dart';

/// Long-press menu on a message (WhatsApp-style): copy, delete for me,
/// and — only for my own, not yet deleted message — delete for everyone.
Future<void> showMessageActions({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings strings,
  required String messageId,
  required String kind, // 'direct' | 'group'
  required bool isMine,
  required bool isDeleted,
  String? text,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.card,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((text ?? '').trim().isNotEmpty && !isDeleted)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(strings.t('chat_copy')),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: AppColors.danger),
            title: Text(strings.t('chat_delete_for_me')),
            onTap: () => Navigator.pop(ctx, 'me'),
          ),
          if (isMine && !isDeleted)
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: AppColors.danger),
              title: Text(strings.t('chat_delete_for_everyone')),
              onTap: () => Navigator.pop(ctx, 'everyone'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (action == 'copy') {
    await Clipboard.setData(ClipboardData(text: text ?? ''));
    messenger.showSnackBar(SnackBar(content: Text(strings.t('chat_copied'))));
    return;
  }
  final everyone = action == 'everyone';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(strings.t(everyone ? 'chat_delete_for_everyone' : 'chat_delete_for_me')),
      content: Text(strings.t(everyone ? 'chat_delete_everyone_body' : 'chat_delete_me_body')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.t('common_cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.t('chat_delete'))),
      ],
    ),
  );
  if (ok != true) return;
  // Hide / blank it on screen right away; the server result follows.
  final local = ref.read(locallyDeletedProvider.notifier);
  final key = everyone ? 'all:$messageId' : 'me:$messageId';
  local.state = {...local.state, key};
  try {
    await ref.read(chatDeleteRepositoryProvider).deleteMessage(messageId, kind: kind, everyone: everyone);
    if (everyone) {
      // Don't rely only on the realtime UPDATE event (iOS Safari often drops
      // the socket): re-read the messages from the server.
      if (kind == 'group') {
        ref.invalidate(myGroupMessagesProvider);
      } else {
        ref.invalidate(conversationMessagesProvider);
      }
    } else {
      await ref.refresh(hiddenMessagesProvider.future);
    }
    ref.invalidate(chatActivityProvider);
  } catch (e) {
    local.state = {...local.state}..remove(key);
    messenger.showSnackBar(SnackBar(content: Text(strings.t(deleteErrorKey(e)))));
  }
}

/// 'chat_delete_server_missing' when migration 0031 has not been run on
/// the database yet (the RPC / table does not exist), otherwise the
/// generic failure text.
String deleteErrorKey(Object e) {
  final m = '$e'.toLowerCase();
  final missing = m.contains('pgrst202') ||
      m.contains('42883') ||
      m.contains('42p01') ||
      m.contains('could not find the function') ||
      (m.contains('function') && m.contains('does not exist'));
  return missing ? 'chat_delete_server_missing' : 'chat_delete_failed';
}

/// Confirm + clear a whole chat (person or group) for me.
Future<void> confirmClearChat({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings strings,
  required String targetId,
  required String kind,
}) async {
  final ok = await confirmClearChatDialog(context, strings);
  if (ok != true || !context.mounted) return;
  await clearChatNow(context: context, ref: ref, strings: strings, targetId: targetId, kind: kind);
}

Future<bool?> confirmClearChatDialog(BuildContext context, AppStrings strings) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('chat_delete_chat')),
        content: Text(strings.t('chat_delete_chat_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.t('chat_delete'))),
        ],
      ),
    );

Future<void> clearChatNow({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings strings,
  required String targetId,
  required String kind,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final n = await ref.read(chatDeleteRepositoryProvider).clearChat(targetId, kind: kind);
    if (n == 0) {
      // Nothing was stored — never say "deleted" when it was not.
      messenger.showSnackBar(SnackBar(content: Text(strings.t('chat_delete_failed'))));
      return;
    }
    // Wait for the new list of cleared chats so the row disappears now.
    await ref.refresh(chatClearsProvider.future);
    ref.invalidate(chatActivityProvider);
    messenger.showSnackBar(SnackBar(content: Text(strings.t('chat_chat_deleted'))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(strings.t(deleteErrorKey(e)))));
  }
}

/// "🚫 This message was deleted" line used inside bubbles.
class DeletedMessageText extends StatelessWidget {
  final AppStrings strings;
  const DeletedMessageText({super.key, required this.strings});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block, size: 15, color: ChatColors.meta),
        const SizedBox(width: 6),
        Flexible(
          child: Text(strings.t('chat_message_deleted'),
              style: TextStyle(color: ChatColors.meta, fontStyle: FontStyle.italic, fontSize: 14)),
        ),
      ],
    );
  }
}

/// Centred day label in a chat ("Bu gün", "Dünən", "12.10.2026").
class ChatDateChip extends StatelessWidget {
  final DateTime day;
  final AppStrings strings;
  const ChatDateChip({super.key, required this.day, required this.strings});

  static bool sameDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final d = day.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final label = sameDay(d, now)
        ? strings.t('chat_today')
        : sameDay(d, now.subtract(const Duration(days: 1)))
            ? strings.t('chat_day_yesterday')
            : '${two(d.day)}.${two(d.month)}.${d.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: ChatColors.dateChip, borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: TextStyle(color: ChatColors.meta, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Subtle dotted wallpaper behind chats (WhatsApp-like).
class ChatWallpaper extends StatelessWidget {
  final Widget child;
  const ChatWallpaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DotsPainter(), child: child);
  }
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = ChatColors.background);
    final p = Paint()..color = ChatColors.dots;
    const step = 26.0;
    for (var y = 8.0; y < size.height; y += step) {
      final shift = ((y / step).floor().isOdd) ? step / 2 : 0.0;
      for (var x = 8.0 + shift; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.4, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

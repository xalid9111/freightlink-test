import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/presence/online_users.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../repositories/profile_repository.dart';
import '../../../models/message_model.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/chat_delete_repository.dart';
import 'providers/chat_providers.dart';
import 'widgets/attachment_view.dart';
import 'widgets/call_options.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/location_message.dart';
import 'widgets/message_actions.dart';
import '../../../core/router/safe_navigation.dart';

/// ONE thread per person (WhatsApp-style).
///
/// Every load has its own conversation row with that person, plus an
/// optional direct chat (DB unchanged — nothing is merged or moved). This
/// screen shows ALL of them as one timeline: messages from every
/// conversation with the person, oldest at the top. Where the subject
/// changes, a small topic chip ("🚚 Azərbaycan → Gürcüstan" / "Şəxsi
/// söhbət") is shown in the timeline. New messages go to the topic of the
/// latest message unless the user taps another topic (chips above the
/// input, or a chip in the timeline).
///
/// Opened either with [otherUserId] (from the messages list) or with a
/// [conversationId] (cargo detail, notifications) — then that topic is
/// pre-selected. Real-time via Supabase Realtime (watchConversation).
class ConversationThreadScreen extends ConsumerStatefulWidget {
  final String? conversationId;
  final String? otherUserId;
  const ConversationThreadScreen({super.key, this.conversationId, this.otherUserId})
      : assert(conversationId != null || otherUserId != null);

  @override
  ConsumerState<ConversationThreadScreen> createState() => _ConversationThreadScreenState();
}

class _ConversationThreadScreenState extends ConsumerState<ConversationThreadScreen> {
  final _scrollCtrl = ScrollController();

  /// Topic picked by the user (conversation id); null = follow the latest.
  String? _picked;

  /// Conversation new messages are sent to (resolved on every build).
  String? _target;

  /// Conversations currently being marked read (avoids repeated calls).
  final Set<String> _marking = {};

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// "14:05" today, "dünən 22:10" yesterday, otherwise "5 Okt 14:05".
  static String _lastSeen(DateTime t, AppStrings strings) {
    final l = t.toLocal();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(l.hour)}:${two(l.minute)}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(l.year, l.month, l.day);
    if (day == today) return hm;
    if (day == today.subtract(const Duration(days: 1))) return '${strings.t('chat_yesterday')} $hm';
    return '${two(l.day)}.${two(l.month)} $hm';
  }

  static String _initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = String.fromCharCode(parts.first.runes.first);
    final second = parts.length > 1 ? String.fromCharCode(parts[1].runes.first) : '';
    return (first + second).toUpperCase();
  }

  /// Sender / receiver for [conversationId], from the conversation row
  /// itself (fetched by id — never from the possibly stale list).
  Future<({String me, String other, String conversationId})> _participants() async {
    final user = ref.read(currentUserProvider);
    if (user == null) throw StateError('not_signed_in');
    final id = _target ?? widget.conversationId;
    if (id == null) throw StateError('conversation_not_found');
    var conv = ref.read(conversationByIdProvider(id)).valueOrNull;
    conv ??= await ref.read(conversationByIdProvider(id).future);
    if (conv == null) throw StateError('conversation_not_found');
    if (user.id != conv.cargoOwnerId && user.id != conv.carrierUserId) {
      throw StateError('not_a_participant');
    }
    return (me: user.id, other: conv.otherParticipant(user.id), conversationId: id);
  }

  // Errors are thrown on purpose: ChatInputBar keeps the text and shows
  // "Not sent" instead of failing silently.
  Future<void> _sendText(String text) async {
    final p = await _participants();
    await ref.read(messageRepositoryProvider).send(
          conversationId: p.conversationId,
          senderId: p.me,
          receiverId: p.other,
          message: text,
        );
  }

  Future<void> _sendAttachment({
    required Uint8List bytes,
    required String type,
    required String fileName,
    String? contentType,
    int? audioDurationMs,
  }) async {
    final p = await _participants();
    await ref.read(messageRepositoryProvider).sendAttachment(
          conversationId: p.conversationId,
          senderId: p.me,
          receiverId: p.other,
          bytes: bytes,
          type: type,
          fileName: fileName,
          contentType: contentType,
          audioDurationMs: audioDurationMs,
        );
  }

  /// "🇦🇿 Azərbaycan → 🇬🇪 Gürcüstan" for a load chat, "Şəxsi söhbət" for
  /// the direct chat.
  String _topicLabel(ConversationWithCargo t, AppStrings strings, String lang) {
    if (t.conversation.cargoId == null) return strings.t('chat_direct');
    final c = t.cargo;
    if (c == null) return strings.t('chat_load_topic');
    return '${Countries.label(c.pickupCountry, lang)} → ${Countries.label(c.destinationCountry, lang)}';
  }

  void _markRead(String conversationId, String me) {
    if (_marking.contains(conversationId)) return;
    _marking.add(conversationId);
    ref
        .read(messageRepositoryProvider)
        .markConversationRead(conversationId: conversationId, userId: me)
        .catchError((_) {})
        .whenComplete(() => _marking.remove(conversationId));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final user = ref.watch(currentUserProvider);
    final me = user?.id;

    // Who we are talking to.
    final opened = widget.conversationId == null ? null : ref.watch(conversationByIdProvider(widget.conversationId!));
    final openedConv = opened?.valueOrNull;
    final String? otherId = widget.otherUserId ?? ((me != null && openedConv != null) ? openedConv.otherParticipant(me) : null);

    // Every conversation with that person = the topics of this thread.
    final allAsync = ref.watch(myConversationsProvider);
    final topics = <ConversationWithCargo>[
      for (final c in allAsync.valueOrNull ?? const <ConversationWithCargo>[])
        if (me != null && otherId != null && c.conversation.otherParticipant(me) == otherId) c,
    ];
    // The list can lag right after a chat was created: keep the opened one.
    if (openedConv != null && !topics.any((t) => t.conversation.id == openedConv.id)) {
      topics.add(ConversationWithCargo(conversation: openedConv, cargo: null));
    }
    final topicById = {for (final t in topics) t.conversation.id: t};

    // Messages of all topics, merged into one timeline.
    final perTopic = [for (final t in topics) ref.watch(conversationMessagesProvider(t.conversation.id))];
    final anyData = perTopic.any((a) => a.hasValue);
    final anyError = perTopic.any((a) => a.hasError);
    // "Delete for me" (single messages) and "delete chat" (everything up
    // to that moment) only hide things from my own view — migration 0031.
    final hidden = ref.watch(hiddenMessagesProvider).valueOrNull ?? const <String>{};
    final clears = ref.watch(chatClearsProvider).valueOrNull ?? const <String, DateTime>{};
    final localDel = ref.watch(locallyDeletedProvider);
    final merged = <MessageModel>[
      for (final a in perTopic)
        for (final m in (a.valueOrNull ?? const <MessageModel>[]))
          if (visibleToMe(id: m.id, chatId: m.conversationId, createdAt: m.createdAt, hidden: hidden, clears: clears, local: localDel)) m,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Mark what I received as read, in every topic.
    if (me != null) {
      final unreadTopics = {for (final m in merged) if (m.receiverId == me && m.readAt == null) m.conversationId};
      if (unreadTopics.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          for (final id in unreadTopics) {
            _markRead(id, me);
          }
        });
      }
    }

    // Where a new message goes: the picked topic, else the opened one (until
    // the user writes elsewhere), else the topic of the latest message.
    String? target = _picked;
    if (target == null || !topicById.containsKey(target)) {
      target = widget.conversationId != null && topicById.containsKey(widget.conversationId)
          ? widget.conversationId
          : (merged.isNotEmpty ? merged.last.conversationId : (topics.isNotEmpty ? topics.first.conversation.id : null));
    }
    _target = target;

    final otherProfile = otherId == null ? null : ref.watch(publicProfileProvider(otherId)).valueOrNull;
    final otherName = otherProfile?.fullName;
    final otherOnline = otherId != null && ref.watch(isUserOnlineProvider(otherId));

    final loading = (topics.isEmpty && (allAsync.isLoading || (opened?.isLoading ?? false))) ||
        (topics.isNotEmpty && !anyData && !anyError);

    // Timeline rows: messages plus a topic chip wherever the subject changes.
    final rows = <Object>[]; // MessageModel | ConversationWithCargo (chip) | DateTime (day)
    String? prevTopic;
    DateTime? prevDay;
    for (final m in merged) {
      if (prevDay == null || !ChatDateChip.sameDay(prevDay, m.createdAt)) {
        rows.add(m.createdAt);
        prevDay = m.createdAt;
      }
      if (topics.length > 1 && m.conversationId != prevTopic) {
        final t = topicById[m.conversationId];
        if (t != null) rows.add(t);
      }
      prevTopic = m.conversationId;
      rows.add(m);
    }

    return Scaffold(
      backgroundColor: ChatColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        actions: [
          // WhatsApp-style: shop icon → the person's profile / catalog.
          if (otherId != null)
            IconButton(
              tooltip: strings.t('profile_catalog'),
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () => context.pushOnce('/user/$otherId/catalog'),
            ),
          if (otherId != null)
            IconButton(
              tooltip: strings.t('chat_call'),
              icon: const Icon(Icons.call_outlined),
              onPressed: () async {
                // The other person's phone is released by the server only
                // when there is a reason (e.g. they have written to you) —
                // RPC get_user_contact, migration 0019. Fetched on tap.
                final messenger = ScaffoldMessenger.of(context);
                String? phone;
                try {
                  phone = (await ref.read(profileRepositoryProvider).contact(otherId)).phone;
                } catch (_) {
                  messenger.showSnackBar(SnackBar(content: Text(strings.t('error_generic'))));
                  return;
                }
                if (!context.mounted) return;
                if (phone == null || phone.trim().isEmpty) {
                  messenger.showSnackBar(SnackBar(content: Text(strings.t('chat_no_phone'))));
                  return;
                }
                showCallOptions(context, strings, phone.trim());
              },
            ),
          const SizedBox(width: 4),
        ],
        title: otherId == null
            ? Text(strings.t('nav_messages'))
            : InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.pushOnce('/user/$otherId'),
                child: Row(
                  children: [
                    UserAvatar(imageUrl: otherProfile?.avatarUrl, initials: _initials(otherName), online: otherOnline),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(otherName ?? strings.t('nav_messages'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
                              ),
                              if (otherProfile?.isVerified == true) ...[
                                const SizedBox(width: 4),
                                const VerifiedTick(),
                              ],
                            ],
                          ),
                          Text(
                            otherOnline
                                ? strings.t('chat_online')
                                : (otherProfile?.lastSeenAt != null
                                    ? strings.t('chat_last_seen', {'time': _lastSeen(otherProfile!.lastSeenAt!, strings)})
                                    : strings.t('chat_offline')),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: otherOnline ? AppColors.online : AppColors.textSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ChatWallpaper(
                child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : (anyError && !anyData)
                      ? Center(child: Text(strings.t('home_error_loading')))
                      : rows.isEmpty
                          ? Center(child: Text(strings.t('messages_empty_title')))
                          // WhatsApp-style: oldest at the top, newest at the
                          // bottom; `reverse: true` keeps the view anchored to
                          // the bottom, so index 0 = newest row.
                          : ListView.builder(
                              controller: _scrollCtrl,
                              reverse: true,
                              padding: const EdgeInsets.all(14),
                              itemCount: rows.length,
                              itemBuilder: (context, i) {
                                final row = rows[rows.length - 1 - i];
                                if (row is ConversationWithCargo) {
                                  return _TopicMarker(
                                    label: _topicLabel(row, strings, lang),
                                    isLoad: row.conversation.cargoId != null,
                                    selected: row.conversation.id == target,
                                    onTap: () => setState(() => _picked = row.conversation.id),
                                  );
                                }
                                if (row is DateTime) return ChatDateChip(day: row, strings: strings);
                                final m = row as MessageModel;
                                final mine = me != null && m.senderId == me;
                                final goneForAll = deletedForAll(m.id, m.isDeleted, localDel);
                                return _MessageBubble(
                                  message: m,
                                  isMine: mine,
                                  deletedLocally: goneForAll,
                                  strings: strings,
                                  onLongPress: () => showMessageActions(
                                    context: context,
                                    ref: ref,
                                    strings: strings,
                                    messageId: m.id,
                                    kind: 'direct',
                                    isMine: mine,
                                    isDeleted: goneForAll,
                                    text: m.message,
                                  ),
                                );
                              },
                            ),
              ),
            ),
            // The "Mövzu:" chip row under the chat was removed (owner's
            // request). Messages go to the latest topic by default; tapping a
            // topic marker in the timeline still switches where you write.
            ChatInputBar(
              strings: strings,
              onSendText: _sendText,
              onSendAttachment: _sendAttachment,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small centred chip in the timeline where the subject changes.
class _TopicMarker extends StatelessWidget {
  final String label;
  final bool isLoad;
  final bool selected;
  final VoidCallback onTap;
  const _TopicMarker({required this.label, required this.isLoad, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? AppColors.accent : AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isLoad ? Icons.local_shipping_outlined : Icons.chat_bubble_outline, size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final AppStrings strings;
  final VoidCallback onLongPress;
  final bool deletedLocally;
  const _MessageBubble({required this.message, required this.isMine, required this.strings, required this.onLongPress, this.deletedLocally = false});

  static bool _isBareLocation(String text) {
    final loc = ChatLocation.parse(text);
    if (loc == null) return false;
    final rest = text.replaceAll(loc.url, '').replaceAll('📍', '').trim();
    return rest.isEmpty;
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final deleted = message.isDeleted || deletedLocally;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          // WhatsApp-like colours so chatting feels familiar; the tail
          // corner points to the sender.
          color: isMine ? ChatColors.mine : ChatColors.theirs,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMine ? 14 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (deleted) DeletedMessageText(strings: strings),
            if (!deleted && message.hasAttachment)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: AttachmentView(message: message, isMine: isMine, strings: strings),
              ),
            if (!deleted)
            if (ChatLocation.parse(message.message) case final loc?)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: LocationCard(location: loc, isMine: isMine, strings: strings),
              ),
            // Our own "📍 <link>" messages are fully represented by the
            // card; any other text (incl. pasted links with a caption)
            // is still shown.
            if (!deleted && (message.message ?? '').isNotEmpty && !_isBareLocation(message.message!))
              Text(
                message.message!,
                style: const TextStyle(color: Colors.white, fontSize: 14.5),
              ),
            const SizedBox(height: 2),
            // Send time (HH:mm, device local time) and, on my own
            // messages, WhatsApp-style ticks: ✓ sent, ✓✓ read.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _hhmm(message.createdAt),
                  style: const TextStyle(fontSize: 11, color: ChatColors.meta),
                ),
                if (isMine && !deleted) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readAt != null ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.readAt != null ? ChatColors.readTick : ChatColors.meta,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

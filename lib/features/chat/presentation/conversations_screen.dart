import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/constants/countries.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../../core/presence/online_users.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../models/group_models.dart';
import '../../../repositories/profile_repository.dart';
import '../data/chat_delete_repository.dart';
import '../data/group_repository.dart';
import 'chat_list_logic.dart';
import 'providers/chat_providers.dart';
import 'widgets/message_actions.dart';
import 'providers/group_providers.dart';
import '../../../core/router/safe_navigation.dart';

/// Bottom-nav "Messages" tab: search box on top, then groups and chats
/// (newest activity first). Typing a name filters the list AND shows
/// matching people from the whole platform, so you can start a direct
/// chat with anyone.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _Entry {
  final DateTime time;
  final Widget tile;
  const _Entry(this.time, this.tile);
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  String? _opening; // user id whose direct chat is being opened

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matches(String text) => _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  Future<void> _openDirect(UserHit u, AppStrings strings) async {
    if (_opening != null) return;
    setState(() => _opening = u.id);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(u.id);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/messages/${conv.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('chat_open_failed'))));
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final user = ref.watch(currentUserProvider);
    final conversationsAsync = ref.watch(myConversationsProvider);
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final unreadByConversation = ref.watch(unreadByConversationProvider).valueOrNull ?? const <String, int>{};
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const <ChatGroup>[];
    final groupUnread = ref.watch(groupUnreadProvider);
    final groupActivity = ref.watch(groupLastActivityProvider);
    // Chats I deleted "for me" stay hidden until a newer message arrives
    // (migration 0031); the list is sorted by the latest message.
    final clears = ref.watch(chatClearsProvider).valueOrNull ?? const <String, DateTime>{};
    final activity = ref.watch(chatActivityProvider).valueOrNull ?? const <String, DateTime>{};
    // Refresh the activity map whenever my unread counts change (new message).
    ref.listen(unreadByConversationProvider, (_, __) => ref.invalidate(chatActivityProvider));

    final entries = <_Entry>[];

    Widget deletable({required Widget child, required String key, required String targetId, required String kind}) {
      return _Deletable(
        key: ValueKey('del-$key'),
        strings: strings,
        onDelete: () => clearChatNow(context: context, ref: ref, strings: strings, targetId: targetId, kind: kind),
        onLongPress: () => confirmClearChat(context: context, ref: ref, strings: strings, targetId: targetId, kind: kind),
        child: child,
      );
    }

    // Groups
    for (final g in groups) {
      if (!_matches(g.name)) continue;
      final last = groupActivity[g.id] ?? g.createdAt;
      final cleared = clears[g.id];
      if (cleared != null && !last.isAfter(cleared)) continue;
      entries.add(_Entry(
        last,
        deletable(
          key: 'g${g.id}',
          targetId: g.id,
          kind: 'group',
          child: _GroupTile(
            group: g,
            unread: groupUnread[g.id] ?? 0,
            label: strings.t('chat_group'),
            onTap: () => context.pushOnce('/messages/group/${g.id}'),
          ),
        ),
      ));
    }

    // 1-to-1 chats — ONE row per person. Every load has its own chat with
    // that person (plus an optional direct chat); they are grouped here and
    // a tap opens ONE thread with all of them (ConversationThreadScreen).
    final items = conversationsAsync.valueOrNull ?? const <ConversationWithCargo>[];
    // People whose chat row is ON THE SCREEN. A chat I deleted is hidden,
    // so that person must stay findable in the people search below.
    final shownPartnerIds = <String>{};
    final byPartner = <String, List<ConversationWithCargo>>{};
    for (final item in items) {
      final otherId = user == null ? item.conversation.carrierUserId : item.conversation.otherParticipant(user.id);
      (byPartner[otherId] ??= []).add(item);
    }
    String routeOf(ConversationWithCargo item) {
      final cargo = item.conversation.cargoId == null ? null : item.cargo;
      final iAmOwner = user != null && user.id == item.conversation.cargoOwnerId;
      final subtitleKey = item.conversation.cargoId == null
          ? 'chat_direct'
          : (iAmOwner ? 'conversation_with_carrier' : 'conversation_with_owner');
      return cargo == null
          ? strings.t(subtitleKey)
          : '${Countries.label(cargo.pickupCountry, localeCode)} → ${Countries.label(cargo.destinationCountry, localeCode)}';
    }

    for (final e in byPartner.entries) {
      final otherId = e.key;
      final convs = [...e.value]..sort((a, b) => b.conversation.createdAt.compareTo(a.conversation.createdAt));
      final latest = convs.first;
      final iAmOwner = user != null && user.id == latest.conversation.cargoOwnerId;
      final subtitleKey = latest.conversation.cargoId == null
          ? 'chat_direct'
          : (iAmOwner ? 'conversation_with_carrier' : 'conversation_with_owner');
      final routes = convs.map(routeOf).toList();
      final route = convs.length == 1 ? routes.first : '${routes.first} · ${strings.t('chat_n_chats', {'n': '${convs.length}'})}';
      final name = ref.watch(publicProfileProvider(otherId)).valueOrNull?.fullName ?? '';
      if (!_matches('$name ${routes.join(' ')}')) continue;
      final unread = convs.fold<int>(0, (sum, c) => sum + (unreadByConversation[c.conversation.id] ?? 0));
      // Latest activity with this person, and whether any chat with them
      // still has something I have not deleted.
      final state = partnerRowState(
        [for (final c in convs) (id: c.conversation.id, createdAt: c.conversation.createdAt)],
        activity: activity,
        clears: clears,
      );
      if (!state.visible) continue;
      final last = state.last;
      shownPartnerIds.add(otherId);
      entries.add(_Entry(
        last,
        deletable(
          key: 'u$otherId',
          targetId: otherId,
          kind: 'direct',
          child: _ConversationTile(
            otherUserId: otherId,
            route: route,
            roleLabel: strings.t(subtitleKey),
            unread: unread,
            // One thread per person: all load chats + the direct chat together.
            onTap: () => context.pushOnce('/messages/with/$otherId'),
          ),
        ),
      ));
    }
    entries.sort((a, b) => b.time.compareTo(a.time));

    // People search (whole platform) while typing
    final people = _query.length >= 2 ? ref.watch(userSearchProvider(_query)) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t('messages_placeholder_title')),
        actions: [
          IconButton(
            tooltip: strings.t('chat_new_group'),
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => context.pushOnce('/messages/new-group'),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: strings.t('chat_search_hint'),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myConversationsProvider);
          ref.invalidate(myGroupsProvider);
          ref.invalidate(chatClearsProvider);
          ref.invalidate(chatActivityProvider);
        },
        child: conversationsAsync.isLoading && entries.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                children: [
                  if (conversationsAsync.hasError && entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(strings.t('home_error_loading'))),
                    ),
                  if (entries.isEmpty && _query.isEmpty && !conversationsAsync.hasError)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 44, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(strings.t('messages_empty_title')),
                          const SizedBox(height: 6),
                          Text(strings.t('chat_empty_hint'),
                              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                        ],
                      ),
                    ),
                  for (final e in entries) Padding(padding: const EdgeInsets.only(bottom: 6), child: e.tile),
                  if (people != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                      child: Text(strings.t('chat_people').toUpperCase(),
                          style: TextStyle(color: AppColors.textSoft, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w500)),
                    ),
                    people.when(
                      loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                      error: (_, __) => Text(strings.t('home_error_loading')),
                      data: (list) {
                        final others = peopleWithoutShownChats(list, (UserHit u) => u.id, shownPartnerIds);
                        if (others.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(strings.t('chat_search_nobody'), style: TextStyle(color: AppColors.textSoft)),
                          );
                        }
                        return Column(
                          children: [
                            for (final u in others)
                              Card(
                                child: ListTile(
                                  leading: GestureDetector(
                                    onTap: () => context.pushOnce('/user/${u.id}'),
                                    child: UserAvatar(imageUrl: u.avatarUrl, initials: u.initials, online: ref.watch(isUserOnlineProvider(u.id))),
                                  ),
                                  title: Text(u.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: u.role == null ? null : Text(strings.t('role_label_${u.role}')),
                                  trailing: _opening == u.id
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Icon(Icons.chat_bubble_outline, color: AppColors.accent),
                                  onTap: () => _openDirect(u, strings),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Swipe left (WhatsApp-style) shows a red "Delete" area; releasing asks
/// for confirmation and deletes the chat for me only. Long-press does the
/// same through a dialog.
class _Deletable extends StatelessWidget {
  final Widget child;
  final AppStrings strings;
  final Future<void> Function() onDelete;
  final VoidCallback onLongPress;
  const _Deletable({super.key, required this.child, required this.strings, required this.onDelete, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: key!,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(18)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, color: Colors.white),
            const SizedBox(width: 6),
            Text(strings.t('chat_delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final ok = await confirmClearChatDialog(context, strings);
        if (ok == true) await onDelete();
        // The list itself drops the row once the clear is stored.
        return false;
      },
      child: GestureDetector(onLongPress: onLongPress, child: child),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(12)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final ChatGroup group;
  final int unread;
  final String label;
  final VoidCallback onTap;
  const _GroupTile({required this.group, required this.unread, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.routeSoft,
                child: Icon(Icons.groups_2_outlined, color: AppColors.route),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text)),
                    const SizedBox(height: 3),
                    Text(label, style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
                  ],
                ),
              ),
              if (unread > 0) _UnreadBadge(unread),
            ],
          ),
        ),
      ),
    );
  }
}

/// One conversation: the other party's photo (with online dot), the name
/// they registered with (company or person) + verified tick, the route
/// underneath, and an unread counter.
class _ConversationTile extends ConsumerWidget {
  final String otherUserId;
  final String route;
  final String roleLabel;
  final int unread;
  final VoidCallback onTap;
  const _ConversationTile({
    required this.otherUserId,
    required this.route,
    required this.roleLabel,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(publicProfileProvider(otherUserId)).valueOrNull;
    final online = ref.watch(isUserOnlineProvider(otherUserId));
    final name = (profile?.fullName.isNotEmpty ?? false) ? profile!.fullName : roleLabel;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.pushOnce('/user/$otherUserId'),
                child: UserAvatar(
                  imageUrl: profile?.avatarUrl,
                  initials: profile?.initials ?? '?',
                  radius: 24,
                  online: online,
                ),
              ),
              const SizedBox(width: 12),
              // Name / route: tapping opens the chat (the avatar opens the profile).
              Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text),
                              ),
                            ),
                            if (profile?.isVerified == true) ...[
                              const SizedBox(width: 4),
                              const VerifiedTick(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          route,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
                        ),
                      ],
                    ),
                ),
              ),
              if (unread > 0) _UnreadBadge(unread),
            ],
          ),
        ),
      ),
    );
  }
}

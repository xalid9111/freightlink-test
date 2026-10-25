import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/chat/presentation/providers/group_providers.dart';
import '../../repositories/profile_repository.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/user_avatar.dart';

/// Computer view, top right of a page: a search field (optional), the
/// bell (unread messages → Mesajlar) and my account (→ Profil). Same look
/// as on the desktop Yüklər page.
class DeskHeaderActions extends ConsumerWidget {
  final AppStrings strings;
  final Widget? search;
  const DeskHeaderActions({super.key, required this.strings, this.search});

  /// Glass pill behind the header controls.
  static BoxDecoration pill() => BoxDecoration(
        color: AppColors.isDay ? Colors.white.withValues(alpha: 0.92) : AppColors.card.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.line),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings;
    final unread = (ref.watch(unreadCountProvider).valueOrNull ?? 0) + ref.watch(groupUnreadTotalProvider);
    final uid = ref.watch(currentUserIdProvider);
    final me = ref.watch(currentUserProvider);
    final profile = uid == null ? null : ref.watch(publicProfileProvider(uid)).valueOrNull;
    final name = (profile?.fullName ?? me?.fullName ?? '').trim();
    final first = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    final initials = name.isEmpty
        ? '?'
        : name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p.characters.first.toUpperCase()).join();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (search != null) Flexible(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: search!)),
        const SizedBox(width: 14),
        Tooltip(
          message: s.t('nav_messages'),
          child: InkWell(
            key: const ValueKey('desk-bell'),
            customBorder: const CircleBorder(),
            onTap: () => context.go('/messages'),
            child: Container(
              width: 54,
              height: 54,
              decoration: pill(),
              alignment: Alignment.center,
              child: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 99 ? '99+' : '$unread'),
                backgroundColor: AppColors.danger,
                child: Icon(Icons.notifications_none, color: AppColors.text, size: 26),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        InkWell(
          key: const ValueKey('desk-account'),
          borderRadius: BorderRadius.circular(28),
          onTap: () => context.go('/profile'),
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: pill(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(imageUrl: profile?.avatarUrl, initials: initials, radius: 21),
                if (first.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 140),
                    child: Text(first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text)),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(Icons.expand_more, color: AppColors.textSoft),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

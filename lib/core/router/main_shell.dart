import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../localization/locale_controller.dart';
import '../presence/online_users.dart';
import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/chat/presentation/providers/group_providers.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../repositories/profile_repository.dart';
import '../theme/app_theme.dart';
import '../notify/message_alert.dart';
import '../notify/notify_settings.dart';
import '../../models/group_models.dart';
import 'safe_navigation.dart';

/// Bottom navigation shell (brief §14): Home/Loads, Search, Shipments,
/// Services, Messages, Profile — wraps all 6 authenticated branches. Uses
/// go_router's StatefulShellRoute so each tab keeps its own navigation
/// stack and scroll position when switching away and back, instead of
/// a plain IndexedStack hand-rolled in application code.
final NavDebounce _tabGuard = NavDebounce(window: const Duration(milliseconds: 400));

class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  /// Current path of the shell (e.g. `/cargo`, `/cargo/123`).
  final String location;
  const MainShell({super.key, required this.navigationShell, this.location = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    // Keeps this user's online presence active on every authenticated
    // screen (see core/presence/online_users.dart).
    // listen (not watch): keeps presence alive without rebuilding the whole
    // shell every time ANY user anywhere comes online or goes offline.
    ref.listen(onlineUsersProvider, (_, __) {});
    final unread = (ref.watch(unreadCountProvider).valueOrNull ?? 0) + ref.watch(groupUnreadTotalProvider);
    // New message received → short sound; if the app is in the background
    // and notifications are allowed, also a browser notification.
    final uid = ref.watch(currentUserIdProvider);
    // New loads from others → sound / notification (Settings).
    ref.watch(newCargoWatcherProvider);
    void alert() {
      final ns = ref.read(notifySettingsProvider);
      if (ns.msgSound) playMessageSound();
      if (ns.msgNotify) showMessageNotification('FreightLink', strings.t('notif_new_message'));
    }
    ref.listen<AsyncValue<int>>(unreadCountProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      if (before != null && after != null && after > before) alert();
    });
    ref.listen<AsyncValue<List<GroupMessage>>>(myGroupMessagesProvider, (prev, next) {
      final before = prev?.valueOrNull;
      final after = next.valueOrNull;
      if (before == null || after == null) return;
      final known = {for (final m in before) m.id};
      if (after.any((m) => !known.contains(m.id) && m.senderId != uid)) alert();
    });
    // Branch indices: Loads 0, Search 1, Shipments 2, Messages 3,
    // Profile 4, Services 5, TIR Bazarı 6. Search and Shipments are NOT in
    // the bar on purpose (owner's decision): the load search already sits
    // on the Loads page under the map. Their routes stay so existing links
    // still work. Owner's layout: Yüklər · Servislər · TIR Bazarı (centre)
    // · Mesajlar · Profil; "Yük əlavə et" (+) sits on the Loads page under
    // the map.
    final items = <_NavItem>[
      _NavItem(0, Icons.local_shipping_outlined, Icons.local_shipping, strings.t('nav_home')),
      _NavItem(5, Icons.home_repair_service_outlined, Icons.home_repair_service, strings.t('nav_services')),
      _NavItem(6, Icons.storefront_outlined, Icons.storefront, strings.t('nav_market')),
      _NavItem(3, Icons.chat_bubble_outline, Icons.chat_bubble, strings.t('nav_messages'), badge: unread.toInt()),
      _NavItem(4, Icons.person_outline, Icons.person, strings.t('nav_profile')),
    ];
    return ResumeRefresher(
      child: Scaffold(
        body: Column(
          children: [
            const _RestrictedBanner(),
            Expanded(child: navigationShell),
          ],
        ),
        bottomNavigationBar: _BottomBar(
          items: items,
          current: navigationShell.currentIndex,
          onTap: (branch) {
            // One tap = one tab switch (iPhone sometimes delivers a tap twice).
            if (!_tabGuard.allow('tab:$branch', DateTime.now())) return;
            navigationShell.goBranch(
              branch,
              // Tapping the already-selected tab resets that tab's stack to
              // its root instead of doing nothing — standard bottom-nav UX.
              initialLocation: branch == navigationShell.currentIndex,
            );
          },
        ),
      ),
    );
  }
}

class _NavItem {
  final int branch;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  const _NavItem(this.branch, this.icon, this.selectedIcon, this.label, {this.badge = 0});
}

/// Equal slots that always fit: each label is one line and shrinks to
/// its slot (FittedBox) instead of wrapping or overflowing on a 320 px
/// iPhone. Respects the home-indicator safe area.
class _BottomBar extends StatelessWidget {
  final List<_NavItem> items;
  final int current;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.items, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.hero,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                for (final it in items) Expanded(child: _slot(it, it.branch == current)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(_NavItem it, bool selected) {
    final color = selected ? AppColors.accent : AppColors.textSoft;
    Widget icon = Icon(selected ? it.selectedIcon : it.icon, color: color, size: 22);
    if (it.badge > 0) {
      icon = Badge(label: Text(it.badge > 99 ? '99+' : '${it.badge}'), child: icon);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: it.label,
      child: InkWell(
        onTap: () => onTap(it.branch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 46,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 15,
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    it.label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// After the app comes back from the background (iOS suspends Safari /
/// PWA tabs and drops their websocket) or the tab becomes visible again,
/// re-subscribe the chat streams so new messages show without a manual
/// refresh.
class ResumeRefresher extends ConsumerStatefulWidget {
  final Widget child;
  const ResumeRefresher({super.key, required this.child});

  @override
  ConsumerState<ResumeRefresher> createState() => _ResumeRefresherState();
}

class _ResumeRefresherState extends ConsumerState<ResumeRefresher> {
  AppLifecycleListener? _listener;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _refresh() {
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(seconds: 2)) return; // show+resume fire together
    _last = now;
    ref.invalidate(myConversationsProvider);
    ref.invalidate(conversationMessagesProvider);
    ref.invalidate(conversationByIdProvider);
    ref.invalidate(receivedMessagesProvider); // drives both unread badges
  }

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onResume: _refresh, onShow: _refresh);
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shown on every tab while an admin has blocked or deactivated this
/// account (migration 0012). The database already refuses new loads,
/// offers and messages; this only explains why.
class _RestrictedBanner extends ConsumerWidget {
  const _RestrictedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const SizedBox.shrink();
    final p = ref.watch(publicProfileProvider(uid)).valueOrNull;
    if (p == null || !p.isRestricted) return const SizedBox.shrink();
    final strings = ref.watch(stringsProvider);
    final lines = <String>[
      p.isActive ? strings.t('account_blocked_banner') : strings.t('account_inactive_banner'),
      if (p.isActive && p.blockedUntil != null)
        strings.t('account_blocked_until', {
          'date': '${p.blockedUntil!.toLocal().day.toString().padLeft(2, '0')}.${p.blockedUntil!.toLocal().month.toString().padLeft(2, '0')}.${p.blockedUntil!.toLocal().year}',
        }),
      if (p.isActive && (p.blockReason ?? '').isNotEmpty) strings.t('account_blocked_reason', {'reason': p.blockReason!}),
    ];
    return Material(
      color: AppColors.urgentBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.block, color: AppColors.urgentFg, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(lines.join('\n'), style: TextStyle(color: AppColors.urgentFg, fontSize: 13, height: 1.35)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

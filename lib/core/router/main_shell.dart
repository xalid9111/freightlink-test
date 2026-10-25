import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../localization/app_strings.dart';
import '../localization/locale_controller.dart';
import '../presence/online_users.dart';
import '../../features/chat/presentation/providers/chat_providers.dart';
import '../../features/chat/presentation/providers/group_providers.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../repositories/profile_repository.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode.dart';
import '../layout/desktop_layout.dart';
import '../../features/auth/presentation/settings_screen.dart' show showLanguagePicker;
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
    final items = _navItems(strings, unread.toInt());
    void goTo(int branch) {
      // One tap = one tab switch (iPhone sometimes delivers a tap twice).
      if (!_tabGuard.allow('tab:$branch', DateTime.now())) return;
      navigationShell.goBranch(
        branch,
        // Tapping the already-selected tab resets that tab's stack to
        // its root instead of doing nothing — standard bottom-nav UX.
        initialLocation: branch == navigationShell.currentIndex,
      );
    }

    // Desktop (wide window): the same sections in a left sidebar instead of
    // the bottom bar. Phones / tablets keep the mobile layout below.
    if (isDesktopLayout(context)) {
      return ResumeRefresher(
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SideNav(items: items, current: navigationShell.currentIndex, onTap: goTo),
              Expanded(
                child: Column(
                  children: [
                    const _RestrictedBanner(),
                    Expanded(child: navigationShell),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
          onTap: goTo,
        ),
      ),
    );
  }
}

List<_NavItem> _navItems(AppStrings strings, int unread) => <_NavItem>[
      _NavItem(0, Icons.local_shipping_outlined, Icons.local_shipping, strings.t('nav_home')),
      _NavItem(5, Icons.home_repair_service_outlined, Icons.home_repair_service, strings.t('nav_services')),
      _NavItem(6, Icons.storefront_outlined, Icons.storefront, strings.t('nav_market')),
      _NavItem(3, Icons.chat_bubble_outline, Icons.chat_bubble, strings.t('nav_messages'), badge: unread),
      _NavItem(4, Icons.person_outline, Icons.person, strings.t('nav_profile')),
    ];

/// Start page of each section in the sidebar (shell branch → path).
const kDeskSectionPaths = <int, String>{0: '/cargo', 5: '/services', 6: '/market', 3: '/messages', 4: '/profile'};

/// Computer view of a page opened outside the tabs (a TIR Bazarı ad, a
/// load, a chat, a form…): the left sidebar stays on screen (owner) and
/// the page sits beside it at a comfortable width instead of stretching
/// over the whole window. [section] is the sidebar item shown as active.
/// Phones and tablets get the page unchanged.
class DeskFrame extends ConsumerWidget {
  final int section;
  final double maxWidth;
  final Widget child;
  const DeskFrame({super.key, required this.section, required this.child, this.maxWidth = 1100});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isDesktopLayout(context)) return child;
    final strings = ref.watch(stringsProvider);
    final unread = (ref.watch(unreadCountProvider).valueOrNull ?? 0) + ref.watch(groupUnreadTotalProvider);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SideNav(
            items: _navItems(strings, unread.toInt()),
            current: section,
            onTap: (branch) {
              if (!_tabGuard.allow('tab:$branch', DateTime.now())) return;
              context.go(kDeskSectionPaths[branch] ?? '/cargo');
            },
          ),
          Expanded(
            child: ColoredBox(
              color: AppColors.background,
              child: Center(
                child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
              ),
            ),
          ),
        ],
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
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
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

/// Desktop sidebar (owner's desktop design): logo, the five sections,
/// unread badge on Mesajlar, day / night switch and app language.
class _SideNav extends ConsumerWidget {
  final List<_NavItem> items;
  final int current;
  final ValueChanged<int> onTap;
  const _SideNav({required this.items, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final day = AppColors.isDay;
    final ground = day ? AppColors.background : Color.lerp(AppColors.background, AppColors.card, 0.4)!;
    BoxDecoration box() => BoxDecoration(
          color: day ? AppColors.card : AppColors.cardAlt.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        );
    return Container(
      width: 236,
      decoration: BoxDecoration(color: ground, border: Border(right: BorderSide(color: AppColors.line))),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 16, 34),
              child: Row(
                children: [
                  Icon(Icons.show_chart, color: AppColors.accentFill, size: 30),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: 'Freight', style: AppFonts.display(size: 26, color: AppColors.text)),
                        TextSpan(text: 'Link', style: AppFonts.display(size: 26, color: AppColors.accent)),
                      ])),
                    ),
                  ),
                ],
              ),
            ),
            for (final it in items) _item(it, it.branch == current),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Semantics(
                button: true,
                label: strings.t(day ? 'desk_light_mode' : 'desk_dark_mode'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => chooseTheme(day: !day),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                    decoration: box(),
                    child: Row(
                      children: [
                        Icon(day ? Icons.wb_sunny_outlined : Icons.dark_mode, color: day ? AppColors.accent : const Color(0xFFFFC94D), size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(strings.t(day ? 'desk_light_mode' : 'desk_dark_mode'),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text)),
                        ),
                        // Shows the mode in use; switching it off picks the other one.
                        Switch(
                          key: const ValueKey('desk-theme'),
                          value: true,
                          activeThumbColor: Colors.white,
                          activeTrackColor: AppColors.accentFill,
                          onChanged: (_) => chooseTheme(day: !day),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
              child: InkWell(
                key: const ValueKey('desk-language'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => showLanguagePicker(context, ref, strings),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: box(),
                  child: Row(
                    children: [
                      Text(languageFlag(lang), style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(lang.toUpperCase(),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: AppColors.text)),
                      ),
                      Icon(Icons.expand_more, color: AppColors.textSoft),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(_NavItem it, bool selected) {
    final color = selected ? AppColors.accent : AppColors.text;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Semantics(
        button: true,
        selected: selected,
        label: it.label,
        child: InkWell(
          key: ValueKey('desk-nav-${it.branch}'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(it.branch),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent.withValues(alpha: AppColors.isDay ? 0.12 : 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(selected ? it.selectedIcon : it.icon, color: color, size: 26),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(it.label,
                      style: TextStyle(fontSize: 16.5, fontWeight: selected ? FontWeight.w500 : FontWeight.w400, color: color)),
                ),
                if (it.badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(11)),
                    child: Text(it.badge > 99 ? '99+' : '${it.badge}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
              ],
            ),
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

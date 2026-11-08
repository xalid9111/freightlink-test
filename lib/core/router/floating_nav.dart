import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Floating capsule bottom bar (owner's picture, 08.11.2026): the phone's
/// bottom bar is no longer a full-width strip glued to the screen edge but
/// a rounded, dark see-through glass capsule floating about 0.5 cm above
/// the bottom edge, with a gap on the left and right. Pages scroll behind
/// it; nothing is ever hidden under it:
///
/// * a page of a tab is wrapped in [NavRoom] (in app_router.dart): it ends
///   above the capsule ([NavRoom] — every page, exactly as before), or —
///   for the five main pages whose lists add the room themselves —
///   runs behind it with the capsule's room as its bottom safe area
///   ([NavRoom.behind]);
/// * a sheet, dialog, menu or full-screen editor opened inside a tab
///   ([ShellOverlayObserver]) hides the capsule while it is open, so the
///   capsule never covers it (the sheet keeps the phone's own safe area);
/// * with the keyboard open the capsule is not there (as before, when the
///   keyboard covered the bar), so a text field never floats above it.
class FloatingNav {
  FloatingNav._();

  /// The capsule's own height.
  static const double height = 64;

  /// About 0.5 cm above the bottom edge of the screen.
  static const double edgeGap = 19;

  /// Left / right gap.
  static const double sideGap = 12;

  /// Room left between the capsule and the content above it.
  static const double contentGap = 10;

  /// Distance from the screen's bottom edge to the capsule: 0.5 cm, or just
  /// over the iPhone's home indicator when that is taller.
  static double bottomGap(double safeBottom) => math.max(edgeGap, safeBottom - 12);

  /// Height the capsule takes at the bottom of the screen (with its gap).
  static double space(double safeBottom) => height + bottomGap(safeBottom);
}

/// Tells the pages of the tabs how much room the floating capsule takes at
/// the bottom (0 = no capsule: computer, keyboard open).
class FloatingNavScope extends InheritedWidget {
  final double space;
  const FloatingNavScope({super.key, required this.space, required super.child});

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<FloatingNavScope>()?.space ?? 0;

  @override
  bool updateShouldNotify(FloatingNavScope old) => old.space != space;
}

/// A page of a tab under the floating capsule.
class NavRoom extends StatelessWidget {
  final Widget child;

  /// true: the page runs behind the capsule and gets the capsule's room as
  /// its bottom safe area (MediaQuery padding) — its lists add that room
  /// after their last item. false: the page simply ends above the capsule.
  final bool behind;
  const NavRoom({super.key, required this.child}) : behind = false;
  const NavRoom.behind({super.key, required this.child}) : behind = true;

  @override
  Widget build(BuildContext context) {
    final space = FloatingNavScope.of(context);
    if (space <= 0) return child;
    final mq = MediaQuery.of(context);
    if (behind) {
      return MediaQuery(
        data: mq.copyWith(padding: mq.padding.copyWith(bottom: space + FloatingNav.contentGap)),
        child: child,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: space + FloatingNav.contentGap),
      child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
    );
  }
}

/// Counts what is open on top of a tab's pages that the router did not put
/// there — sheets, dialogs, menus (popup routes) and full-screen editors
/// pushed with Navigator.push — so the capsule steps aside while they are
/// open. One observer per tab navigator.
class ShellOverlayObserver extends NavigatorObserver {
  /// Open overlays over all tabs.
  static final ValueNotifier<int> open = ValueNotifier<int>(0);

  static bool counts(Route<dynamic>? r) => r != null && (r is PopupRoute || r.settings is! Page);

  void _add(int d) => open.value = math.max(0, open.value + d);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (counts(route)) _add(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (counts(route)) _add(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (counts(route)) _add(-1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (counts(oldRoute)) _add(-1);
    if (counts(newRoute)) _add(1);
  }
}

class FloatingNavItem {
  final int branch;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  const FloatingNavItem(this.branch, this.icon, this.selectedIcon, this.label, {this.badge = 0});
}

/// The capsule itself: five equal slots in one row; each label is one line
/// and shrinks to its slot (FittedBox) instead of wrapping or overlapping
/// on a 320 pt iPhone. The selected tab: a slightly bigger icon, accent
/// colour (the same colour logic as the old bar).
class FloatingNavBar extends StatelessWidget {
  final List<FloatingNavItem> items;
  final int current;
  final ValueChanged<int> onTap;

  /// Stepped aside (a sheet / dialog is open): slides down and fades out,
  /// keeping its room so the page under the sheet does not move.
  final bool hidden;
  const FloatingNavBar({super.key, required this.items, required this.current, required this.onTap, this.hidden = false});

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final day = AppColors.isDay;
    final glass = day ? AppColors.card.withValues(alpha: 0.82) : AppColors.hero.withValues(alpha: 0.72);
    return SizedBox(
      height: FloatingNav.space(safeBottom),
      child: IgnorePointer(
        ignoring: hidden,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          offset: hidden ? const Offset(0, 1.2) : Offset.zero,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: hidden ? 0 : 1,
            child: Padding(
              padding: EdgeInsets.fromLTRB(FloatingNav.sideGap, 0, FloatingNav.sideGap, FloatingNav.bottomGap(safeBottom)),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: DecoratedBox(
                    key: const ValueKey('floating-nav'),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(FloatingNav.height / 2),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: day ? 0.14 : 0.38), blurRadius: 22, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(FloatingNav.height / 2),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Container(
                            height: FloatingNav.height,
                            decoration: BoxDecoration(
                              color: glass,
                              borderRadius: BorderRadius.circular(FloatingNav.height / 2),
                              border: Border.all(color: AppColors.line.withValues(alpha: day ? 1 : 0.9)),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              children: [
                                for (final it in items) Expanded(child: _slot(it, it.branch == current)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(FloatingNavItem it, bool selected) {
    final color = selected ? AppColors.accent : AppColors.textSoft;
    Widget icon = Icon(selected ? it.selectedIcon : it.icon, color: color, size: selected ? 28 : 24);
    if (it.badge > 0) {
      icon = Badge(label: Text(it.badge > 99 ? '99+' : '${it.badge}'), child: icon);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: it.label,
      child: InkWell(
        key: ValueKey('nav-${it.branch}'),
        borderRadius: BorderRadius.circular(FloatingNav.height / 2),
        onTap: () => onTap(it.branch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 30, child: Center(child: icon)),
              const SizedBox(height: 2),
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
                      fontSize: 11.5,
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

import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/tirlink_wordmark.dart';
import '../../cargo/presentation/widgets/cargo_picture.dart' show HeaderCircle;
import '../../favorites/favorites.dart' show openFavorites, FavTab;
import '../../notices/notices.dart' show NoticeBell;

/// The top of the "Xəritə" tab — Parklar, Servislər and Mağazalar alike
/// (owner's picture, 20.11.2026; replaces the map banners, "tam çıxsın"):
/// the TırLink mark on the left, "Xəritə" in the middle, the bell and the
/// heart on the right (fixed on every page, owner 17.11.2026).
class MapPageHeader extends StatelessWidget {
  final AppStrings s;

  /// The title's text key ("Xəritə" by default, "Maşınlarım" on /fleet).
  final String titleKey;
  const MapPageHeader({super.key, required this.s, this.titleKey = 'nav_map'});

  static const double height = 58;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('map-page-header'),
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 12, 6),
        child: Stack(alignment: Alignment.center, children: [
          Text(
            s.t(titleKey),
            key: const ValueKey('map-page-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
          Row(children: [
            const TirLinkWordmark(size: 17, showSite: false, showLogo: true),
            const Spacer(),
            NoticeBell(
              strings: s,
              size: 21,
              frame: (icon, onTap, tip) => HeaderCircle(key: const ValueKey('notice-bell'), tooltip: tip, onTap: onTap, child: icon),
            ),
            const SizedBox(width: 10),
            HeaderCircle(
              key: const ValueKey('map-favorites'),
              tooltip: s.t('fav_title'),
              onTap: () => openFavorites(context, FavTab.profiles),
              child: Icon(Icons.favorite_border, size: 21, color: AppColors.accent),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// "Xəritə | Maşınlarım" (owner's picture, 20.11.2026): under the header on
/// the map pages and on Maşınlarım; the chosen half filled orange.
class MapFleetSwitch extends StatelessWidget {
  final AppStrings s;
  final bool fleet;
  final VoidCallback onMap, onFleet;
  const MapFleetSwitch({super.key, required this.s, required this.fleet, required this.onMap, required this.onFleet});

  @override
  Widget build(BuildContext context) {
    Widget half(String key, IconData icon, String label, bool on, VoidCallback tap) => Expanded(
          child: Material(
            color: on ? AppColors.accentFill : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(16),
              onTap: on ? null : tap,
              child: SizedBox(
                height: 42,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 20, color: on ? Colors.white : AppColors.text),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w500 : FontWeight.w400, color: on ? Colors.white : AppColors.text)),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        key: const ValueKey('map-fleet-switch'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          half('switch-map', Icons.place, s.t('nav_map'), !fleet, onMap),
          const SizedBox(width: 4),
          half('switch-fleet', Icons.local_shipping_outlined, s.t('fl_title'), fleet, onFleet),
        ]),
      ),
    );
  }
}

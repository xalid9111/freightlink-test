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
  const MapPageHeader({super.key, required this.s});

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
            s.t('nav_map'),
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

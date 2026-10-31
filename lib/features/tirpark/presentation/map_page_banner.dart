import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/page_hero.dart';

/// The phone banner of TIRPark and Servislər (owner, 31.10.2026: both pages
/// have the same form — picture, map and buttons stay in place, only the
/// names change). The admin's picture (a GIF too) with its place / zoom and
/// texts comes from the page hero ('tirpark' / 'services'); the pencil opens
/// the same banner editor.
class MapPageBanner extends ConsumerWidget {
  final AppStrings s;
  final String page;
  final IconData brandIcon, editIcon;
  final String brandAccent, brandRest;
  final String defaultTitle, defaultAccent, defaultSubtitle;

  /// Picture shown before the admin sets one (null = a faded icon).
  final String? asset;
  const MapPageBanner({
    super.key,
    required this.s,
    required this.page,
    required this.brandIcon,
    required this.editIcon,
    required this.brandAccent,
    required this.brandRest,
    required this.defaultTitle,
    required this.defaultAccent,
    required this.defaultSubtitle,
    this.asset,
  });

  static const double height = 168;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = AppColors.background;
    final hero = ref.watch(pageHeroProvider(page)).valueOrNull;
    final img = hero?.imageFor(day: AppColors.isDay);
    final texts = img == null || (hero?.showText ?? true);
    final admin = isAdminUser(ref);
    return SizedBox(
      key: ValueKey('map-banner-$page'),
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        if (img != null)
          PageHeroImage(
            url: img,
            align: hero!.alignmentFor(day: AppColors.isDay),
            zoom: hero.zoomFor(day: AppColors.isDay),
            fallback: (_) => const SizedBox.shrink(),
          )
        else if (asset != null)
          Align(
            alignment: Alignment.centerRight,
            child: Image.asset(asset!, fit: BoxFit.cover, alignment: const Alignment(0, -0.45), height: height, width: 230),
          )
        else
          Align(
            alignment: const Alignment(0.85, 0),
            child: Icon(brandIcon, size: 110, color: AppColors.accent.withValues(alpha: 0.18)),
          ),
        if (texts)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [bg, bg, bg.withValues(alpha: 0.55), bg.withValues(alpha: 0.0)],
                stops: const [0, 0.42, 0.62, 0.85],
              ),
            ),
          ),
        if (texts)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 120, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Icon(brandIcon, color: AppColors.accent, size: 26),
                const SizedBox(width: 6),
                Text(brandAccent, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.accent)),
                Flexible(
                  child: Text(brandRest,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(hero?.title ?? defaultTitle, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.1)),
              ),
              Text(hero?.titleAccent ?? defaultAccent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.accent, height: 1.15)),
              const SizedBox(height: 4),
              Text(hero?.subtitle ?? defaultSubtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            ]),
          ),
        if (admin)
          Positioned(
            right: 10,
            top: 10,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: IconButton(
                key: ValueKey('page-hero-edit-$page'),
                tooltip: s.t('mk_hero_edit'),
                icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                onPressed: () => showPageHeroEditor(context, strings: s, page: page, hero: hero, icon: editIcon),
              ),
            ),
          ),
      ]),
    );
  }
}

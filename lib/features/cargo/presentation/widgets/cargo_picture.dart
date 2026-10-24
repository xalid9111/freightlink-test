import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/router/safe_navigation.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../repositories/profile_repository.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/cargo_categories.dart';
import '../../data/cargo_media_repository.dart';
import '../../domain/cargo_pictures.dart';
import '../providers/cargo_media_providers.dart';

/// A load's card picture (0058). A load without its own picture shows an
/// admin template of its type (owner, 24.10.2026), picked by [seed] (the
/// load id) so loads of one type differ. No template (or a picture that
/// does not load) → the load type icon on a plain tile.
class CargoPicture extends ConsumerWidget {
  final String? imageUrl;
  final String? truckType;
  final bool groupage;
  final BoxFit fit;
  /// The load id; null = never use a template (e.g. the form preview).
  final String? seed;
  const CargoPicture(
      {super.key, this.imageUrl, this.truckType, this.groupage = false, this.fit = BoxFit.cover, this.seed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = cargoPictureCategory(truckType: truckType, groupage: groupage);
    final placeholder = Container(
      color: AppColors.tileBg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(18),
      child: cat == null
          ? Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.textSoft)
          : FractionallySizedBox(
              widthFactor: 0.6,
              // An icon that cannot load (e.g. during a site update) shows
              // the plain box icon instead of an error per card.
              child: Image.asset(categoryIconAsset(cat, night: !AppColors.isDay),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.textSoft)),
            ),
    );
    var url = imageUrl;
    if ((url == null || url.isEmpty) && cat != null && seed != null) {
      final templates = ref.watch(cargoTemplatesProvider(cat)).valueOrNull ?? const <CargoTemplate>[];
      url = templateFor([for (final t in templates) t.imageUrl], seed!);
    }
    if (url == null || url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: 800, // decoded small: fast lists on phones
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (c, child, p) => p == null ? child : placeholder,
    );
  }
}

/// Heart of one load: adds it to / takes it off "Seçilmiş yüklər".
/// [onPhoto] = drawn on a picture (dark round backing, like TIR Bazarı).
class CargoFavoriteHeart extends ConsumerWidget {
  final String cargoId;
  final double size;
  final bool onPhoto;
  const CargoFavoriteHeart({super.key, required this.cargoId, this.size = 20, this.onPhoto = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(cargoFavoriteIdsProvider).contains(cargoId);
    final s = ref.watch(stringsProvider);
    void tap() {
      ref.read(cargoFavoriteIdsProvider.notifier).toggle(cargoId).catchError((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('fav_cargo_failed'))));
        }
      });
    }

    final icon = Icon(on ? Icons.favorite : Icons.favorite_border,
        size: size, color: on ? AppColors.accent : (onPhoto ? Colors.white : AppColors.textSoft));
    return Semantics(
      button: true,
      selected: on,
      label: s.t('fav_cargo_title'),
      child: onPhoto
          ? Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                key: ValueKey('cargo-heart-$cargoId'),
                customBorder: const CircleBorder(),
                onTap: tap,
                child: Padding(padding: const EdgeInsets.all(7), child: icon),
              ),
            )
          : InkWell(
              key: ValueKey('cargo-heart-$cargoId'),
              customBorder: const CircleBorder(),
              onTap: tap,
              child: Padding(padding: const EdgeInsets.all(6), child: icon),
            ),
    );
  }
}

/// Phone Loads page, top right (owner, 22.10.2026): two round buttons —
/// the heart opens "Seçilmiş yüklər", the profile picture opens Profil.
class HeaderCircles extends ConsumerWidget {
  final AppStrings strings;
  const HeaderCircles({super.key, required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    final me = ref.watch(currentUserProvider);
    final profile = uid == null ? null : ref.watch(publicProfileProvider(uid)).valueOrNull;
    final name = (profile?.fullName ?? me?.fullName ?? '').trim();
    final initials = name.isEmpty
        ? '?'
        : name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p.characters.first.toUpperCase()).join();
    final favCount = ref.watch(cargoFavoriteIdsProvider).length;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      HeaderCircle(
        key: const ValueKey('hdr-favorites'),
        tooltip: strings.t('fav_cargo_title'),
        onTap: () => context.pushOnce('/cargo/favorites'),
        child: Badge(
          isLabelVisible: favCount > 0,
          label: Text(favCount > 99 ? '99+' : '$favCount'),
          backgroundColor: AppColors.accentFill,
          child: Icon(favCount > 0 ? Icons.favorite : Icons.favorite_border, size: 21, color: AppColors.accent),
        ),
      ),
      const SizedBox(width: 10),
      HeaderCircle(
        key: const ValueKey('hdr-profile'),
        tooltip: strings.t('nav_profile'),
        onTap: () => context.go('/profile'),
        padding: 2,
        child: UserAvatar(imageUrl: profile?.avatarUrl, initials: initials, radius: 18),
      ),
    ]);
  }
}

/// One round glass button of the header (also used on the computer).
class HeaderCircle extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final double padding;
  const HeaderCircle(
      {super.key, required this.child, required this.onTap, required this.tooltip, this.size = 42, this.padding = 0});

  @override
  Widget build(BuildContext context) {
    final glass = AppColors.isDay ? AppColors.tileBg.withValues(alpha: 0.92) : AppColors.card.withValues(alpha: 0.82);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: glass,
        shape: CircleBorder(side: BorderSide(color: AppColors.tileLine)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Padding(padding: EdgeInsets.all(padding), child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

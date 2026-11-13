import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../favorites/favorites.dart';
import '../../cargo/domain/truck_types.dart';
import '../../cargo/presentation/widgets/cargo_picture.dart';
import '../data/empty_truck_repository.dart';
import '../domain/empty_truck.dart';

/// "İndi" or "14 noy, 09:00" — when the truck is free.
String emptyTruckFreeLabel(AppStrings s, EmptyTruck t, String lang, {DateTime? now}) {
  final at = t.availableFrom;
  if (at == null || !at.isAfter(now ?? DateTime.now())) return s.t('et_free_now');
  return s.t('et_free_from', {'date': DateFormat('d MMM, HH:mm', lang).format(at)});
}

/// "20 t boş"
String emptyTruckTonsLabel(AppStrings s, double tons) {
  final v = tons == tons.roundToDouble() ? tons.toStringAsFixed(0) : tons.toStringAsFixed(1);
  return s.t('et_free_tons', {'t': v});
}

/// Yüklər | Daşıyıcılar (owner's picture, 13.11.2026): two equal buttons
/// under the route search; the chosen one filled.
class LoadsSectionSwitch extends ConsumerWidget {
  final AppStrings strings;
  final VoidCallback? onChanged;
  const LoadsSectionSwitch({super.key, required this.strings, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(loadsSectionProvider);
    Widget button(LoadsSection v, String label) {
      final on = now == v;
      return Expanded(
        child: Material(
          color: on ? AppColors.accent.withValues(alpha: 0.32) : AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            // Only the chosen one has the frame (owner, 13.11.2026: two
            // frames looked alike and confused).
            side: on ? BorderSide(color: AppColors.accent, width: 1.5) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('loads-section-${v.name}'),
            onTap: () {
              if (on) return;
              ref.read(loadsSectionProvider.notifier).state = v;
              onChanged?.call();
            },
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(label,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.text)),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      button(LoadsSection.loads, strings.t('et_section_loads')),
      const SizedBox(width: 12),
      button(LoadsSection.carriers, strings.t('et_section_carriers')),
    ]);
  }
}

/// One empty truck on the Daşıyıcılar list: the truck picture of its type,
/// where it is now ("📍 Bakı, Azərbaycan"), the route ("Bakı → İstanbul"),
/// free tonnes, the truck, when it is free.
class EmptyTruckTile extends ConsumerWidget {
  final EmptyTruck truck;
  final AppStrings strings;
  final VoidCallback onTap;
  const EmptyTruckTile({super.key, required this.truck, required this.strings, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final t = truck;
    final text = TextStyle(fontSize: 14, color: AppColors.text, height: 1.25);
    Widget line(IconData icon, String value, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            Icon(icon, size: 15, color: AppColors.textSoft),
            const SizedBox(width: 5),
            Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: text)),
          ]),
        );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('empty-truck-tile-${t.id}'),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.tileLine, width: 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                CargoPicture(truckType: t.truckType, seed: t.id),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(8)),
                    child: Text(strings.t('et_badge_empty'),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white)),
                  ),
                ),
                // Bəyən (owner, 13.11.2026): the carrier goes to
                // Bəyəndiklərim → Profillər; not on one's own ads.
                if (ref.watch(currentUserIdProvider) != t.ownerId)
                  Positioned(top: 6, right: 6, child: LikeHeart(kind: FavKind.user, id: t.ownerId, size: 19, onPhoto: true)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  t.routeLabel(lang, anyLabel: strings.t('et_any_direction_short')),
                  key: const ValueKey('empty-truck-route'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: AppColors.text, height: 1.2),
                ),
                line(Icons.place_outlined, t.placeLabel(lang), key: const ValueKey('empty-truck-place')),
                line(Icons.scale_outlined, emptyTruckTonsLabel(strings, t.freeTons)),
                line(Icons.local_shipping_outlined, truckTypeLabel(strings, t.truckType)),
                line(Icons.schedule, emptyTruckFreeLabel(strings, t, lang)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Aktiv / Dayandırılıb / Maşın doldu — for the owner's own ads.
class EmptyTruckStatusChip extends StatelessWidget {
  final String status;
  final AppStrings strings;
  const EmptyTruckStatusChip({super.key, required this.status, required this.strings});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => (strings.t('et_status_active'), AppColors.online),
      'paused' => (strings.t('et_status_paused'), AppColors.textSoft),
      _ => (strings.t('et_status_filled'), AppColors.accent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
    );
  }
}

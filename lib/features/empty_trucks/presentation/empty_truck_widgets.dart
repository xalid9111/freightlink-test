import '../../../core/widgets/neu_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/router/guest_access.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../repositories/profile_repository.dart';
import '../../cargo/domain/cargo_categories.dart' show categoryIconAsset;
import '../../cargo/domain/cargo_pictures.dart' show cargoPictureCategory;
import '../../chat/data/group_repository.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/call_options.dart';

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
    // Neumorf (0137): one pressed-in track, the chosen half raised (owner's
    // approved picture); same keys and taps.
    if (AppColors.neumorph) {
      Widget half(LoadsSection v, String label) {
        final on = now == v;
        return Expanded(
          child: InkWell(
            key: ValueKey('loads-section-${v.name}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              if (on) return;
              ref.read(loadsSectionProvider.notifier).state = v;
              onChanged?.call();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 44,
              decoration: on ? neuRaisedDecoration(radius: 14, depth: 0.7) : const BoxDecoration(),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: on ? AppColors.text : AppColors.textSoft)),
            ),
          ),
        );
      }

      return Container(
        key: const ValueKey('loads-section-neu'),
        padding: const EdgeInsets.all(5),
        decoration: neuInsetDecoration(radius: 18),
        child: Row(children: [
          half(LoadsSection.loads, strings.t('et_section_loads')),
          const SizedBox(width: 6),
          half(LoadsSection.carriers, strings.t('et_section_carriers')),
        ]),
      );
    }
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

/// When the truck is ready, as on the owner's picture (17.11.2026): "Bu gün
/// hazırdır" (free now or later today), otherwise the day it is free from —
/// "25 noyabrdan" (Azerbaijani suffix by the month), "from 25 November" …
String emptyTruckReadyLabel(AppStrings s, EmptyTruck t, String lang, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final at = t.availableFrom?.toLocal();
  final endOfToday = DateTime(n.year, n.month, n.day).add(const Duration(days: 1));
  if (at == null || at.isBefore(endOfToday)) return s.t('et_ready_today');
  final date = DateFormat('d MMMM', lang).format(at);
  if (lang == 'az') return '$date${at.month == 4 ? 'dən' : 'dan'}';
  return s.t('et_free_from', {'date': date});
}

/// "Caspian Trans" → "CT"; empty → "?".
String carrierInitials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = String.fromCharCode(parts.first.runes.first);
  final second = parts.length > 1 ? String.fromCharCode(parts[1].runes.first) : '';
  return (first + second).toUpperCase();
}

/// "20 T" (capital T, owner 17.11.2026).
String carrierTonsLabel(double tons) {
  final v = tons == tons.roundToDouble() ? tons.toStringAsFixed(0) : tons.toStringAsFixed(1);
  return '$v T';
}

/// Daşıyıcılar card (owner's picture 1, 17.11.2026): the carrier's own
/// picture (profile photo / company logo, else the initials) in an accent
/// ring, name + blue badge (a rating only when one exists — none is made
/// up), the route with flags and a ›, the truck kind's own icon + "Tent •
/// 20 T" | 📅 "Bu gün hazırdır" / "25 noyabrdan", then "Zəng et" and "Mesaj".
/// A tap on the information opens the ad; the buttons work on their own.
class EmptyTruckCarrierCard extends ConsumerStatefulWidget {
  final EmptyTruck truck;
  final AppStrings strings;
  final VoidCallback onTap;

  /// The carrier's rating — shown only when a real one exists (null = none).
  final double? rating;
  const EmptyTruckCarrierCard({super.key, required this.truck, required this.strings, required this.onTap, this.rating});

  @override
  ConsumerState<EmptyTruckCarrierCard> createState() => _EmptyTruckCarrierCardState();
}

class _EmptyTruckCarrierCardState extends ConsumerState<EmptyTruckCarrierCard> {
  bool _busy = false;

  Future<void> _message() async {
    if (askSignIn(context)) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(widget.truck.ownerId);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.t('chat_open_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final t = widget.truck;
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final me = ref.watch(currentUserIdProvider);
    final own = me != null && me == t.ownerId;
    final profile = ref.watch(publicProfileProvider(t.ownerId)).valueOrNull;
    final name = (profile?.fullName ?? '').trim();
    final night = Theme.of(context).brightness == Brightness.dark;
    final kind = cargoPictureCategory(truckType: t.truckType);
    final phone = (t.phone ?? '').trim().isNotEmpty ? t.phone!.trim() : (t.whatsapp ?? '').trim();
    final meta = TextStyle(fontSize: 14, color: AppColors.text, height: 1.2);
    final divider = Container(height: 1, color: AppColors.line);

    Widget kindIcon() => kind == null
        ? Icon(Icons.local_shipping_outlined, size: 20, color: AppColors.textSoft)
        : Image.asset(categoryIconAsset(kind, night: night),
            key: ValueKey('carrier-kind-$kind'),
            width: 28,
            height: 18,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(Icons.local_shipping_outlined, size: 20, color: AppColors.textSoft));

    final info = InkWell(
      key: ValueKey('empty-truck-tile-${t.id}'),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.accent, width: 2)),
              child: UserAvatar(
                key: const ValueKey('carrier-avatar'),
                imageUrl: profile?.avatarUrl,
                initials: carrierInitials(name),
                radius: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(
                    flex: 3,
                    child: Text(name.isEmpty ? '—' : name,
                        key: const ValueKey('carrier-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                  if (profile?.isVerified == true) ...[const SizedBox(width: 6), const VerifiedPhotoBadge(size: 18)],
                  // "Boşdur" right after the name / badge (owner's mark,
                  // 17.11.2026): the truck is empty at a glance.
                  const SizedBox(width: 8),
                  // Shrinks (never overflows) on a narrow phone with a long language.
                  Flexible(
                    flex: 2,
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _FreeBadge(label: s.t('et_badge_free'))),
                  ),
                ]),
                if (widget.rating != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(key: const ValueKey('carrier-rating'), children: [
                      Icon(Icons.star_rounded, size: 17, color: AppColors.accent),
                      const SizedBox(width: 3),
                      Text(widget.rating!.toStringAsFixed(1), style: meta),
                    ]),
                  ),
              ]),
            ),
            if (!own) LikeHeart(kind: FavKind.user, id: t.ownerId, size: 20),
          ]),
          const SizedBox(height: 10),
          divider,
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t.routeLabel(lang, anyLabel: s.t('et_any_direction_short')),
                  key: const ValueKey('empty-truck-route'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.2),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  kindIcon(),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${truckTypeLabel(s, t.truckType)} • ${carrierTonsLabel(t.freeTons)}',
                        key: const ValueKey('carrier-kind-tons'), maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                  ),
                  Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.line),
                  Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textSoft),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(emptyTruckReadyLabel(s, t, lang),
                        key: const ValueKey('carrier-ready'), maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                  ),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.textSoft),
          ]),
        ]),
      ),
    );

    // The buttons: "Zəng et" (accent) + "Mesaj"; a visitor signs in first;
    // a hidden / missing number leaves only "Mesaj"; one's own ad: Redaktə et.
    Widget buttons() {
      const h = 44.0;
      final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
      if (own) {
        return OutlinedButton.icon(
          key: const ValueKey('carrier-edit'),
          onPressed: () => context.pushOnce('/trucks/${t.id}/edit'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(h), shape: shape),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(s.t('et_edit')),
        );
      }
      final guest = isSignedOut();
      final canCall = guest || phone.isNotEmpty;
      final message = OutlinedButton.icon(
        key: const ValueKey('carrier-message'),
        onPressed: _busy ? null : _message,
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(h), shape: shape, backgroundColor: AppColors.cardAlt, foregroundColor: AppColors.text),
        icon: const Icon(Icons.chat_bubble_outline, size: 19),
        label: Text(s.t('et_card_message'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
      );
      if (!canCall) return message;
      return Row(children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('carrier-call'),
            onPressed: () {
              if (askSignIn(context)) return;
              showCallOptions(context, s, phone);
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(h), shape: shape, backgroundColor: AppColors.accentFill),
            icon: const Icon(Icons.phone, size: 19),
            label: Text(s.t('et_call'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: message),
      ]);
    }

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.tileLine, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          info,
          Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 12), child: buttons()),
        ]),
      ),
    );
  }
}

/// The green "● Boşdur" pill on a carrier card.
class _FreeBadge extends StatelessWidget {
  final String label;
  const _FreeBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('carrier-free-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.online.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.online.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.online, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.online)),
        ]),
      );
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

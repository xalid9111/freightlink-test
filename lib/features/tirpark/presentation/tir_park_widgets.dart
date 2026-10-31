import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/tir_park.dart';

/// Icon of an amenity (labels: `tp_am_<code>` in the six languages).
IconData tirParkAmenityIcon(String code) => switch (code) {
      'secure' => Icons.verified_user_outlined,
      '24_7' => Icons.schedule,
      'food' => Icons.restaurant,
      'shower' => Icons.shower_outlined,
      'wc' => Icons.wc,
      'fuel' => Icons.local_gas_station_outlined,
      'wifi' => Icons.wifi,
      'repair' => Icons.build_outlined,
      'lighting' => Icons.lightbulb_outline,
      'camera' => Icons.videocam_outlined,
      'free' => Icons.money_off,
      _ => Icons.payments_outlined,
    };

Color tirParkAmenityColor(String code) => switch (code) {
      'secure' => AppColors.online,
      '24_7' => AppColors.blue,
      'food' || 'fuel' => AppColors.accent,
      _ => AppColors.textSoft,
    };

/// One amenity as a small pill (card / park page).
class TirParkAmenityPill extends StatelessWidget {
  final String code;
  final AppStrings s;
  const TirParkAmenityPill({super.key, required this.code, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = tirParkAmenityColor(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(tirParkAmenityIcon(code), size: 15, color: c),
        const SizedBox(width: 5),
        Text(s.t('tp_am_$code'), style: TextStyle(fontSize: 12.5, color: AppColors.text)),
      ]),
    );
  }
}

/// The map pin: orange with a truck for an approved park; grey with an
/// hourglass while it waits for approval (only its author sees it).
class TirParkPin extends StatelessWidget {
  final bool approved, selected;
  const TirParkPin({super.key, required this.approved, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final c = approved ? AppColors.accentFill : AppColors.textSoft;
    final size = selected ? 44.0 : 36.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Icon(approved ? Icons.local_shipping : Icons.hourglass_top, color: Colors.white, size: size * 0.5),
      ),
      CustomPaint(size: const Size(12, 7), painter: _PinTail(c)),
    ]);
  }
}

class _PinTail extends CustomPainter {
  final Color color;
  _PinTail(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PinTail old) => old.color != color;
}

/// A park in the "Yaxınlıqdakı TIR parkları" list (owner's picture): photo,
/// name, rating, place · distance, amenities.
class TirParkCard extends StatelessWidget {
  final TirPark park;
  final double? km;
  final AppStrings s;
  final bool selected;
  final VoidCallback onTap;
  /// "Şərhlər (n) ›" and "Şərh yaz" (owner's picture; null = not shown).
  final VoidCallback? onReviews, onWrite;
  const TirParkCard(
      {super.key, required this.park, required this.km, required this.s, required this.onTap, this.selected = false, this.onReviews, this.onWrite});

  @override
  Widget build(BuildContext context) {
    final photo = park.photoUrls.firstOrNull;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.line, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('tp-card-${park.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 88,
                height: 88,
                child: photo == null
                    ? Container(
                        color: AppColors.cardAlt,
                        child: Icon(Icons.local_parking, color: AppColors.textSoft, size: 36),
                      )
                    : Image.network(photo, fit: BoxFit.cover, cacheWidth: 270,
                        errorBuilder: (_, __, ___) => Container(color: AppColors.cardAlt)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(park.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                  // A real rating only (no stars before anybody rated).
                  if (park.ratingCount > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.star_rounded, size: 18, color: AppColors.promoPremium),
                    const SizedBox(width: 2),
                    Text(park.ratingAvg.toStringAsFixed(1), style: TextStyle(fontSize: 14, color: AppColors.text)),
                  ],
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.place_outlined, size: 16, color: AppColors.textSoft),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      [if ((park.city ?? '').isNotEmpty) park.city!, if (km != null) distanceLabel(km!)].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
                    ),
                  ),
                ]),
                if (park.isPending) ...[
                  const SizedBox(height: 6),
                  Text(s.t('tp_pending'), key: ValueKey('tp-pending-${park.id}'),
                      style: TextStyle(fontSize: 12.5, color: AppColors.promoVip)),
                ],
                if (park.amenities.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in park.amenities.take(3)) TirParkAmenityPill(code: a, s: s),
                    if (park.amenities.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('+${park.amenities.length - 3}', style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                      ),
                  ]),
                ],
                if (onReviews != null) ...[
                  const SizedBox(height: 8),
                  Divider(height: 1, color: AppColors.line),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        key: ValueKey('tp-reviews-${park.id}'),
                        onTap: onReviews,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.textSoft),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(s.t('tp_reviews_short', {'n': '${park.ratingCount}'}),
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: AppColors.text)),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: AppColors.textSoft),
                          ]),
                        ),
                      ),
                    ),
                    if (onWrite != null && park.isApproved)
                      OutlinedButton.icon(
                        key: ValueKey('tp-write-${park.id}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: BorderSide(color: AppColors.accent),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onWrite,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(s.t('tp_write'), style: const TextStyle(fontSize: 13)),
                      ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Parklar | Servislər" (owner, 31.10.2026): the same switch on the
/// TIRPark map and on the Servislər map, so either one is one tap away.
class ParksServicesSwitch extends StatelessWidget {
  final bool parks;
  final AppStrings s;
  final VoidCallback onParks, onServices;
  const ParksServicesSwitch({super.key, required this.parks, required this.s, required this.onParks, required this.onServices});

  @override
  Widget build(BuildContext context) {
    Widget seg(String key, IconData icon, String label, bool on, VoidCallback tap) => InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(20),
          onTap: on ? null : tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: on ? AppColors.accentFill : Colors.transparent, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: on ? Colors.white : AppColors.text),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 13.5, fontWeight: on ? FontWeight.w500 : FontWeight.w400, color: on ? Colors.white : AppColors.text)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('tp-tab-parks', Icons.local_parking, s.t('tp_parks'), parks, onParks),
        seg('tp-tab-services', Icons.home_repair_service_outlined, s.t('nav_services'), !parks, onServices),
      ]),
    );
  }
}

/// "… əlavə et +" on a map: a label pill running under a round orange +.
class MapAddButton extends StatelessWidget {
  final String label, buttonKey;
  final VoidCallback onTap;
  const MapAddButton({super.key, required this.label, required this.buttonKey, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey(buttonKey),
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Stack(alignment: Alignment.centerRight, children: [
            Container(
              margin: const EdgeInsets.only(right: 30),
              padding: const EdgeInsets.fromLTRB(16, 10, 30, 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.line),
              ),
              child: Text(label, style: TextStyle(fontSize: 14.5, color: AppColors.text)),
            ),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accentFill,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.accentFill.withValues(alpha: 0.45), blurRadius: 12)],
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 30),
            ),
          ]),
        ),
      );
}

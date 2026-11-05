import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/geo_service.dart';
import '../../services/presentation/services_providers.dart' show fmtKm;
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
  /// Shown under the park while it is selected: the way there (owner,
  /// 01.11.2026 — like Servislər).
  final Widget? footer;
  /// The booking line (0081): free places now and "Yeri rezerv et"; shown
  /// whether or not the park is selected.
  final Widget? booking;
  /// Opens the park's page (owner, 02.11.2026): a tap on the picture or the
  /// name of the selected park.
  final VoidCallback? onOpen;
  /// "Önə çıxar" (0093): the "Reklam" mark with the crown / diamond.
  final Widget? badge;
  const TirParkCard(
      {super.key,
      required this.park,
      required this.km,
      required this.s,
      required this.onTap,
      this.selected = false,
      this.onReviews,
      this.onWrite,
      this.footer,
      this.booking,
      this.onOpen,
      this.badge});

  /// The picture and the name open the park's page (owner, 05.11.2026 —
  /// on any park, selected or not); the rest of the card selects it.
  Widget _opens(String key, Widget child) => GestureDetector(
        key: ValueKey('$key-${park.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen ?? onTap,
        child: child,
      );

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
            _opens('tp-photo', ClipRRect(
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
            )),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: _opens('tp-name', Text(park.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.text))),
                  ),
                  // A real rating only (no stars before anybody rated).
                  if (park.ratingCount > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.star_rounded, size: 18, color: AppColors.promoPremium),
                    const SizedBox(width: 2),
                    Text(park.ratingAvg.toStringAsFixed(1), style: TextStyle(fontSize: 14, color: AppColors.text)),
                  ],
                ]),
                if (badge != null) ...[const SizedBox(height: 4), badge!],
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
                if (booking != null) ...[
                  const SizedBox(height: 8),
                  booking!,
                ],
                if (selected && footer != null) ...[
                  const SizedBox(height: 8),
                  footer!,
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

/// "Parklar | Servislər | Mağazalar" (owner, 31.10.2026; Mağazalar 05.11.2026):
/// the same switch on the TIRPark map and on the Servislər map, so each one
/// is one tap away. Mağazalar = the services map with the shops (spare parts).
class ParksServicesSwitch extends StatelessWidget {
  final bool parks;
  final bool shops;
  final AppStrings s;
  final VoidCallback onParks, onServices;
  final VoidCallback? onShops;
  const ParksServicesSwitch(
      {super.key, required this.parks, required this.s, required this.onParks, required this.onServices, this.shops = false, this.onShops});

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
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          seg('tp-tab-parks', Icons.local_parking, s.t('tp_parks'), parks, onParks),
          seg('tp-tab-services', Icons.home_repair_service_outlined, s.t('nav_services'), !parks && !shops, onServices),
          if (onShops != null) seg('tp-tab-shops', Icons.storefront_outlined, s.t('tp_shops'), shops, onShops!),
        ]),
      ),
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


/// A map control placed [gap] px over the list sheet. The sheet's top is a
/// part ([sheet]) of the MAP AREA under the banner, not of the whole
/// screen, so the place is measured there (owner, 31.10.2026: the "əlavə
/// et" buttons sit right above the list on TIRPark and Servislər). Must be
/// a child of the map's Stack; taps outside [child] reach the map.
class AboveSheet extends StatelessWidget {
  final double sheet, gap;
  final double? left;
  final Widget child;
  const AboveSheet({super.key, required this.sheet, required this.gap, this.left, required this.child});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: LayoutBuilder(
          builder: (context, box) => Stack(children: [
            Positioned(right: 12, left: left, bottom: box.maxHeight * sheet + gap, child: child),
          ]),
        ),
      );
}

/// The title row of a sheet with a close (X) button (owner, 01.11.2026:
/// every opened sheet can be left without doing anything — X, a swipe
/// down on the handle, or a tap outside).
class SheetTitle extends StatelessWidget {
  final String title, closeKey;
  final AppStrings s;
  final TextStyle? style;
  const SheetTitle({super.key, required this.title, required this.s, required this.closeKey, this.style});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(title, style: style ?? TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
        ),
        IconButton(
          key: ValueKey(closeKey),
          tooltip: s.t('nav_sheet_cancel'),
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.close, color: AppColors.textSoft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ]);
}

/// A page opened from TIRPark closes with a swipe from the left edge to the
/// right, the way it came (owner, 01.11.2026); the back arrow stays.
class EdgeSwipeBack extends StatefulWidget {
  final Widget child;
  const EdgeSwipeBack({super.key, required this.child});

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 24,
          child: GestureDetector(
            key: const ValueKey('edge-swipe-back'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _dx = 0,
            onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
            onHorizontalDragEnd: (d) {
              if (_dx > 80 || (d.primaryVelocity ?? 0) > 400) Navigator.of(context).maybePop();
            },
          ),
        ),
      ]);
}

/// The way to a selected park (owner, 01.11.2026, the same as Servislər):
/// distance and time by road, and "Marşrut" that offers the navigation
/// apps (Google Maps, Waze, Sygic, Apple Maps on iPhone).
class TirParkRouteRow extends StatelessWidget {
  final AppStrings s;
  final RouteInfo? route;
  final bool hasGps;
  final VoidCallback onNavigate;
  const TirParkRouteRow({super.key, required this.s, required this.route, required this.hasGps, required this.onNavigate});

  String _duration(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return h > 0 ? s.t('map_duration_hm', {'h': '$h', 'm': '$m'}) : s.t('map_duration_m', {'m': '$m'});
  }

  @override
  Widget build(BuildContext context) {
    final r = route;
    final text = !hasGps
        ? s.t('svc_route_need_gps')
        : r == null
            ? s.t('svc_route_loading')
            : r.isRoad
                ? s.t('svc_route_info', {'km': fmtKm(r.distanceKm), 'time': r.durationMin == null ? '—' : _duration(r.durationMin!)})
                : s.t('svc_route_straight', {'km': fmtKm(r.distanceKm)});
    return Container(
      key: const ValueKey('tp-route'),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(color: AppColors.routeSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.route, size: 18, color: AppColors.route),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: AppColors.newFg))),
        const SizedBox(width: 6),
        FilledButton.icon(
          key: const ValueKey('tp-navigate'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onNavigate,
          icon: const Icon(Icons.directions, size: 18),
          label: Text(s.t('svc_route'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

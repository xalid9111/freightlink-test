import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/osm_truck_park.dart';

/// The OSM pin (owner, 11.11.2026, 0117): a smaller blue "P" with a white
/// "OSM" tag — never the platform's orange truck pin, so map data is never
/// taken for a park the platform checked.
class OsmParkPin extends StatelessWidget {
  final bool selected;
  const OsmParkPin({super.key, this.selected = false});

  static const width = 40.0, height = 40.0;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 32.0 : 26.0;
    return Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 2.5 : 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Icon(Icons.local_parking, color: Colors.white, size: size * 0.62),
      ),
      Positioned(
        top: size - 5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: Text('OSM', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w500, color: AppColors.blue, height: 1.2)),
        ),
      ),
    ]);
  }
}

/// The small "Xəritə məlumatı" mark.
class OsmBadge extends StatelessWidget {
  final AppStrings s;
  const OsmBadge({super.key, required this.s});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('osm-badge'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.blue.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.map_outlined, size: 13, color: AppColors.blue),
          const SizedBox(width: 4),
          Text(s.t('osm_badge'), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppColors.blue)),
        ]),
      );
}

/// What a tap on an OSM pin shows: the source's facts only, the mark, the
/// note that the platform did not check it, "Marşrut". No booking, no
/// reviews, no favourite, no promotion. An admin may hide a wrong object.
class OsmParkSheet extends StatelessWidget {
  final AppStrings s;
  final OsmTruckPark park;
  final VoidCallback onNavigate;
  final VoidCallback? onHide;
  const OsmParkSheet({super.key, required this.s, required this.park, required this.onNavigate, this.onHide});

  @override
  Widget build(BuildContext context) {
    final p = park;
    final facts = <String>[
      if (p.paid == true) s.t('osm_fee_yes'),
      if (p.paid == false) s.t('osm_fee_no'),
      if (p.capacity != null) s.t('osm_capacity', {'n': '${p.capacity}'}),
      for (final f in p.facilities) s.t('osm_$f'),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        key: ValueKey('osm-sheet-${p.id}'),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(p.name ?? s.t('osm_noname'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
            ),
            const SizedBox(width: 8),
            OsmBadge(s: s),
          ]),
          const SizedBox(height: 4),
          Text(s.t('osm_kind_${p.kind}'), style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in facts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(8)),
                  child: Text(f, style: TextStyle(fontSize: 12.5, color: AppColors.text)),
                ),
            ]),
          ],
          if (p.openingHours != null) ...[
            const SizedBox(height: 8),
            Text(s.t('osm_hours', {'h': p.openingHours!}), style: TextStyle(fontSize: 13, color: AppColors.text)),
          ],
          if (p.operator != null) ...[
            const SizedBox(height: 4),
            Text(s.t('osm_operator', {'o': p.operator!}), style: TextStyle(fontSize: 13, color: AppColors.text)),
          ],
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('osm-unverified'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.textSoft),
              const SizedBox(width: 8),
              Expanded(child: Text(s.t('osm_unverified'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft))),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('osm-navigate'),
                onPressed: onNavigate,
                icon: const Icon(Icons.directions, size: 18),
                label: Text(s.t('svc_route'), style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
            ),
            if (onHide != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('osm-hide'),
                onPressed: onHide,
                child: Text(s.t('osm_hide'), style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          Text('${s.t('osm_source')} · ${s.t('osm_attrib')}', style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
        ]),
      ),
    );
  }
}

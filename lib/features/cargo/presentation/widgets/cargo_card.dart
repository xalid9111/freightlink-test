import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../../../../core/constants/cities.dart';
import '../../../../core/constants/countries.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../models/cargo_model.dart';
import '../../../../repositories/profile_repository.dart';
import '../../../../core/router/safe_navigation.dart';
import '../../domain/truck_types.dart';
import 'cargo_picture.dart';

/// Cargo card in the approved "night map" design: badge row, a route
/// block (teal start dot, dashed line, end dot, flags + country + city),
/// a meta row, a 2-column spec grid and a big price with a CTA. Every
/// value is a real CargoModel field — nothing invented.
class CargoCard extends ConsumerWidget {
  final CargoModel cargo;
  final AppStrings strings;
  final VoidCallback onTap;
  /// Compact one-glance row for the home feed (route, weight, date,
  /// price, poster). Full details live on the cargo detail screen.
  final bool compact;

  const CargoCard({super.key, required this.cargo, required this.strings, required this.onTap, this.compact = false});

  Widget _compact(BuildContext context, WidgetRef ref) {
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final owner = ref.watch(publicProfileProvider(cargo.ownerId)).valueOrNull;
    final from = Countries.find(cargo.pickupCountry);
    final to = Countries.find(cargo.destinationCountry);
    final dateFmt = DateFormat('d MMM', localeCode);
    final tons = cargo.weightKg / 1000;
    final tonsText = tons == tons.roundToDouble() ? tons.toStringAsFixed(0) : tons.toStringAsFixed(1);
    // Under 1 t show kilograms (a 20 kg parcel used to read "0.0 t").
    final weightText = cargo.weightKg < 1000 ? '${_num(cargo.weightKg)} kg' : '$tonsText t';
    final meta = [
      weightText,
      dateFmt.format(cargo.pickupDate),
      if (cargo.distanceKm != null) '≈ ${_num(cargo.distanceKm!)} km',
    ].join('  ·  ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${from?.flag ?? ''} ${Cities.label(cargo.pickupCity, localeCode)}  →  ${to?.flag ?? ''} ${Cities.label(cargo.destinationCity, localeCode)}'.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                    const SizedBox(height: 3),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                    if (owner != null && owner.fullName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      // Tap the name → the owner's profile page.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.pushOnce('/user/${cargo.ownerId}'),
                        child: Row(
                        children: [
                          Flexible(
                            child: Text(owner.fullName, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                          ),
                          if (owner.isVerified) ...[
                            const SizedBox(width: 3),
                            const VerifiedTick(size: 12),
                          ],
                        ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Heart: "Seçilmiş yüklər" (0058).
              CargoFavoriteHeart(cargoId: cargo.id, size: 20),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_num(cargo.offeredPrice), style: AppFonts.display(size: 22, color: AppColors.text, height: 1)),
                  Text(cargo.currency, style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
                ],
              ),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (compact) return _compact(context, ref);
    // Locale-aware date formatting (month names etc.), so a switched
    // language looks consistent everywhere, not just in plain strings.
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final dateFmt = DateFormat('d MMM', localeCode);
    final owner = ref.watch(publicProfileProvider(cargo.ownerId)).valueOrNull;
    final from = Countries.find(cargo.pickupCountry);
    final to = Countries.find(cargo.destinationCountry);
    final shortId = '#${cargo.id.substring(0, cargo.id.length < 6 ? cargo.id.length : 6).toUpperCase()}';

    final specs = <(String, String)>[
      (strings.t('card_weight'), '${_num(cargo.weightKg)} kg'),
      if (cargo.truckType != null && cargo.truckType!.trim().isNotEmpty) (strings.t('card_truck'), truckTypeLabel(strings, cargo.truckType!)),
      if (cargo.volumeM3 != null) (strings.t('card_volume'), '${_num(cargo.volumeM3!)} m³'),
      if (cargo.cargoType != null && cargo.cargoType!.trim().isNotEmpty) (strings.t('card_cargo_type'), cargo.cargoType!),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (cargo.status == 'new') _Badge(strings.t('card_badge_new'), AppColors.newBg, AppColors.newFg),
                  const Spacer(),
                  Text(shortId, style: AppFonts.mono(color: AppColors.textSoft, weight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 10),
              // Who posted it: the name the cargo owner registered with
              // (company or person), photo and verified tick.
              if (owner != null && owner.fullName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  // Tap the photo / name → the owner's profile page.
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pushOnce('/user/${cargo.ownerId}'),
                  child: Row(
                    children: [
                      UserAvatar(imageUrl: owner.avatarUrl, initials: owner.initials, radius: 12),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          owner.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text),
                        ),
                      ),
                      if (owner.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedTick(size: 14),
                      ],
                    ],
                  ),
                  ),
                ),
              // Route block — the dominant element.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 14,
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          _dot(AppColors.route),
                          const Expanded(child: Center(child: _DashedLine())),
                          _dot(AppColors.text),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Point(flag: from?.flag, country: from?.name(localeCode) ?? cargo.pickupCountry, city: Cities.label(cargo.pickupCity, localeCode)),
                          const SizedBox(height: 12),
                          _Point(flag: to?.flag, country: to?.name(localeCode) ?? cargo.destinationCountry, city: Cities.label(cargo.destinationCity, localeCode)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _DashedDivider(),
              const SizedBox(height: 9),
              Row(
                children: [
                  Text('${strings.t('card_pickup')} ', style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  Text(dateFmt.format(cargo.pickupDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (cargo.distanceKm != null)
                    Text('≈ ${_num(cargo.distanceKm!)} km', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                runSpacing: 9,
                children: [
                  for (final s in specs)
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1, style: TextStyle(fontSize: 11, color: AppColors.textSoft)),
                          Text(s.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(_num(cargo.offeredPrice), style: AppFonts.display(size: 28, color: AppColors.text)),
                  const SizedBox(width: 5),
                  Text(cargo.currency, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  const Spacer(),
                  FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(minimumSize: const Size(44, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
                    child: Text(strings.t('cargo_card_view_details')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _dot(Color c) => Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

/// "5 000" style thousands grouping, no decimals.
String _num(double v) {
  final s = v.toStringAsFixed(0);
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0 && s[i - 1] != '-') b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

class _Point extends StatelessWidget {
  final String? flag;
  final String country;
  final String city;
  const _Point({required this.flag, required this.country, required this.city});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (flag != null) ...[
          Text(flag!, style: const TextStyle(fontSize: 22, height: 1)),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(country.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppFonts.display(size: 21, color: AppColors.text, height: 1.05)),
              Text(city, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Vertical dashed connector. A CustomPaint (not LayoutBuilder) so it
/// works inside the IntrinsicHeight route block.
class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(1.5, double.infinity), painter: _DashPainter(vertical: true, color: AppColors.route));
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter(vertical: false, color: AppColors.line)),
    );
  }
}

class _DashPainter extends CustomPainter {
  final bool vertical;
  final Color color;
  const _DashPainter({required this.vertical, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = vertical ? 1.5 : 1;
    final length = vertical ? size.height : size.width;
    const dash = 4.0;
    const gap = 3.5;
    for (double d = 0; d < length; d += dash + gap) {
      final e = (d + dash) > length ? length : d + dash;
      if (vertical) {
        canvas.drawLine(Offset(size.width / 2, d), Offset(size.width / 2, e), paint);
      } else {
        canvas.drawLine(Offset(d, size.height / 2), Offset(e, size.height / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.vertical != vertical;
}

/// Loads page tile (owner, 22.10.2026): a square picture on top (the
/// load's own / template picture, else its load type icon) with the heart,
/// under it route, weight, load type, date and price. Two in a row on a
/// phone. Every value is a real CargoModel field.
class CargoTile extends ConsumerWidget {
  final CargoModel cargo;
  final AppStrings strings;
  final VoidCallback onTap;
  /// Shown in a VIP row (0059): orange frame and a gold VIP medal (owner's
  /// design, 23.10.2026) — same size as every other tile.
  final bool vip;
  const CargoTile({super.key, required this.cargo, required this.strings, required this.onTap, this.vip = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final from = Countries.find(cargo.pickupCountry);
    final to = Countries.find(cargo.destinationCountry);
    final dateFmt = DateFormat('d MMM', localeCode);
    final tons = cargo.weightKg / 1000;
    final tonsText = tons == tons.roundToDouble() ? tons.toStringAsFixed(0) : tons.toStringAsFixed(1);
    final weight = cargo.weightKg < 1000 ? '${_num(cargo.weightKg)} kg' : '$tonsText t';
    final truck = (cargo.truckType ?? '').trim();
    final type = cargo.groupage
        ? strings.t('cargo_groupage_label')
        : (truck.isEmpty ? null : truckTypeLabel(strings, truck));
    final end = cargo.deliveryDeadline;
    final date = end == null || !end.isAfter(cargo.pickupDate)
        ? dateFmt.format(cargo.pickupDate)
        : '${dateFmt.format(cargo.pickupDate)} – ${dateFmt.format(end)}';
    // Readable on a phone (owner, 24.10.2026): bigger and in the main
    // text colour; only the small icons stay soft.
    final soft = TextStyle(fontSize: 14, color: AppColors.text, height: 1.25);

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            Icon(icon, size: 15, color: AppColors.textSoft),
            const SizedBox(width: 5),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: soft)),
          ]),
        );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('cargo-tile-${cargo.id}'),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: vip ? AppColors.accent : AppColors.tileLine, width: vip ? 2 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                CargoPicture(imageUrl: cargo.imageUrl, truckType: cargo.truckType, groupage: cargo.groupage),
                Positioned(top: 6, right: 6, child: CargoFavoriteHeart(cargoId: cargo.id, size: 19, onPhoto: true)),
                if (vip) const Positioned(key: ValueKey('tile-vip'), top: 4, left: 4, child: VipMedal(size: 50)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Full size, never shrunk; a long route takes a second line.
                Text(
                  '${from?.flag ?? ''} ${Cities.label(cargo.pickupCity, localeCode)} → ${to?.flag ?? ''} ${Cities.label(cargo.destinationCity, localeCode)}'
                      .trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.text, height: 1.2),
                ),
                line(Icons.scale_outlined, weight),
                if (type != null) line(Icons.local_shipping_outlined, type),
                line(Icons.calendar_today_outlined, date),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: _num(cargo.offeredPrice), style: AppFonts.display(size: 20, color: AppColors.text, height: 1)),
                      TextSpan(text: ' ${cargo.currency}', style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                    ]),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Gold VIP medal (owner's design, 23.10.2026): a toothed gold disc with
/// "VIP" and two ribbons under it. Drawn in code, same in day and night.
class VipMedal extends StatelessWidget {
  final double size;
  const VipMedal({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'VIP',
        child: SizedBox(width: size, height: size * 1.25, child: CustomPaint(painter: _MedalPainter())),
      );
}

class _MedalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = Offset(w / 2, w / 2);
    final r = w / 2;
    const gold = AppColors.vipGold;
    const dark = AppColors.vipGoldDark;
    const ink = AppColors.vipInk;
    // Two ribbons behind the disc.
    final ribbon = Paint()..color = ink;
    final edge = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035;
    for (final dir in [-1.0, 1.0]) {
      final x0 = c.dx + dir * r * 0.30;
      final path = Path()
        ..moveTo(x0 - r * 0.20, c.dy + r * 0.45)
        ..lineTo(x0 + r * 0.20, c.dy + r * 0.45)
        ..lineTo(x0 + dir * r * 0.30 + r * 0.17, size.height)
        ..lineTo(x0 + dir * r * 0.30, size.height - r * 0.18)
        ..lineTo(x0 + dir * r * 0.30 - r * 0.17, size.height)
        ..close();
      canvas.drawPath(path, ribbon);
      canvas.drawPath(path, edge);
    }
    // Toothed rim.
    const teeth = 18;
    final rim = Path();
    for (var i = 0; i <= teeth * 2; i++) {
      final a = i * math.pi / teeth - math.pi / 2;
      final rr = i.isEven ? r : r * 0.86;
      final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      i == 0 ? rim.moveTo(p.dx, p.dy) : rim.lineTo(p.dx, p.dy);
    }
    rim.close();
    canvas.drawPath(rim, Paint()..color = gold);
    canvas.drawPath(
        rim,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.02);
    // Dark centre with a gold ring.
    canvas.drawCircle(c, r * 0.66, Paint()..color = ink);
    canvas.drawCircle(
        c,
        r * 0.66,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.045);
    final tp = TextPainter(
      text: TextSpan(
        text: 'VIP',
        style: TextStyle(fontSize: r * 0.62, fontWeight: FontWeight.w900, color: gold, height: 1, letterSpacing: -0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

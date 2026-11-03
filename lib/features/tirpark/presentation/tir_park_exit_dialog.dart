import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// The exit sheet of a truck in the park (owner's picture, 03.11.2026): the
/// truck's real plate on an Azerbaijani number plate, the time it stayed,
/// and the amount to take — the biggest thing on the sheet. Returns true
/// when "Ödənişi aldım, çıxış et" is pressed. Only the look; the exit
/// itself and the money are the server's (tir_park_stay_exit).
class TirParkExitDialog extends StatelessWidget {
  final AppStrings s;
  final String plate;
  final String duration;
  final String amount;
  const TirParkExitDialog({super.key, required this.s, required this.plate, required this.duration, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: AzPlate(plate: plate)),
            const SizedBox(height: 10),
            Center(
              child: Container(
                key: const ValueKey('tpo-exit-dur'),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.schedule, size: 20, color: AppColors.text),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('${s.t('tpo_exit_dur')} • $duration',
                        style: TextStyle(fontSize: 16, color: AppColors.text), textAlign: TextAlign.center),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            // The amount: the most visible part (owner, 03.11.2026).
            Container(
              key: const ValueKey('tpo-exit-amount'),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.accent, width: 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.30),
                    AppColors.accent.withValues(alpha: 0.75),
                  ],
                ),
                boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 18)],
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.payments_outlined, color: AppColors.promoVip, size: 24),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(s.t('tpo_exit_amount'),
                        style: TextStyle(fontSize: 17, color: AppColors.text), textAlign: TextAlign.center),
                  ),
                ]),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(amount,
                      key: const ValueKey('tpo-exit-sum'),
                      maxLines: 1,
                      style: TextStyle(fontSize: 52, height: 1.1, fontWeight: FontWeight.w800, color: AppColors.text)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Text(s.t('tpo_exit_note'),
                key: const ValueKey('tpo-exit-text'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.35, color: AppColors.text)),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('tpo-exit-cancel'),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('common_cancel'), style: const TextStyle(fontSize: 17)),
            ),
            const SizedBox(height: 4),
            FilledButton(
              key: const ValueKey('tpo-exit-go'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('tpo_exit_btn'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// An Azerbaijani number plate: white plate, the flag and "AZ" on the left,
/// the truck's plate as stored (e.g. 10-FK-037). Long plates shrink to fit.
class AzPlate extends StatelessWidget {
  final String plate;
  const AzPlate({super.key, required this.plate});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('tpo-exit-plate'),
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.plateWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.plateInk, width: 2.5),
        boxShadow: [BoxShadow(color: AppColors.plateInk.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: IntrinsicHeight(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                width: 30,
                height: 18,
                child: Column(children: [
                  Expanded(child: Container(color: AppColors.plateFlagBlue)),
                  Expanded(child: Container(color: AppColors.plateFlagRed)),
                  Expanded(child: Container(color: AppColors.plateFlagGreen)),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(border: Border.all(color: AppColors.plateInk, width: 1), borderRadius: BorderRadius.circular(3)),
              child: const Text('AZ', style: TextStyle(fontSize: 14, height: 1.2, color: AppColors.plateInk)),
            ),
          ]),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(plate,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 46, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.plateInk)),
            ),
          ),
        ]),
      ),
    );
  }
}

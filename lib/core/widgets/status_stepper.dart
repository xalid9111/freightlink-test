import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

/// Horizontal delivery-stage stepper from the approved design: teal for
/// finished stages, an orange glowing node for the current one, grey for
/// the rest. Works for both cargo.status and shipments.status (same
/// vocabulary, migration 0001). Labels reuse shipment_status_* strings.
class StatusStepper extends StatelessWidget {
  final String status;
  final AppStrings strings;
  /// Show the leading "new" stage (cargo detail) or start at "agreed"
  /// (shipments, which only exist once an offer was accepted).
  final bool includeNew;

  const StatusStepper({super.key, required this.status, required this.strings, this.includeNew = true});

  static const _all = ['new', 'agreed', 'loading', 'in_transit', 'delivered'];

  int _currentIndex(List<String> steps) {
    final s = switch (status) {
      'carrier_found' => 'agreed',
      'completed' => 'delivered',
      _ => status,
    };
    final i = steps.indexOf(s);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final steps = includeNew ? _all : _all.sublist(1);
    final current = _currentIndex(steps);
    final allDone = status == 'completed';

    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final done = allDone || i < current;
      final now = !allDone && i == current;
      if (i > 0) {
        children.add(Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.only(top: 6),
            color: (done || now) ? AppColors.route : AppColors.line,
          ),
        ));
      }
      children.add(SizedBox(
        width: 56,
        child: Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: now ? AppColors.accentFill : (done ? AppColors.route : AppColors.line),
                border: Border.all(color: AppColors.card, width: 2),
                boxShadow: now ? [BoxShadow(color: AppColors.accentFill.withValues(alpha: 0.35), spreadRadius: 4)] : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.t('shipment_status_${steps[i]}'),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: (done || now) ? FontWeight.w500 : FontWeight.w400,
                color: (done || now) ? AppColors.text : AppColors.textSoft,
              ),
            ),
          ],
        ),
      ));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'theme_mode.dart';

/// While an admin tries night colours on this device ("Önizlə", 0076): a
/// small "Önizləmə · Bitir" pill on top, so it is never forgotten. Nobody
/// else ever sees it.
class NightPreviewBadge extends StatelessWidget {
  final Widget child;
  const NightPreviewBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!nightPreviewActive) return child;
    return Stack(children: [
      child,
      Positioned(
        top: MediaQuery.of(context).padding.top + 6,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: AppColors.accentFill,
            shape: const StadiumBorder(),
            elevation: 4,
            child: const InkWell(
              key: ValueKey('night-preview-end'),
              customBorder: StadiumBorder(),
              onTap: endNightPreview,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.visibility_outlined, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Önizləmə · Bitir', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

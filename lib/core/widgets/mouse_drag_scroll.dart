import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// Horizontal rows (category chips, popular routes, photos …) can be
/// dragged sideways with the mouse on computers, like with a finger on a
/// phone. Flutter lets only touch drag a list by default, so on a PC the
/// items past the right edge could not be reached.
///
/// Used only around horizontal rows: vertical pages keep the default
/// (mouse wheel), so text selection etc. is unchanged.
class MouseDragScroll extends StatelessWidget {
  final Widget child;
  const MouseDragScroll({super.key, required this.child});

  static const dragDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(dragDevices: dragDevices),
        child: child,
      );
}

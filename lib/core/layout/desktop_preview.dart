import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../localization/locale_controller.dart';
import '../theme/app_theme.dart';
import 'desktop_layout.dart';

/// Desktop preview — TEST ONLY (owner, 19.10.2026). On a phone the whole
/// app is laid out as on a 1440 × 900 computer screen; the phone shows it
/// scaled, with pinch-zoom and sideways panning. Off by default; when off
/// nothing changes at all. Kept on this device; the "Mobil görünüş" button
/// (always on screen in the preview) switches back.
const Size kDesktopPreviewCanvas = Size(1440, 900);
const kDesktopPreviewKey = 'desktop_preview';

bool _initialDesktopPreview = false;

Future<void> loadSavedDesktopPreview() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _initialDesktopPreview = prefs.getBool(kDesktopPreviewKey) ?? false;
  } catch (_) {
    _initialDesktopPreview = false;
  }
}

class DesktopPreviewController extends StateNotifier<bool> {
  DesktopPreviewController() : super(_initialDesktopPreview);

  Future<void> set(bool on) async {
    if (on == state) return;
    state = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kDesktopPreviewKey, on);
    } catch (_) {}
  }
}

final desktopPreviewProvider = StateNotifierProvider<DesktopPreviewController, bool>((ref) => DesktopPreviewController());

/// Wraps the whole app (MaterialApp.builder). Off, or on a real computer
/// screen: returns [child] unchanged.
Widget applyDesktopPreview(BuildContext context, bool on, Widget child) {
  if (!on || MediaQuery.sizeOf(context).width >= kDesktopMinWidth) return child;
  return _DesktopPreviewFrame(child: child);
}

class _DesktopPreviewFrame extends ConsumerStatefulWidget {
  final Widget child;
  const _DesktopPreviewFrame({required this.child});

  @override
  ConsumerState<_DesktopPreviewFrame> createState() => _DesktopPreviewFrameState();
}

class _DesktopPreviewFrameState extends ConsumerState<_DesktopPreviewFrame> {
  final _view = TransformationController();
  Size? _screen;

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    const canvas = kDesktopPreviewCanvas;
    // Smallest zoom: the whole 1440 px width on the phone screen.
    final fitWidth = screen.width / canvas.width;
    // Start: the full page height on screen, pan sideways for the rest.
    final start = math.min(1.0, screen.height / canvas.height);
    final minScale = math.min(fitWidth, start);
    if (_screen != screen) {
      _screen = screen;
      _view.value = Matrix4.diagonal3Values(start, start, 1);
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.background,
            child: InteractiveViewer(
              key: const ValueKey('desktop-preview'),
              transformationController: _view,
              constrained: false,
              minScale: minScale,
              // Room below / beside the page, so it can be zoomed out to the
              // whole width (InteractiveViewer never shows past its margin).
              boundaryMargin: EdgeInsets.only(
                right: math.max(0, screen.width / minScale - canvas.width),
                bottom: math.max(0, screen.height / minScale - canvas.height),
              ),
              maxScale: 2.5,
              child: SizedBox.fromSize(
                size: canvas,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: canvas,
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12 + mq.padding.bottom,
          child: Material(
            color: AppColors.accentFill,
            shape: const StadiumBorder(),
            elevation: 6,
            child: InkWell(
              key: const ValueKey('desktop-preview-exit'),
              customBorder: const StadiumBorder(),
              onTap: () => ref.read(desktopPreviewProvider.notifier).set(false),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.smartphone, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(ref.watch(stringsProvider).t('desk_preview_exit'),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

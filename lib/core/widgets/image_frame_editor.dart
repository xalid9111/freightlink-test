import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'framed_image.dart';

/// "Yerini düzəlt" (owner, 29.10.2026): the picture in a fixed frame of
/// the shape it has on the profile (a circle for the profile picture, the
/// cover's rectangle). The user drags it and zooms (two fingers or the
/// slider), then saves. Returns the framing, or null when cancelled. The
/// picture itself is not changed, so a GIF stays animated.
class ImageFrameEditorScreen extends StatefulWidget {
  final ImageProvider image;
  final ImageFraming initial;

  /// Width / height of the frame (1 for the profile picture).
  final double aspect;
  final bool circle;
  final String title;
  final AppStrings s;
  const ImageFrameEditorScreen({
    super.key,
    required this.image,
    required this.aspect,
    required this.circle,
    required this.title,
    required this.s,
    this.initial = ImageFraming.centre,
  });

  @override
  State<ImageFrameEditorScreen> createState() => _ImageFrameEditorScreenState();
}

/// How far (−1…1) the picture moves for a drag of [delta] points in a
/// frame of [frame] points, when the zoomed picture is [overflow] points
/// bigger than the frame. Nothing moves when it is not bigger.
double frameShift(double delta, double overflow) => overflow > 0.5 ? -2 * delta / overflow : 0;

/// Size of [image] filling [frame] like BoxFit.cover, zoomed [z]×.
Size coverSize(Size image, Size frame, double z) {
  if (image.isEmpty) return frame * z;
  final s = (frame.width / image.width) > (frame.height / image.height) ? frame.width / image.width : frame.height / image.height;
  return Size(image.width * s * z, image.height * s * z);
}

class _ImageFrameEditorScreenState extends State<ImageFrameEditorScreen> {
  late ImageFraming _f = widget.initial;
  ImageFraming _start = ImageFraming.centre;
  Size _image = Size.zero;
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (mounted) setState(() => _image = Size(info.image.width.toDouble(), info.image.height.toDouble()));
  }, onError: (_, __) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream?.removeListener(_listener);
    _stream = widget.image.resolve(createLocalImageConfiguration(context))..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _drag(Offset d, Size frame) {
    final big = coverSize(_image, frame, _f.z);
    setState(() => _f = _f.copyWith(
          ax: _f.ax + frameShift(d.dx, big.width - frame.width),
          ay: _f.ay + frameShift(d.dy, big.height - frame.height),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        leading: IconButton(
          tooltip: s.t('common_cancel'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final maxW = (box.maxWidth - 32).clamp(80.0, widget.circle ? 360.0 : 900.0);
              var frame = Size(maxW, maxW / widget.aspect);
              if (frame.height > box.maxHeight - 32) {
                final h = box.maxHeight - 32;
                frame = Size(h * widget.aspect, h);
              }
              final shape = widget.circle
                  ? const CircleBorder(side: BorderSide(color: Colors.white, width: 2))
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Colors.white, width: 2));
              return Center(
                child: GestureDetector(
                  key: const ValueKey('frame-area'),
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) => _start = _f,
                  onScaleUpdate: (d) {
                    if (d.pointerCount > 1) setState(() => _f = _f.copyWith(z: _start.z * d.scale));
                    _drag(d.focalPointDelta, frame);
                  },
                  child: Container(
                    key: const ValueKey('frame-box'),
                    width: frame.width,
                    height: frame.height,
                    foregroundDecoration: ShapeDecoration(shape: shape),
                    child: ClipPath(
                      clipper: ShapeBorderClipper(shape: shape),
                      child: FramedImage(image: widget.image, framing: _f),
                    ),
                  ),
                ),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Text(s.t('cover_crop_hint'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              const Icon(Icons.zoom_out, color: Colors.white70),
              Expanded(
                child: Slider(
                  key: const ValueKey('frame-zoom'),
                  value: _f.z,
                  min: 1,
                  max: kFrameMaxZoom,
                  activeColor: AppColors.accent,
                  onChanged: (v) => setState(() => _f = _f.copyWith(z: v)),
                ),
              ),
              const Icon(Icons.zoom_in, color: Colors.white70),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('frame-reset'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  onPressed: () => setState(() => _f = ImageFraming.centre),
                  child: Text(s.t('frame_reset')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const ValueKey('frame-save'),
                  onPressed: () => Navigator.of(context).pop(_f),
                  child: Text(s.t('catalog_save')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

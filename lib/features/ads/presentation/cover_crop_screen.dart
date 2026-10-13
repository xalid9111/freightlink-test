import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

/// After picking a cover photo: the user drags (left / right / up / down)
/// and pinch-zooms the photo inside a frame that has the cover's shape,
/// then saves. Returns the cropped picture as PNG bytes, or null when
/// cancelled. Pure Flutter — no extra package.
class CoverCropScreen extends StatefulWidget {
  final Uint8List bytes;

  /// Width / height of the cover area on the profile page.
  final double aspect;
  final AppStrings s;

  /// Screen title; defaults to "change cover photo".
  final String? title;
  const CoverCropScreen({super.key, required this.bytes, required this.aspect, required this.s, this.title});

  @override
  State<CoverCropScreen> createState() => _CoverCropScreenState();
}

class _CoverCropScreenState extends State<CoverCropScreen> {
  final _ctrl = TransformationController();
  ui.Image? _image;
  bool _saving = false;
  bool _centered = false;
  Size _frame = Size.zero;
  Size _child = Size.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _image?.dispose();
    super.dispose();
  }

  /// Size of the photo at zoom 1: just big enough to fill the frame.
  Size _fitSize(ui.Image img, Size frame) {
    final imgAspect = img.width / img.height;
    if (imgAspect > frame.width / frame.height) {
      return Size(frame.height * imgAspect, frame.height);
    }
    return Size(frame.width, frame.width / imgAspect);
  }

  Future<void> _save() async {
    final img = _image;
    if (img == null || _frame.isEmpty || _child.isEmpty) return;
    setState(() => _saving = true);
    try {
      final m = _ctrl.value.storage;
      final scale = m[0] <= 0 ? 1.0 : m[0];
      final left = -m[12] / scale;
      final top = -m[13] / scale;
      final f = img.width / _child.width; // layout px → image px
      final src = Rect.fromLTWH(left * f, top * f, _frame.width / scale * f, _frame.height / scale * f)
          .intersect(Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()));
      final int outW = src.width < 1 ? 1 : (src.width > 1200 ? 1200 : src.width.round());
      final int rawH = (outW / widget.aspect).round();
      final int outH = rawH < 1 ? 1 : rawH;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(outW, outH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (!mounted) return;
      if (data == null) {
        setState(() => _saving = false);
        return;
      }
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final img = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.title ?? s.t('profile_change_cover')),
        leading: IconButton(
          tooltip: s.t('common_cancel'),
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: img == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, box) {
                      final w = box.maxWidth - 24;
                      var frame = Size(w, w / widget.aspect);
                      if (frame.height > box.maxHeight - 24) {
                        final h = box.maxHeight - 24;
                        frame = Size(h * widget.aspect, h);
                      }
                      final child = _fitSize(img, frame);
                      _frame = frame;
                      _child = child;
                      if (!_centered) {
                        _centered = true;
                        _ctrl.value = Matrix4.translationValues(
                          -(child.width - frame.width) / 2,
                          -(child.height - frame.height) / 2,
                          0,
                        );
                      }
                      return Center(
                        child: Container(
                          width: frame.width,
                          height: frame.height,
                          decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 1.5)),
                          child: ClipRect(
                            child: InteractiveViewer(
                              transformationController: _ctrl,
                              constrained: false,
                              minScale: 1,
                              maxScale: 5,
                              boundaryMargin: EdgeInsets.zero,
                              child: SizedBox(
                                width: child.width,
                                height: child.height,
                                child: RawImage(image: img, fit: BoxFit.fill),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      s.t('cover_crop_hint'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 13.5),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(s.t('catalog_save')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

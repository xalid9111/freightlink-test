import 'package:flutter/material.dart';

/// Which part of a profile picture / cover shows (owner, 29.10.2026): the
/// picture is kept whole (a GIF stays animated) and the chosen place and
/// zoom travel in its link as `ax`, `ay` (−1…1, like [Alignment]) and `z`
/// (1…[kFrameMaxZoom]). Storage ignores these; old links mean "centre, 1×".
class ImageFraming {
  final double ax, ay, z;
  const ImageFraming({this.ax = 0, this.ay = 0, this.z = 1});

  static const centre = ImageFraming();

  bool get isDefault => ax == 0 && ay == 0 && z == 1;

  Alignment get alignment => Alignment(ax, ay);

  ImageFraming copyWith({double? ax, double? ay, double? z}) => ImageFraming(
        ax: (ax ?? this.ax).clamp(-1.0, 1.0),
        ay: (ay ?? this.ay).clamp(-1.0, 1.0),
        z: (z ?? this.z).clamp(1.0, kFrameMaxZoom),
      );

  /// The framing kept in [url] (centre when none or unreadable).
  static ImageFraming of(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null) return centre;
    double read(String k, double def, double lo, double hi) {
      final v = double.tryParse(uri.queryParameters[k] ?? '');
      return v == null || v.isNaN ? def : v.clamp(lo, hi);
    }

    return ImageFraming(ax: read('ax', 0, -1, 1), ay: read('ay', 0, -1, 1), z: read('z', 1, 1, kFrameMaxZoom));
  }

  /// [url] with this framing (other parameters such as `v` are kept).
  String applyTo(String url) {
    final uri = Uri.parse(url);
    final q = Map<String, String>.from(uri.queryParameters)..removeWhere((k, _) => k == 'ax' || k == 'ay' || k == 'z');
    if (!isDefault) {
      q['ax'] = ax.toStringAsFixed(3);
      q['ay'] = ay.toStringAsFixed(3);
      q['z'] = z.toStringAsFixed(3);
    }
    return uri.replace(queryParameters: q.isEmpty ? null : q).toString();
  }

  /// [url] without the framing — the picture itself.
  static String baseOf(String url) => const ImageFraming().applyTo(url);
}

const kFrameMaxZoom = 4.0;

/// [image] filling its box like BoxFit.cover, moved to [framing.alignment]
/// and zoomed [framing.z]× around it. The same at every size of the same
/// shape, so the editor's frame shows exactly what the profile shows.
class FramedImage extends StatelessWidget {
  final ImageProvider image;
  final ImageFraming framing;
  final ImageErrorWidgetBuilder? errorBuilder;
  const FramedImage({super.key, required this.image, required this.framing, this.errorBuilder});

  @override
  Widget build(BuildContext context) {
    final a = framing.alignment;
    return ClipRect(
      child: Transform.scale(
        scale: framing.z,
        alignment: a,
        child: Image(
          image: image,
          fit: BoxFit.cover,
          alignment: a,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          errorBuilder: errorBuilder,
        ),
      ),
    );
  }
}

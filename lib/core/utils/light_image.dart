import 'dart:async';

import 'package:flutter/widgets.dart';

// Faster site, stage 1 (owner, 16.11.2026): the admins' own pictures — the
// load-type templates (2.5 MB PNG each) and the page banners (2.7 MB PNG) —
// are asked for at the size they are shown, as WebP, through Supabase's
// image service (/storage/v1/render/image/...): ~45 KB per template card,
// ~120–185 KB per banner. The stored files and every saved address stay as
// they are; when the service does not answer, the original file is shown.

/// The widths asked for (shared steps, so phones of one size share the
/// server's cache).
// 2400 = the sharpest a banner is ever decoded at (heroDecodeWidth), so a
// banner stays as sharp as before.
const kLightWidths = [480, 640, 960, 1280, 1920, 2400];

/// The step at or above [px] (the largest one for bigger screens).
int lightWidthStep(int px) => kLightWidths.firstWhere((w) => w >= px, orElse: () => kLightWidths.last);

/// The image service sends WebP only when it is asked for it.
const kLightImageHeaders = {'Accept': 'image/webp,image/*'};

const _object = '/storage/v1/object/public/';

/// Whether [url] is one of the admins' pictures handled here: a load-type
/// template (cargo-photos/templates/…) or a page banner (…/hero_….);
/// never a GIF (it would stop moving) and never a user's own photo.
bool isLightImage(String url) {
  final i = url.indexOf(_object);
  if (i < 0 || url.contains('?')) return false;
  final path = url.substring(i + _object.length).toLowerCase();
  if (path.endsWith('.gif')) return false;
  return path.startsWith('cargo-photos/templates/') || RegExp(r'/hero_[^/]+$').hasMatch(path);
}

/// The light address of [url] for a picture shown [px] pixels wide; any
/// other address comes back unchanged. `resize=contain` keeps the WHOLE
/// picture in its own proportions (owner, 16.11.2026: with only a width the
/// service kept the original height and cut a narrow strip out of it).
String lightImageUrl(String url, int px) {
  if (!isLightImage(url)) return url;
  final i = url.indexOf(_object);
  final host = url.substring(0, i).replaceAll(RegExp(r'/+$'), '');
  final path = url.substring(i + _object.length);
  return '$host/storage/v1/render/image/public/$path?width=${lightWidthStep(px)}&resize=contain&quality=80';
}

/// Draws [url] through [builder] with its light address (and the headers it
/// needs); if that fails, once more with the original address. [onError] is
/// shown only when the original fails too.
class LightImage extends StatefulWidget {
  final String url;
  final int px;
  final Widget Function(BuildContext context, String src, Map<String, String>? headers, ImageErrorWidgetBuilder onError)
      builder;
  final ImageErrorWidgetBuilder onError;
  const LightImage({super.key, required this.url, required this.px, required this.builder, required this.onError});

  @override
  State<LightImage> createState() => _LightImageState();
}

class _LightImageState extends State<LightImage> {
  bool _original = false;

  @override
  void didUpdateWidget(LightImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _original = false;
  }

  @override
  Widget build(BuildContext context) {
    final light = _original ? widget.url : lightImageUrl(widget.url, widget.px);
    if (light == widget.url) return widget.builder(context, widget.url, null, widget.onError);
    return widget.builder(context, light, kLightImageHeaders, (c, e, s) {
      scheduleMicrotask(() {
        if (mounted && !_original) setState(() => _original = true);
      });
      return widget.onError(c, e, s);
    });
  }
}

import 'package:flutter/material.dart';

/// An app picture (asset) that tries again by itself (AutoFix, owner
/// 15.11.2026): a dropped connection or a new version being published at
/// that moment ("Unable to load asset") left the load-type picture empty.
/// Up to [retries] new tries, 2 s / 6 s apart; meanwhile and after that the
/// [fallback] (or nothing) — never an error report per card.
class RetryAssetImage extends StatefulWidget {
  final String asset;
  final BoxFit? fit;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Widget? fallback;
  final int retries;
  const RetryAssetImage(this.asset,
      {super.key, this.fit, this.color, this.colorBlendMode, this.fallback, this.retries = 2});

  /// The pause before try n (1, 2, …).
  static Duration delayFor(int attempt) => Duration(seconds: attempt <= 1 ? 2 : 6);

  @override
  State<RetryAssetImage> createState() => _RetryAssetImageState();
}

class _RetryAssetImageState extends State<RetryAssetImage> {
  int _attempt = 0;
  bool _scheduled = false;

  void _retryLater() {
    if (_scheduled || _attempt >= widget.retries) return;
    _scheduled = true;
    Future<void>.delayed(RetryAssetImage.delayFor(_attempt + 1), () {
      if (!mounted) return;
      // A failed picture is not kept in the cache; a new key loads it again.
      imageCache.evict(AssetImage(widget.asset));
      setState(() {
        _attempt++;
        _scheduled = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      widget.asset,
      key: ValueKey('${widget.asset}#$_attempt'),
      fit: widget.fit,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      errorBuilder: (_, __, ___) {
        _retryLater();
        return widget.fallback ?? const SizedBox.shrink();
      },
    );
  }
}

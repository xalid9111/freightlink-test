import 'package:flutter/material.dart';

/// One line of text that, when it does not fit, glides smoothly to its end
/// by itself, rests, glides back and repeats (owner, 22.11.2026: the chat's
/// "son görülmə: dünən …" was cut off — "axıcı olsun və avtomatik
/// sürüşərək geridə qalan qismi görünsün"). A text that fits stands still;
/// phones asking for less motion get the plain ellipsis.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Glide speed in logical pixels a second.
  final double speed;

  /// Rest at each end before gliding on.
  final Duration pause;
  const MarqueeText(this.text, {super.key, this.style, this.speed = kMarqueeSpeed, this.pause = kMarqueePause});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

const double kMarqueeSpeed = 28;
const Duration kMarqueePause = Duration(milliseconds: 1600);

/// How long one glide over [overflow] pixels takes at [speed] px / s
/// (at least 0.6 s so a tiny overflow still moves calmly).
Duration marqueeGlide(double overflow, double speed) {
  if (overflow <= 0 || speed <= 0) return Duration.zero;
  final ms = (overflow / speed * 1000).round();
  return Duration(milliseconds: ms < 600 ? 600 : ms);
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  // 0 = the start of the text, 1 = its end in view. Not a scroll view: the
  // line is never dragged, it only moves by itself.
  late final AnimationController _c;
  bool _running = false;
  int _run = 0;
  double _overflow = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _run++; // a new text starts again from its beginning
      _running = false;
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _run++;
    _c.dispose();
    super.dispose();
  }

  Future<void> _loop(int run) async {
    try {
      while (mounted && run == _run) {
        await Future<void>.delayed(widget.pause);
        if (!mounted || run != _run) return;
        if (_overflow <= 0) {
          _running = false;
          return;
        }
        final glide = marqueeGlide(_overflow, widget.speed);
        await _c.animateTo(1, duration: glide, curve: Curves.easeInOut);
        await Future<void>.delayed(widget.pause);
        if (!mounted || run != _run) return;
        await _c.animateTo(0, duration: glide, curve: Curves.easeInOut);
      }
    } on TickerCanceled {
      // disposed or a new text: the next loop (if any) takes over
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return Text(widget.text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return LayoutBuilder(builder: (context, c) {
      final tp = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      _overflow = tp.width - c.maxWidth;
      tp.dispose();
      final text = Text(widget.text, style: style, maxLines: 1, softWrap: false);
      if (_overflow <= 0) return text;
      if (!_running) {
        _running = true;
        final run = _run;
        WidgetsBinding.instance.addPostFrameCallback((_) => _loop(run));
      }
      return UnconstrainedBox(
        key: const ValueKey('marquee-box'),
        alignment: Alignment.centerLeft,
        constrainedAxis: Axis.vertical,
        clipBehavior: Clip.hardEdge,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.translate(
            key: const ValueKey('marquee-move'),
            offset: Offset(-_overflow * _c.value, 0),
            child: child,
          ),
          child: text,
        ),
      );
    });
  }
}

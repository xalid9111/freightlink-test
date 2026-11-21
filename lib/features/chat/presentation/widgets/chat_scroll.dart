import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';

// Owner, 16.11.2026: links in a message open with a tap; older messages stay
// in the archive and load by themselves while scrolling up; a ⌄ button brings
// the chat back to the newest message (with the count of new ones that came
// in meanwhile).

/// http(s):// … or www. … up to a space; trailing punctuation is not part of it.
final _linkRe = RegExp(r'(?:https?:\/\/|www\.)[^\s<>"]+', caseSensitive: false);

/// "https://tirlink.app/#/cargo/12" → "/cargo/12": a page of this app (its
/// own address or tirlink.app); null for any other link.
String? appPathOf(Uri link) {
  final own = {'tirlink.app', 'www.tirlink.app', if (Uri.base.host.isNotEmpty) Uri.base.host};
  if (!own.contains(link.host.toLowerCase())) return null;
  final f = link.fragment;
  return f.startsWith('/') && f.length > 1 ? f : null;
}

/// The text split into plain parts and link parts; only http / https links.
List<(String text, Uri? link)> splitLinks(String text) {
  final out = <(String, Uri?)>[];
  var at = 0;
  for (final m in _linkRe.allMatches(text)) {
    var raw = m.group(0)!;
    // "… bax: https://x.az." — the closing dot / comma / bracket stays text.
    while (raw.isNotEmpty && '.,;:!?)]}\'"'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    final uri = Uri.tryParse(raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) continue;
    if (m.start > at) out.add((text.substring(at, m.start), null));
    out.add((raw, uri));
    at = m.start + raw.length;
  }
  if (at < text.length) out.add((text.substring(at), null));
  return out;
}

/// A message's text with its links underlined; a tap opens the link in a new
/// browser tab (the Home Screen app: Safari), TırLink stays open.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const LinkifiedText(this.text, {super.key, required this.style});

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final _taps = <TapGestureRecognizer>[];

  void _clear() {
    for (final r in _taps) {
      r.dispose();
    }
    _taps.clear();
  }

  TapGestureRecognizer _tap(Uri link) {
    final r = TapGestureRecognizer()
      ..onTap = () {
        // A TırLink page (a shared load …) opens right here in the app
        // (owner, 21.11.2026: "linkə basıldıqda birbaşa yük açılsın").
        final inApp = appPathOf(link);
        if (inApp != null) {
          GoRouter.of(context).go(inApp);
          return;
        }
        launchUrl(link, mode: LaunchMode.externalApplication);
      };
    _taps.add(r);
    return r;
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = splitLinks(widget.text);
    if (parts.every((p) => p.$2 == null)) return Text(widget.text, style: widget.style);
    _clear();
    return Text.rich(TextSpan(style: widget.style, children: [
      for (final (t, link) in parts)
        if (link == null)
          TextSpan(text: t)
        else
          TextSpan(
            text: t,
            // The bubble's own text colour (readable on both bubbles, day and
            // night), underlined like a link.
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: widget.style.color,
            ),
            recognizer: _tap(link),
          ),
    ]));
  }
}

/// The row on top of a chat that still has older messages: a small spinner;
/// as soon as it comes near the screen the next older part is asked for.
class ChatOlderLoader extends StatefulWidget {
  final VoidCallback onLoad;
  const ChatOlderLoader({super.key, required this.onLoad});

  @override
  State<ChatOlderLoader> createState() => _ChatOlderLoaderState();
}

class _ChatOlderLoaderState extends State<ChatOlderLoader> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoad();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: ChatColors.meta),
          ),
        ),
      );
}

/// How many of [incoming] (other people's message ids, oldest first) came
/// after the newest one already [seen]; older ones loaded later never count.
int unseenAfter(List<String> incoming, Set<String> seen) {
  for (var i = incoming.length - 1; i >= 0; i--) {
    if (seen.contains(incoming[i])) return incoming.length - 1 - i;
  }
  return 0;
}

/// The list of a chat (reverse: offset 0 = the newest message) with the round
/// ⌄ button at its lower right while the user reads further up.
class ChatJumpToLatest extends StatefulWidget {
  final ScrollController controller;

  /// Other people's message ids, oldest first.
  final List<String> incoming;
  final String tooltip;
  final Widget child;
  const ChatJumpToLatest({
    super.key,
    required this.controller,
    required this.incoming,
    required this.tooltip,
    required this.child,
  });

  /// Further up than this (px) = the button shows.
  static const showAfter = 300.0;

  @override
  State<ChatJumpToLatest> createState() => _ChatJumpToLatestState();
}

class _ChatJumpToLatestState extends State<ChatJumpToLatest> {
  bool _away = false;
  final _seen = <String>{};

  bool get _isAway => widget.controller.hasClients && widget.controller.offset > ChatJumpToLatest.showAfter;

  @override
  void initState() {
    super.initState();
    _seen.addAll(widget.incoming);
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ChatJumpToLatest old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    if (!_away) _seen.addAll(widget.incoming);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final away = _isAway;
    if (!away) _seen.addAll(widget.incoming);
    if (away != _away) setState(() => _away = away);
  }

  Future<void> _jump() async {
    final c = widget.controller;
    if (!c.hasClients) return;
    // A long way up: most of it at once, the last part smoothly.
    if (c.offset > 3000) c.jumpTo(1200);
    await c.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final n = _away ? unseenAfter(widget.incoming, _seen) : 0;
    return Stack(children: [
      Positioned.fill(child: widget.child),
      Positioned(
        right: 12,
        bottom: 12,
        child: IgnorePointer(
          ignoring: !_away,
          child: AnimatedOpacity(
            opacity: _away ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: AnimatedScale(
              scale: _away ? 1 : 0.8,
              duration: const Duration(milliseconds: 180),
              child: Stack(clipBehavior: Clip.none, children: [
                Material(
                  key: const ValueKey('chat-jump-latest'),
                  color: ChatColors.theirs,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _jump,
                    child: Tooltip(
                      message: widget.tooltip,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.keyboard_arrow_down_rounded, size: 30, color: ChatColors.text),
                      ),
                    ),
                  ),
                ),
                if (n > 0)
                  Positioned(
                    top: -6,
                    right: -4,
                    child: Container(
                      key: const ValueKey('chat-jump-count'),
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                      child: Text(n > 99 ? '99+' : '$n',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

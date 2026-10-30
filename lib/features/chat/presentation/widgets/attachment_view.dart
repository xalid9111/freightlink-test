import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/message_model.dart';
import '../providers/chat_providers.dart';
import 'voice/voice_audio.dart';

/// Renders a message's attachment (migration 0010) inside its bubble:
/// photo thumbnail, voice-note player, or a file row. Files live in the
/// PRIVATE bucket chat-files and are reached through 1-hour signed links.
class AttachmentView extends ConsumerWidget {
  final MessageModel message;
  final bool isMine;
  final AppStrings strings;
  const AttachmentView({super.key, required this.message, required this.isMine, required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(attachmentUrlProvider(message.attachmentPath!));
    final fg = isMine ? ChatColors.text : AppColors.text;

    switch (message.attachmentType) {
      case 'image':
        return urlAsync.when(
          loading: () => const SizedBox(
            width: 220,
            height: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => _FileRow(message: message, url: null, color: fg),
          data: (url) => GestureDetector(
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                width: 220,
                // Decoded at the shown width (×3 for sharp retina), not the
                // full photo: long chats stay light on iPhones.
                cacheWidth: 660,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _FileRow(message: message, url: url, color: fg),
              ),
            ),
          ),
        );
      case 'audio':
        return urlAsync.when(
          loading: () => const SizedBox(width: 200, height: 40, child: Center(child: LinearProgressIndicator())),
          error: (_, __) => Text(strings.t('chat_voice_message'), style: TextStyle(color: fg)),
          data: (url) => _VoicePlayer(url: url, durationMs: message.audioDurationMs, color: fg, strings: strings),
        );
      default:
        return _FileRow(message: message, url: urlAsync.valueOrNull, color: fg);
    }
  }
}

class _FileRow extends StatelessWidget {
  final MessageModel message;
  final String? url;
  final Color color;
  const _FileRow({required this.message, required this.url, required this.color});

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: url == null ? null : () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, color: color, size: 28),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message.attachmentName ?? 'file',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w400)),
                  Text(_size(message.attachmentSize), style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoicePlayer extends StatefulWidget {
  final String url;
  final int? durationMs;
  final Color color;
  final AppStrings strings;
  const _VoicePlayer({required this.url, required this.durationMs, required this.color, required this.strings});

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  /// Only one voice note plays at a time.
  static _VoicePlayerState? _active;

  final VoiceAudio _player = VoiceAudio();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _playing = false;
  bool _failed = false;
  Duration _pos = Duration.zero;
  Duration? _dur;

  @override
  void initState() {
    super.initState();
    if (widget.durationMs != null && widget.durationMs! > 0) _dur = Duration(milliseconds: widget.durationMs!);
    _subs.add(_player.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
    }));
    _subs.add(_player.position.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.duration.listen((d) {
      // Prefer the real length; keep the recorded one if the browser
      // reports nothing useful.
      if (mounted && d > Duration.zero) setState(() => _dur = d);
    }));
    _subs.add(_player.completed.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    }));
    _subs.add(_player.failed.listen((_) {
      if (mounted) setState(() => _failed = true);
    }));
  }

  @override
  void dispose() {
    if (identical(_active, this)) _active = null;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_playing) {
      _player.pause();
      return;
    }
    final other = _active;
    if (other != null && !identical(other, this) && other.mounted) other._player.pause();
    _active = this;
    setState(() => _failed = false);
    _player.play(widget.url);
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _dur ?? Duration.zero;
    final progress = total.inMilliseconds > 0 ? (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: 220,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 36, color: widget.color),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    color: widget.color,
                    backgroundColor: widget.color.withValues(alpha: 0.25),
                  ),
                ),
                const SizedBox(height: 4),
                if (_failed)
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
                    child: Text(
                      widget.strings.t('chat_voice_cant_play'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: widget.color, decoration: TextDecoration.underline),
                    ),
                  )
                else
                  Text(
                    _playing || _pos > Duration.zero ? _fmt(_pos) : _fmt(total),
                    style: TextStyle(fontSize: 11, color: widget.color.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

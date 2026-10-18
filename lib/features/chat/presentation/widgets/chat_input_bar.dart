import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../../../core/autofix/autofix.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import 'location_message.dart';

typedef SendAttachment = Future<void> Function({
  required Uint8List bytes,
  required String type,
  required String fileName,
  String? contentType,
  int? audioDurationMs,
});

/// WhatsApp-style composer: 📎 attach (photo / camera / file), text
/// field, and on the right a mic button that turns into a send button
/// as soon as there is text. Tapping the mic starts recording; the bar
/// then shows a timer with "cancel" and "send".
class ChatInputBar extends StatefulWidget {
  final AppStrings strings;
  final Future<void> Function(String text) onSendText;
  final SendAttachment onSendAttachment;

  const ChatInputBar({super.key, required this.strings, required this.onSendText, required this.onSendAttachment});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  static const _maxBytes = 20 * 1024 * 1024; // matches the bucket limit (migration 0010)

  final _ctrl = TextEditingController();
  bool _busy = false;

  AudioRecorder? _rec;
  AudioEncoder _encoder = AudioEncoder.aacLc;
  DateTime? _recStart;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  bool get _recording => _rec != null;
  bool get _hasText => _ctrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _rec?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.t(key))));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e, st) {
      AutoFix.instance.capture(e, st, source: 'chat.send', messaging: true);
      _toast('chat_send_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    await _run(() async {
      await widget.onSendText(text);
      _ctrl.clear();
    });
  }

  // ---- attachments ---------------------------------------------------

  Future<void> _sendBytes(Uint8List bytes, String type, String name, String? contentType) async {
    if (bytes.length > _maxBytes) {
      _toast('chat_file_too_big');
      return;
    }
    await _run(() => widget.onSendAttachment(bytes: bytes, type: type, fileName: name, contentType: contentType));
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _sendBytes(bytes, 'image', file.name, file.mimeType ?? 'image/jpeg');
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final f = result?.files.single;
    if (f == null || f.bytes == null) return;
    await _sendBytes(f.bytes!, 'file', f.name, _mimeFor(f.name));
  }

  static String? _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return const {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'heic': 'image/heic',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
    }[ext];
  }

  /// Sends the device's current position as a map link (browser asks
  /// for location permission the first time).
  Future<void> _sendMyLocation() async {
    setState(() => _busy = true);
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 20));
    } catch (_) {
      _toast('chat_location_denied');
    }
    try {
      if (pos != null) await widget.onSendText(ChatLocation.messageFor(pos.latitude, pos.longitude));
    } catch (_) {
      _toast('chat_send_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openAttachMenu() {
    final s = widget.strings;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_outlined, color: AppColors.accent),
              title: Text(s.t('chat_attach_photo')),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: AppColors.accent),
              title: Text(s.t('chat_attach_camera')),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.my_location, color: AppColors.accent),
              title: Text(s.t('chat_attach_location')),
              subtitle: Text(s.t('chat_attach_location_hint')),
              onTap: () {
                Navigator.of(ctx).pop();
                _sendMyLocation();
              },
            ),
            ListTile(
              leading: Icon(Icons.insert_drive_file_outlined, color: AppColors.accent),
              title: Text(s.t('chat_attach_file')),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---- voice notes ---------------------------------------------------

  Future<void> _startRecording() async {
    if (_busy || _recording) return;
    if (!kIsWeb) {
      // Native builds need a file path (path_provider) — not wired yet.
      _toast('chat_voice_unsupported');
      return;
    }
    final rec = AudioRecorder();
    try {
      if (!await rec.hasPermission()) {
        await rec.dispose();
        _toast('chat_mic_denied');
        return;
      }
      // Safari records AAC (m4a); fall back to Opus where AAC isn't
      // available.
      var enc = AudioEncoder.aacLc;
      if (!await rec.isEncoderSupported(enc)) enc = AudioEncoder.opus;
      // Mono voice with the browser's automatic gain, noise suppression
      // and echo cancellation — without these iPhone Safari records very
      // quietly.
      await rec.start(
        RecordConfig(
          encoder: enc,
          bitRate: 96000,
          numChannels: 1,
          autoGain: true,
          noiseSuppress: true,
          echoCancel: true,
        ),
        path: '',
      );
      _encoder = enc;
      _recStart = DateTime.now();
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _recStart != null) setState(() => _elapsed = DateTime.now().difference(_recStart!));
      });
      setState(() => _rec = rec);
    } catch (_) {
      _ticker?.cancel();
      _ticker = null;
      await _disposeRecorder(rec);
      if (mounted) setState(() => _rec = null);
      _toast('chat_mic_denied');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    final rec = _rec;
    if (rec == null) return;
    _ticker?.cancel();
    _ticker = null;
    final duration = _recStart == null ? Duration.zero : DateTime.now().difference(_recStart!);
    setState(() => _rec = null);
    if (!send) {
      try {
        await rec.cancel();
      } catch (_) {}
      await _disposeRecorder(rec);
      return;
    }
    if (duration.inMilliseconds < 700) {
      // Accidental tap — tell the user instead of silently dropping it.
      try {
        await rec.cancel();
      } catch (_) {}
      await _disposeRecorder(rec);
      _toast('chat_voice_too_short');
      return;
    }
    setState(() => _busy = true);
    Uint8List? bytes;
    try {
      // Safari sometimes never resolves stop(); don't hang the composer.
      final blobUrl = await rec.stop().timeout(const Duration(seconds: 10));
      if (blobUrl != null && blobUrl.isNotEmpty) {
        bytes = (await http.get(Uri.parse(blobUrl)).timeout(const Duration(seconds: 15))).bodyBytes;
      }
    } catch (_) {
      bytes = null;
    } finally {
      await _disposeRecorder(rec);
      if (mounted) setState(() => _busy = false);
    }
    if (bytes == null || bytes.length < 200) {
      _toast('chat_voice_failed');
      return;
    }
    if (bytes.length > _maxBytes) {
      _toast('chat_file_too_big');
      return;
    }
    await _sendVoice(_VoiceNote(bytes, _voiceFormat(bytes, _encoder), duration.inMilliseconds));
  }

  Future<void> _disposeRecorder(AudioRecorder rec) async {
    try {
      await rec.dispose(); // releases the microphone (iOS plays quietly while it is held)
    } catch (_) {}
  }

  /// Real container of the recorded bytes (browsers don't always give
  /// the format that was asked for), so the file is stored with the right
  /// type and plays on the other phone.
  static ({String name, String mime}) _voiceFormat(Uint8List b, AudioEncoder asked) {
    bool at(int off, List<int> sig) {
      if (b.length < off + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[off + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(4, const [0x66, 0x74, 0x79, 0x70])) return (name: 'voice.m4a', mime: 'audio/mp4'); // ....ftyp
    if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) return (name: 'voice.webm', mime: 'audio/webm'); // EBML
    if (at(0, const [0x4F, 0x67, 0x67, 0x53])) return (name: 'voice.ogg', mime: 'audio/ogg'); // OggS
    if (at(0, const [0x52, 0x49, 0x46, 0x46])) return (name: 'voice.wav', mime: 'audio/wav'); // RIFF
    return asked == AudioEncoder.aacLc
        ? (name: 'voice.m4a', mime: 'audio/mp4')
        : (name: 'voice.webm', mime: 'audio/webm');
  }

  /// Uploads a voice note; one quiet automatic retry, then a snackbar
  /// with "Retry" so the recording is never lost on a weak connection.
  Future<void> _sendVoice(_VoiceNote v) async {
    if (!mounted) return;
    setState(() => _busy = true);
    var ok = false;
    for (var attempt = 0; attempt < 2 && !ok; attempt++) {
      try {
        await widget.onSendAttachment(
          bytes: v.bytes,
          type: 'audio',
          fileName: v.format.name,
          contentType: v.format.mime,
          audioDurationMs: v.durationMs,
        );
        ok = true;
      } catch (_) {
        if (attempt == 0) await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.strings.t('chat_voice_failed_retry')),
        duration: const Duration(seconds: 12),
        action: SnackBarAction(label: widget.strings.t('chat_retry'), onPressed: () => _sendVoice(v)),
      ),
    );
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;

    if (_recording) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: s.t('common_cancel'),
              onPressed: () => _stopRecording(send: false),
              icon: Icon(Icons.delete_outline, color: AppColors.danger),
            ),
            Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.danger, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(_fmt(_elapsed), style: AppFonts.mono(size: 15, color: AppColors.text)),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t('chat_recording'), style: TextStyle(color: AppColors.textSoft))),
            IconButton.filled(
              onPressed: () => _stopRecording(send: true),
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: s.t('chat_attach_file'),
            onPressed: _busy ? null : _openAttachMenu,
            icon: Icon(Icons.attach_file, color: AppColors.textSoft),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: s.t('conversation_input_hint'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendText(),
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(width: 48, height: 48, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_hasText)
            IconButton.filled(onPressed: _sendText, icon: const Icon(Icons.send))
          else
            IconButton.filled(
              tooltip: s.t('chat_voice_message'),
              onPressed: _startRecording,
              icon: const Icon(Icons.mic),
            ),
        ],
      ),
    );
  }
}

class _VoiceNote {
  final Uint8List bytes;
  final ({String name, String mime}) format;
  final int durationMs;
  const _VoiceNote(this.bytes, this.format, this.durationMs);
}

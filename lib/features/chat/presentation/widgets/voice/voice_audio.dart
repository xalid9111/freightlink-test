import 'voice_audio_stub.dart' if (dart.library.js_interop) 'voice_audio_web.dart' as impl;

/// Minimal voice-note player. On the web it drives a plain HTML <audio>
/// element and calls play() synchronously inside the tap — the only way
/// iPhone Safari / PWA reliably starts playback. Elsewhere it wraps
/// audioplayers.
abstract class VoiceAudio {
  factory VoiceAudio() => impl.createVoiceAudio();

  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<void> get completed;
  Stream<void> get failed;

  /// Must be called directly from the tap handler (no await before it).
  void play(String url);
  void pause();
  void dispose();
}

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'voice_audio.dart';

VoiceAudio createVoiceAudio() => _PlayersVoiceAudio();

class _PlayersVoiceAudio implements VoiceAudio {
  final AudioPlayer _p = AudioPlayer();
  final _failed = StreamController<void>.broadcast();

  @override
  Stream<bool> get playing => _p.onPlayerStateChanged.map((s) => s == PlayerState.playing);
  @override
  Stream<Duration> get position => _p.onPositionChanged;
  @override
  Stream<Duration> get duration => _p.onDurationChanged;
  @override
  Stream<void> get completed => _p.onPlayerComplete;
  @override
  Stream<void> get failed => _failed.stream;

  @override
  void play(String url) {
    _p.play(UrlSource(url), volume: 1.0).catchError((Object _) => _failed.add(null));
  }

  @override
  void pause() => _p.pause();

  @override
  void dispose() {
    _failed.close();
    _p.dispose();
  }
}

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'voice_audio.dart';

VoiceAudio createVoiceAudio() => _WebVoiceAudio();

class _WebVoiceAudio implements VoiceAudio {
  web.HTMLAudioElement? _el;
  String? _url;
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _failed = StreamController<void>.broadcast();
  bool _disposed = false;

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<void> get failed => _failed.stream;

  static Duration _secs(num s) => Duration(milliseconds: (s * 1000).round());

  void _emitDuration(web.HTMLAudioElement el) {
    final d = el.duration;
    if (d.isFinite && d > 0) _duration.add(_secs(d));
  }

  void _on(web.HTMLAudioElement el, String type, void Function() f) {
    el.addEventListener(
      type,
      ((web.Event _) {
        if (!_disposed && identical(el, _el)) f();
      }).toJS,
    );
  }

  web.HTMLAudioElement _ensure(String url) {
    final current = _el;
    if (current != null && _url == url) return current;
    current?.pause();
    final el = web.HTMLAudioElement();
    el.setAttribute('playsinline', '');
    el.preload = 'auto';
    el.src = url;
    _el = el;
    _url = url;
    _on(el, 'play', () => _playing.add(true));
    _on(el, 'pause', () => _playing.add(false));
    _on(el, 'timeupdate', () => _position.add(_secs(el.currentTime)));
    _on(el, 'loadedmetadata', () => _emitDuration(el));
    _on(el, 'durationchange', () => _emitDuration(el));
    _on(el, 'ended', () {
      _playing.add(false);
      _completed.add(null);
    });
    _on(el, 'error', () {
      _playing.add(false);
      _failed.add(null);
    });
    return el;
  }

  @override
  void play(String url) {
    if (_disposed) return;
    final el = _ensure(url);
    el.volume = 1.0;
    el.muted = false;
    // Called synchronously from the tap, so iOS treats it as a user gesture.
    el.play().toDart.then((_) {}, onError: (Object _) {
      if (!_disposed) {
        _playing.add(false);
        _failed.add(null);
      }
    });
  }

  @override
  void pause() => _el?.pause();

  @override
  void dispose() {
    _disposed = true;
    final el = _el;
    if (el != null) {
      el.pause();
      el.removeAttribute('src');
      el.load();
    }
    _el = null;
    for (final c in [_playing, _position, _duration, _completed, _failed]) {
      c.close();
    }
  }
}

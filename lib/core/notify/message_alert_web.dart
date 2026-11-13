import 'dart:js_interop';

@JS('flMsgAlert.play')
external void _play(JSString kind);

@JS('flMsgAlert.notify')
external void _notify(JSString title, JSString body, JSString tag);

void playSound(String kind) {
  try {
    _play(kind.toJS);
  } catch (_) {}
}

void showNotification(String title, String body, String tag) {
  try {
    _notify(title.toJS, body.toJS, tag.toJS);
  } catch (_) {}
}

@JS('flMsgAlert.test')
external JSString? _test();

/// "Səsi yoxla": plays the message sound, asks for notifications; returns
/// 'granted' | 'denied' | 'default' | 'unsupported'.
String testSound() {
  try {
    return _test()?.toDart ?? 'unsupported';
  } catch (_) {
    return 'unsupported';
  }
}

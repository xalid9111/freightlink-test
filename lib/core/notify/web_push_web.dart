import 'dart:js_interop';

@JS('flPush.state')
external JSString? _state();

@JS('flPush.enable')
external JSPromise<JSString> _enable(JSString key, JSString keyUrl);

@JS('flPush.current')
external JSPromise<JSString> _current();

@JS('flPush.disable')
external JSPromise<JSString> _disable();

@JS('flPush.clear')
external JSPromise<JSNumber> _clear(JSString tag);

@JS('flPush.badge')
external void _badge(JSNumber n);

/// Closes the notifications of one chat ('chat-<id>') or of all chats ('chat-').
Future<void> pushClear(String tag) async {
  try {
    await _clear(tag.toJS).toDart;
  } catch (_) {}
}

/// The number on the app icon (0 = none), where supported.
void pushBadge(int n) {
  try {
    _badge(n.toJS);
  } catch (_) {}
}

String pushState() {
  try {
    return _state()?.toDart ?? 'unsupported';
  } catch (_) {
    return 'unsupported';
  }
}

/// Asks for the permission at once (must run inside the tap), then subscribes.
Future<String> pushEnable(String key, String keyUrl) async {
  try {
    final p = _enable(key.toJS, keyUrl.toJS);
    return (await p.toDart).toDart;
  } catch (e) {
    return '{"status":"error"}';
  }
}

Future<String> pushCurrent() async {
  try {
    return (await _current().toDart).toDart;
  } catch (_) {
    return '';
  }
}

Future<String> pushDisable() async {
  try {
    return (await _disable().toDart).toDart;
  } catch (_) {
    return '';
  }
}

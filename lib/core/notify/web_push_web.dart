import 'dart:js_interop';

@JS('flPush.state')
external JSString? _state();

@JS('flPush.enable')
external JSPromise<JSString> _enable(JSString key, JSString keyUrl);

@JS('flPush.current')
external JSPromise<JSString> _current();

@JS('flPush.disable')
external JSPromise<JSString> _disable();

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

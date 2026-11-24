import 'dart:js_interop';

@JS('flStatusBarRoom')
external JSNumber _room();

/// The see-through status bar test (index.html): the room above the app in
/// logical pixels, or 0 when it is not on.
double statusBarRoom() {
  try {
    return _room().toDartDouble;
  } catch (_) {
    return 0;
  }
}

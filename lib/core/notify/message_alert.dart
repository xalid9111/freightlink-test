import 'message_alert_stub.dart' if (dart.library.js_interop) 'message_alert_web.dart' as impl;

/// Short sound for a newly received message (web/sounds/message.wav).
void playMessageSound() => impl.playSound('message');

/// Short sound for a new load in the marketplace (web/sounds/cargo.wav).
void playCargoSound() => impl.playSound('cargo');

/// Browser notification — shown only while the app is in the background
/// and the user allowed notifications.
void showMessageNotification(String title, String body) => impl.showNotification(title, body, 'fl-msg');

void showCargoNotification(String title, String body) => impl.showNotification(title, body, 'fl-cargo');

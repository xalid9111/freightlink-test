/// Provider-agnostic push notification contract (Firebase Cloud
/// Messaging is the concrete implementation, wired in Phase 12).
abstract class NotificationService {
  Future<void> initialize();
  Future<String?> getDeviceToken();
  Stream<Map<String, dynamic>> onMessage();
}

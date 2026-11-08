/// Phones / tests: the texts come from the app bundle only.
Future<String?> fetchFreshText(String assetPath) async => null;

/// Phones / tests: no per-version copy of the texts.
String? readCachedText(String key, String build) => null;
void storeCachedText(String key, String build, String text) {}

String pushState() => 'unsupported';

Future<String> pushEnable(String key, String keyUrl) async => '{"status":"unsupported"}';

Future<String> pushCurrent() async => '';

Future<String> pushDisable() async => '';

Future<void> pushClear(String tag) async {}

void pushBadge(int n) {}

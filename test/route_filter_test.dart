// "Haradan → Haraya" filter: key format used for saved routes.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/providers/route_filter.dart';

void main() {
  test('empty filter is inactive and has the wildcard key', () {
    const f = RouteFilter();
    expect(f.isActive, isFalse);
    expect(f.key, '*>*');
  });

  test('key round-trips through fromKey', () {
    for (final f in const [RouteFilter(from: 'AZ', to: 'RU'), RouteFilter(from: 'AZ'), RouteFilter(to: 'TR')]) {
      final back = RouteFilter.fromKey(f.key)!;
      expect(back.from, f.from);
      expect(back.to, f.to);
      expect(back.isActive, isTrue);
    }
  });

  test('malformed keys are rejected', () {
    expect(RouteFilter.fromKey('AZ'), isNull);
    expect(RouteFilter.fromKey('AZ>RU>TR'), isNull);
  });
}

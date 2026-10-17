// "Reklam ver": service owners get service templates, others load ads.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/ads/presentation/ad_kind_logic.dart';

void main() {
  test('service owner: service ads first, load ads still available', () {
    expect(adKindsFor(hasService: true), [AdKind.service, AdKind.cargo]);
  });

  test('carrier / company / cargo owner without a service: load ads only (as before)', () {
    expect(adKindsFor(hasService: false), [AdKind.cargo]);
  });

  test('service template opens the service ad editor for the own service', () {
    expect(adCreateRoute(AdKind.service, 't1', serviceId: 's1'), '/ad-create?service=s1&tpl=t1');
  });

  test('load template opens the normal editor; never a service ad without a service', () {
    expect(adCreateRoute(AdKind.cargo, 't1', serviceId: 's1'), '/ad-create?tpl=t1');
    expect(adCreateRoute(AdKind.service, 't1'), '/ad-create?tpl=t1');
  });
}

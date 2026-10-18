import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/admin/presentation/admin_autofix_page.dart';

void main() {
  Map<String, dynamic> row(String msg, String route) => {
        'kind': 'runtime',
        'code': 'minified:i1',
        'message': msg,
        'file': null,
        'line': null,
        'route': route,
        'count': 2,
        'users': 1,
        'auto_fixed': 0,
        'stack': 'at x',
        'breadcrumbs': 'tap',
      };

  test('"Hamısını kopyala" copies every problem in the list, numbered', () {
    final text = autofixReportAll([row('Bad state A', '/services'), row('Bad state B', '/market')]);
    expect(text.startsWith('AutoFix — 2 problem'), isTrue);
    expect(text.contains('1 / 2'), isTrue);
    expect(text.contains('2 / 2'), isTrue);
    expect(text.contains('Mesaj: Bad state A'), isTrue);
    expect(text.contains('Mesaj: Bad state B'), isTrue);
    expect(text.contains('Səhifə: /market'), isTrue);
    expect(text.contains('Stack:\nat x'), isTrue);
  });

  test('one problem copies the same text as its own "Kopyala"', () {
    final r = row('Bad state A', '/services');
    expect(autofixReportAll([r]).contains(autofixReport(r)), isTrue);
  });
}

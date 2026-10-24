// Owner, 24.10.2026 ("sayt gec yüklənir"): smaller start-up. Guards that
// the slim fonts stay in use and the start-up files load in parallel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('slim fonts (renamed as the OFL asks), no unused bold italic', () {
    final pub = _read('pubspec.yaml');
    for (final s in ['Regular', 'Bold', 'Italic']) {
      expect(pub, contains('assets/fonts/FreightLinkSans-$s.ttf'));
      final f = File('assets/fonts/FreightLinkSans-$s.ttf');
      expect(f.lengthSync(), lessThan(200 * 1024), reason: s);
      // OFL: a changed font must not carry the reserved name "Liberation".
      expect(String.fromCharCodes(f.readAsBytesSync()).contains('Liberation Sans'), isFalse, reason: s);
    }
    expect(pub.contains('LiberationSans-'), isFalse);
    expect(pub.contains('BoldItalic'), isFalse);
    expect(_read('assets/fonts/OFL.txt'), contains('FreightLinkSans-*.ttf are Modified Versions of Liberation Sans'));
  });

  test('the app file starts downloading at once; languages load in parallel', () {
    expect(_read('web/index.html'), contains('<link rel="preload" href="main.dart.js" as="script">'));
    expect(_read('lib/core/localization/localization_service.dart'), contains('await Future.wait('));
  });
}

// AutoFix 08.11.2026: "AbortError: Aborted by failure" (the browser's image
// decoder failing on an animated picture) and "Unable to load asset" (a file
// that did not arrive) were shown as anonymous code errors.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/autofix/autofix.dart';
import 'package:freightlink/core/autofix/autofix_logic.dart';

void main() {
  test('a picture that failed: its own code and WHICH picture', () {
    final details = FlutterErrorDetails(
      exception: 'AbortError: Aborted by failure.',
      library: 'image resource service',
      context: ErrorDescription('resolving an image frame'),
      informationCollector: () => [DiagnosticsProperty<ImageProvider>('Image provider', const NetworkImage('https://x.supabase.co/storage/v1/object/public/avatars/a.gif'))],
    );
    final detail = imageErrorDetail(details)!;
    expect(detail, contains('resolving an image frame'));
    expect(detail, contains('avatars/a.gif'));
    final info = classifyError('JSObject', 'AbortError: Aborted by failure.\n$detail');
    expect(info.code, 'image');
    expect(info.message, contains('avatars/a.gif'));
  });

  test('other Flutter errors get no picture detail', () {
    expect(imageErrorDetail(FlutterErrorDetails(exception: StateError('x'), library: 'widgets library')), isNull);
  });

  test('an app file that did not arrive is a network problem, not a code error', () {
    final info = classifyError('minified:yo', 'Unable to load asset: "assets/images/promo/promo_vip.png".');
    expect(info.kind, AutoFixKind.network);
    expect(classifyError('minified:yf', 'Unable to load asset: "AssetManifest.bin.json".').kind, AutoFixKind.network);
  });

  test('avatars: a picture that cannot be shown keeps the initials (handled, not reported)', () {
    final a = File('lib/core/widgets/user_avatar.dart').readAsStringSync();
    expect(a, contains('onForegroundImageError: hasImage && !framed ? (_, __) {} : null,'));
    expect(a, contains('errorBuilder: (_, __, ___) => const SizedBox.shrink(),'), reason: 'framed avatars were already handled');
    expect(File('lib/features/admin/presentation/admin_pages.dart').readAsStringSync(), contains('onBackgroundImageError:'));
    expect(File('lib/core/autofix/autofix.dart').readAsStringSync(),
        contains("capture(details.exception, details.stack, source: 'flutter', detail: imageErrorDetail(details));"));
  });
}

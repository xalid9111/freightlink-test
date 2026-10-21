// GitHub workflows: Pages deploy only on push to main; Edge Functions are
// deployed only by hand, with the token from a secret.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pages deploy still runs on push to main only', () {
    final d = File('.github/workflows/deploy.yml').readAsStringSync();
    expect(RegExp(r'on:\s*\n\s*push:\s*\n\s*branches:\s*\[main\]').hasMatch(d), isTrue);
  });

  test('Edge Functions workflow: manual only, no Pages, token only from the secret', () {
    final f = File('.github/workflows/supabase-functions.yml').readAsStringSync();
    expect(f.contains('workflow_dispatch:'), isTrue);
    expect(RegExp(r'^\s*(push|pull_request|schedule):', multiLine: true).hasMatch(f), isFalse);
    expect(f.contains('pages'), isFalse);
    expect(f.contains(r'${{ secrets.SUPABASE_ACCESS_TOKEN }}'), isTrue);
    expect(RegExp(r'sbp_[A-Za-z0-9]{10,}').hasMatch(f), isFalse);
    expect(f.contains('supabase functions deploy "\${{ inputs.function }}" --project-ref jqdqtfmxnqezlsetelpi'), isTrue);
  });
}

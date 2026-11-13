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
    // Newer Supabase CLIs ask before deploying; a GitHub run cannot answer (05.11.2026).
    expect(RegExp(r'functions deploy .* --yes\s*$', multiLine: true).hasMatch(f), isTrue);
  });

  test('OSM truck parks: monthly + by hand, no Pages, no push, token only from the secret, never AZ', () {
    final f = File('.github/workflows/osm-truck-parks.yml').readAsStringSync();
    expect(f.contains('workflow_dispatch:'), isTrue);
    expect(RegExp(r"schedule:\s*\n\s*- cron: '23 2 5 \* \*'").hasMatch(f), isTrue, reason: 'once a month');
    expect(RegExp(r'^\s*(push|pull_request):', multiLine: true).hasMatch(f), isFalse);
    expect(RegExp(r'pages|deploy-pages|upload-pages', caseSensitive: false).hasMatch(f), isFalse);
    expect(f.contains(r'${{ secrets.SUPABASE_ACCESS_TOKEN }}'), isTrue);
    expect(RegExp(r'sbp_[A-Za-z0-9]{10,}').hasMatch(f), isFalse);
    expect(f.contains('max-parallel: 2'), isTrue, reason: 'polite to Geofabrik');
    expect(f.toLowerCase().contains('overpass-api'), isFalse, reason: 'no public Overpass in production');
    final py = File('scripts/osm_truck_parks/import_parks.py').readAsStringSync();
    expect(py.contains("GEOFABRIK = 'https://download.geofabrik.de'"), isTrue);
    expect(py.contains('asia/azerbaijan-latest'), isFalse);
    expect(py.toLowerCase().contains('overpass-api'), isFalse);
    // Only these workflows exist (CLAUDE.md §1): one Pages deploy, the gate, two manual / scheduled data jobs.
    final names = Directory('.github/workflows').listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(names, {'deploy.yml', 'autofix-ci.yml', 'supabase-functions.yml', 'osm-truck-parks.yml'});
  });

  test('the site lives at the root of tirlink.app: base href "/" (owner, 13.11.2026)', () {
    final d = File('.github/workflows/deploy.yml').readAsStringSync();
    expect(d.contains('--base-href "/"'), isTrue, reason: 'a sub-folder base href opens tirlink.app on a black screen');
    expect(d.contains('github.event.repository.name'), isFalse);
    expect(File('web/index.html').readAsStringSync().contains(r'<base href="$FLUTTER_BASE_HREF">'), isTrue);
  });
}

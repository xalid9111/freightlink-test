import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Search engines (owner, 22.11.2026): the plain HTML pages Google / Bing /
/// AI search can read without running the app — the about page, the
/// canonical addresses, the sitemap and the JSON-LD blocks.
String _src(String p) => File(p).readAsStringSync();

List<Map<String, dynamic>> _jsonLd(String html) => [
      for (final m in RegExp(r'<script type="application/ld\+json">([\s\S]*?)</script>').allMatches(html))
        jsonDecode(m.group(1)!) as Map<String, dynamic>,
    ];

void main() {
  test('the about page exists, has its own canonical and a valid WebPage JSON-LD', () {
    final f = File('web/haqqimizda/index.html');
    expect(f.existsSync(), isTrue, reason: 'served at https://tirlink.app/haqqimizda/');
    final html = f.readAsStringSync();
    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('<html lang="az">'));
    expect(html, contains('<link rel="canonical" href="https://tirlink.app/haqqimizda/">'));
    expect(html, contains('<title>TırLink'));
    expect(html, contains('<meta name="description"'));
    final ld = _jsonLd(html);
    expect(ld, hasLength(1));
    expect(ld.single['@context'], 'https://schema.org');
    expect(ld.single['@type'], 'WebPage');
    expect(ld.single['url'], 'https://tirlink.app/haqqimizda/');
    final pub = ld.single['publisher'] as Map<String, dynamic>;
    expect(pub['@type'], 'Organization');
    expect(pub['url'], 'https://tirlink.app/');
    // Every picture / logo it names is a real file of the site.
    for (final m in RegExp(r'(?:src|href|content)="(?:https://tirlink\.app)?(/[^"#?]+\.(?:png|ico))"').allMatches(html)) {
      expect(File('web${m.group(1)}').existsSync(), isTrue, reason: m.group(1));
    }
    expect(File('web/${(pub['logo'] as String).substring('https://tirlink.app/'.length)}').existsSync(), isTrue);
    // A link back to the app, no scripts of its own, no unproven claims.
    expect(html, contains('href="https://tirlink.app/"'));
    expect(RegExp(r'<script(?! type="application/ld\+json")').hasMatch(html), isFalse);
    final lower = html.toLowerCase();
    for (final claim in ['ən böyük', 'ən yaxşı', '№1', 'nömrə 1', 'largest', 'best', 'süni intellekt']) {
      expect(lower.contains(claim), isFalse, reason: 'no unproven claim: $claim');
    }
    expect(RegExp(r'\bai\b').hasMatch(lower), isFalse, reason: 'no AI claim');
    expect(html, isNot(contains('FreightLink')));
  });

  test('the home page: canonical, Open Graph, a noscript text and the Organization JSON-LD', () {
    final html = _src('web/index.html');
    final head = html.substring(0, html.indexOf('</head>'));
    expect(head, contains('<link rel="canonical" href="https://tirlink.app/">'));
    expect(head, contains('<meta property="og:url" content="https://tirlink.app/">'));
    expect(head, contains('<meta property="og:image" content="https://tirlink.app/icons/tirlink-logo-org-512.png">'));
    final ld = _jsonLd(head);
    expect(ld.map((e) => e['@type']), ['Organization']);
    final ns = RegExp(r'<noscript>([\s\S]*?)</noscript>').firstMatch(html);
    expect(ns, isNotNull);
    expect(ns!.group(1), contains('href="/haqqimizda/"'));
    expect(html.indexOf('<noscript>'), greaterThan(html.indexOf('<body>')));
  });

  test('the sitemap: valid XML, only the three public addresses, each one a real file', () {
    final xml = _src('web/sitemap.xml');
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'));
    expect('<url>'.allMatches(xml).length, '</url>'.allMatches(xml).length);
    final locs = [for (final m in RegExp(r'<loc>([^<]+)</loc>').allMatches(xml)) m.group(1)!];
    expect(locs, ['https://tirlink.app/', 'https://tirlink.app/haqqimizda/', 'https://tirlink.app/privacy.html']);
    for (final l in locs) {
      expect(l, isNot(contains('#')), reason: 'no app (#) routes');
      final path = l.substring('https://tirlink.app'.length);
      final file = path.endsWith('/') ? 'web${path}index.html' : 'web$path';
      expect(File(file).existsSync(), isTrue, reason: '$l → $file');
    }
    expect(_src('web/robots.txt'), contains('Sitemap: https://tirlink.app/sitemap.xml'));
  });

  test('the brand on the plain pages: TırLink, no FreightLink, no "AI-powered"', () {
    final privacy = _src('web/privacy.html');
    expect(privacy, isNot(contains('FreightLink')));
    expect(privacy, contains('<title>TırLink'));
    final manifest = jsonDecode(_src('web/manifest.json')) as Map<String, dynamic>;
    expect('${manifest['description']}'.toLowerCase(), isNot(contains('ai-powered')));
  });
}

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

/// The about page in the app's six languages (owner, 24.11.2026): AZ keeps
/// /haqqimizda/; hreflang = the code in the page's <html lang>.
class _About {
  final String hreflang, path;
  final List<String> claims; // unproven claims in that language
  const _About(this.hreflang, this.path, this.claims);
  String get file => 'web${path}index.html';
}

const _about = [
  _About('az', '/haqqimizda/', ['ən böyük', 'ən yaxşı', 'lider', 'süni intellekt']),
  _About('tr', '/tr/hakkimizda/', ['en büyük', 'en iyi', 'lider', 'yapay zeka']),
  _About('en', '/en/about/', ['largest', 'best', 'leading', 'artificial intelligence']),
  _About('ru', '/ru/o-nas/', ['крупнейш', 'лучш', 'лидер', 'искусственн']),
  _About('ka', '/ka/about/', ['უდიდეს', 'საუკეთესო', 'ლიდერ', 'ხელოვნური ინტელექტ']),
  _About('zh-Hans', '/zh/about/', ['最大', '最好', '领先', '人工智能']),
];

void main() {
  test('every language page: its own canonical, the same hreflang set, a WebPage JSON-LD, its own text', () {
    final titles = <String>{}, descs = <String>{};
    Set<String>? alternatesOfFirst;
    for (final a in _about) {
      final f = File(a.file);
      expect(f.existsSync(), isTrue, reason: 'served at https://tirlink.app${a.path}');
      final html = f.readAsStringSync();
      final url = 'https://tirlink.app${a.path}';
      expect(html, startsWith('<!doctype html>'), reason: a.path);
      expect(html, contains('<html lang="${a.hreflang}">'), reason: a.path);
      expect(html, contains('<link rel="canonical" href="$url">'), reason: a.path);
      expect(html.contains('name="keywords"'), isFalse, reason: 'no meta keywords');
      expect(html, isNot(contains('FreightLink')));
      expect(titles.add(RegExp(r'<title>([^<]+)</title>').firstMatch(html)!.group(1)!), isTrue, reason: 'unique title ${a.path}');
      expect(descs.add(RegExp(r'<meta name="description" content="([^"]+)">').firstMatch(html)!.group(1)!), isTrue,
          reason: 'unique description ${a.path}');
      // Reciprocal hreflang: every page lists all six + x-default, the same set.
      final alts = {
        for (final m in RegExp(r'<link rel="alternate" hreflang="([^"]+)" href="([^"]+)">').allMatches(html))
          '${m.group(1)} ${m.group(2)}'
      };
      expect(alts, contains('${a.hreflang} $url'), reason: 'lists itself');
      expect(alts, contains('x-default https://tirlink.app/en/about/'));
      expect(alts.length, _about.length + 1);
      alternatesOfFirst ??= alts;
      expect(alts, alternatesOfFirst, reason: 'the same set on every page ${a.path}');
      // Plain links a person can tap to every other language (no redirect).
      for (final o in _about.where((o) => o != a)) {
        expect(html, contains('<a href="${o.path}" hreflang="${o.hreflang}"'), reason: '${a.path} → ${o.path}');
      }
      expect(html.contains('location.replace') || html.contains('http-equiv="refresh"'), isFalse, reason: 'no redirect');
      final ld = _jsonLd(html);
      expect(ld, hasLength(1));
      expect(ld.single['@type'], 'WebPage');
      expect(ld.single['url'], url);
      expect(ld.single['inLanguage'], a.hreflang);
      final pub = ld.single['publisher'] as Map<String, dynamic>;
      expect(pub['url'], 'https://tirlink.app/');
      expect(pub['logo'], 'https://tirlink.app/icons/tirlink-logo-org-512.png');
      final lower = html.toLowerCase();
      for (final c in a.claims) {
        expect(lower.contains(c), isFalse, reason: 'no unproven claim on ${a.path}: $c');
      }
      expect(RegExp(r'\bai\b').hasMatch(lower), isFalse, reason: 'no AI claim ${a.path}');
      expect(RegExp(r'<li>').allMatches(html).length, 10, reason: 'the full text: 7 sections + 3 uses ${a.path}');
    }
  });

  test('the sitemap carries the same hreflang set for every language page', () {
    final xml = _src('web/sitemap.xml');
    for (final a in _about) {
      final block = RegExp('<url>\\s*<loc>https://tirlink.app${RegExp.escape(a.path)}</loc>([\\s\\S]*?)</url>').firstMatch(xml);
      expect(block, isNotNull, reason: a.path);
      for (final o in _about) {
        expect(block!.group(1), contains('hreflang="${o.hreflang}" href="https://tirlink.app${o.path}"'), reason: '${a.path} → ${o.path}');
      }
      expect(block!.group(1), contains('hreflang="x-default" href="https://tirlink.app/en/about/"'));
    }
  });

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

  test('the sitemap: valid XML, only the public addresses, each one a real file', () {
    final xml = _src('web/sitemap.xml');
    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(xml, contains('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"'));
    expect(xml, contains('xmlns:xhtml="http://www.w3.org/1999/xhtml"'));
    expect('<url>'.allMatches(xml).length, '</url>'.allMatches(xml).length);
    final locs = [for (final m in RegExp(r'<loc>([^<]+)</loc>').allMatches(xml)) m.group(1)!];
    expect(locs, [
      'https://tirlink.app/',
      for (final a in _about) 'https://tirlink.app${a.path}',
      'https://tirlink.app/privacy.html',
    ]);
    for (final l in locs) {
      expect(l, isNot(contains('#')), reason: 'no app (#) routes');
      final path = l.substring('https://tirlink.app'.length);
      final file = path.endsWith('/') ? 'web${path}index.html' : 'web$path';
      expect(File(file).existsSync(), isTrue, reason: '$l → $file');
    }
    expect(_src('web/robots.txt'), contains('Sitemap: https://tirlink.app/sitemap.xml'));
    // Sitemap 0.9 order inside <url>: loc, then lastmod (ISO date), then the
    // xhtml:link alternates; no changefreq / priority (owner, 24.11.2026).
    for (final m in RegExp(r'<url>([\s\S]*?)</url>').allMatches(xml)) {
      final b = m.group(1)!.trim();
      expect(b, matches(RegExp(r'^<loc>[^<]+</loc>\s*<lastmod>\d{4}-\d{2}-\d{2}</lastmod>(\s*<xhtml:link [^>]+/>)*$')),
          reason: b.split('\n').first);
    }
    expect(xml.contains('<changefreq>') || xml.contains('<priority>'), isFalse);
  });

  test('the brand on the plain pages: TırLink, no FreightLink, no "AI-powered"', () {
    final privacy = _src('web/privacy.html');
    expect(privacy, isNot(contains('FreightLink')));
    expect(privacy, contains('<title>TırLink'));
    final manifest = jsonDecode(_src('web/manifest.json')) as Map<String, dynamic>;
    expect('${manifest['description']}'.toLowerCase(), isNot(contains('ai-powered')));
  });
}

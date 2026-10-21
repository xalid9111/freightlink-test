// Regression guards for FreightLink's critical paths (see CLAUDE.md).
//
// These are fast, source-level checks: they fail when a change silently
// removes a route, a bottom-bar tab, an admin section, a translation, a
// web script — or when a migration starts deleting data. They do NOT
// replace a manual check on iPhone Safari/PWA (see CLAUDE.md checklist).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/notify/notify_settings.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('Routes (Loads, Services, Add load, Messages, Profile, Ads, Admin)', () {
    final router = _read('lib/core/router/app_router.dart');
    const required = [
      "'/cargo'",
      "'/cargo/create'",
      "'/load/:id'",
      "'/my-cargo'",
      "'/services'",
      "'/service/:id'",
      "'/service-join'",
      "'/messages'",
      "'with/:uid'",
      "'group/:gid'",
      "'/profile'",
      "'/settings'",
      "'/change-password'",
      "'/user/:id'",
      "'/user/:id/catalog'",
      "'/ads'",
      "'/ad-create'",
      "'/ad-order/:id'",
      "'/admin'",
      "'/admin/:section'",
    ];
    for (final r in required) {
      test('route $r exists', () => expect(router.contains(r), isTrue, reason: '$r was removed from app_router.dart'));
    }
    test('unknown routes have an error screen (no dead end)', () {
      expect(router.contains('errorBuilder:'), isTrue);
    });
  });

  group('Bottom bar (owner-approved layout)', () {
    final shell = _read('lib/core/router/main_shell.dart');
    test('tabs: Loads(0) · Services(5) · TIR Bazarı(6, centre) · Messages(3) · Profile(4)', () {
      final order = ['_NavItem(0,', '_NavItem(5,', '_NavItem(6,', '_NavItem(3,', '_NavItem(4,'];
      var at = -1;
      for (final b in order) {
        final i = shell.indexOf(b);
        expect(i > at, isTrue, reason: '$b missing or out of order');
        at = i;
      }
    });
    test('Search(1) and Shipments(2) stay out of the bar (owner decision)', () {
      expect(shell.contains('_NavItem(1,'), isFalse);
      expect(shell.contains('_NavItem(2,'), isFalse);
    });
    test('"Yük əlavə et" (+) on the Loads page under the map opens "add load"', () {
      final loads = _read('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
      expect(loads.contains("_AddLoadButton(label: strings.t('nav_add_cargo'), onTap: () => context.pushOnce('/cargo/create'))"), isTrue);
    });
    test('TIR Bazarı is a separate part, loaded only when opened', () {
      final router = _read('lib/core/router/app_router.dart');
      expect(router.contains("market_module.dart' deferred as market;"), isTrue);
      expect(router.contains('market.loadLibrary'), isTrue);
    });
    test('narrow screens / iPhone: labels shrink, safe area respected', () {
      expect(shell.contains('FittedBox'), isTrue);
      expect(shell.contains('SafeArea('), isTrue);
    });
    test('tab switch keeps go_router branch navigation', () {
      expect(shell.contains('goBranch('), isTrue);
    });
  });

  group('Admin panel sections', () {
    final admin = _read('lib/features/admin/presentation/admin_shell.dart');
    for (final key in ['cargo', 'users', 'ads', 'ad_templates', 'service_templates', 'services', 'autofix', 'audit']) {
      test('section "$key" is listed and routed', () {
        expect(admin.contains("AdminSection('$key'"), isTrue);
        expect(admin.contains("case '$key':"), isTrue);
      });
    }
  });

  group('Translations for critical screens (all 6 languages)', () {
    const keys = [
      'nav_home', 'nav_services', 'nav_messages', 'nav_profile', 'nav_add_cargo',
      'settings_title', 'pf_my_loads', 'pf_sign_out', 'detail_message_button',
      'chat_send_failed', 'chat_delete_server_missing', 'adv_create_service',
      'adv_own_image_add', 'notif_new_message', 'autofix_route_missing',
    ];
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      test('$lang has the critical keys', () {
        final json = _read('assets/i18n/$lang.json');
        for (final k in keys) {
          expect(json.contains('"$k"'), isTrue, reason: '$lang.json misses $k');
        }
      });
    }
  });

  group('Web / PWA files', () {
    final index = _read('web/index.html');
    test('index.html loads the helper scripts before Flutter', () {
      final alert = index.indexOf('src="msg_alert.js"');
      final autofix = index.indexOf('src="autofix.js"');
      final boot = index.indexOf('src="flutter_bootstrap.js"');
      expect(alert, greaterThan(0));
      expect(autofix, greaterThan(0));
      expect(boot, greaterThan(alert));
      expect(boot, greaterThan(autofix));
    });
    test('sound files exist', () {
      expect(File('web/sounds/message.wav').existsSync(), isTrue);
      expect(File('web/sounds/cargo.wav').existsSync(), isTrue);
    });
  });

  group('Ads: client font is accepted by the server (the invalid_font bug)', () {
    test('the newest _ad_v2_creative_for allows every font the app sends', () {
      final files = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      String? latest;
      for (final f in files) {
        final s = f.readAsStringSync();
        if (s.contains('function public._ad_v2_creative_for(')) latest = s;
      }
      expect(latest, isNotNull);
      final models = _read('lib/models/ad_models.dart');
      final m = RegExp(r"static const fonts = \[([^\]]*)\]").firstMatch(models);
      expect(m, isNotNull);
      for (final font in RegExp(r"'([^']+)'").allMatches(m!.group(1)!).map((x) => x.group(1)!)) {
        expect(latest!.contains("'$font'"), isTrue, reason: 'server rejects font $font');
      }
    });
  });

  group('Service ads: own picture, order, service templates', () {
    final screen = _read('lib/features/ads/presentation/ad_create_screen.dart');
    test('own picture failures are explained, never swallowed', () {
      final start = screen.indexOf('Future<void> _addOwnImage(');
      final end = screen.indexOf('Widget _orderingOffNote(');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = screen.substring(start, end);
      expect(body.contains('catch (_)'), isFalse);
      expect(body.contains('ownImageErrorKey('), isTrue);
      expect(body.contains("AutoFix.instance.capture(e, st, source: 'ads.own_image')"), isTrue);
    });
    test('service ad uses service templates and offers the own picture', () {
      expect(screen.contains('serviceAdTemplatesProvider : adTemplatesProvider'), isTrue);
      expect(screen.contains('_ownImageButton(s)'), isTrue);
      expect(screen.contains('repo.createServiceOrder('), isTrue);
    });
    test('admin "Servis şablonları" shows only service backgrounds, new ones for services', () {
      final panel = _read('lib/features/admin/presentation/admin_ad_templates.dart');
      expect(panel.contains('standard.where((t) => t.forService)'), isTrue);
      expect(panel.contains("defaultAudience: audience ?? 'cargo'"), isTrue);
      expect(panel.contains('widget.template?.audience ?? widget.defaultAudience'), isTrue);
      final shell = _read('lib/features/admin/presentation/admin_shell.dart');
      expect(shell.contains("AdminTemplatesPanel(audience: 'service')"), isTrue);
    });
  });

  group('Data safety (rule 10)', () {
    test('migrations are numbered without gaps or duplicates', () {
      final nums = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => RegExp(r'^\d{4}_.*\.sql$').hasMatch(n))
          .map((n) => int.parse(n.substring(0, 4)))
          .toList()
        ..sort();
      for (var i = 0; i < nums.length; i++) {
        expect(nums[i], i + 1, reason: 'migration numbering broken near ${nums[i]}');
      }
    });
    test('new migrations (0031+) never drop tables or wipe data', () {
      final files = Directory('supabase/migrations').listSync().whereType<File>().where((f) {
        final n = f.uri.pathSegments.last;
        return RegExp(r'^\d{4}_').hasMatch(n) && int.parse(n.substring(0, 4)) >= 31;
      });
      final bad = RegExp(r'\bdrop\s+table\b|\btruncate\b|\bdelete\s+from\s+public\.(users|cargo|messages|conversations|service_providers)\b',
          caseSensitive: false);
      for (final f in files) {
        final sql = f.readAsStringSync().replaceAll(RegExp(r'--[^\n]*'), '');
        expect(bad.hasMatch(sql), isFalse, reason: '${f.path} contains a destructive statement');
      }
    });
  });

  group('Settings defaults', () {
    test('sounds and notifications are on by default', () {
      const s = NotifySettings();
      expect(s.cargoNotify && s.cargoSound && s.msgNotify && s.msgSound, isTrue);
      expect(s.copyWith(msgSound: false).msgSound, isFalse);
      expect(s.copyWith(msgSound: false).cargoSound, isTrue);
    });
  });

  group('AutoFix: no "ref after dispose" from lazy text controllers', () {
    test('controllers that read ref are made in initState', () {
      final lazy = RegExp(r'late final (TextEditingController )?_\w+ = TextEditingController\(text: ref\.');
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(lazy.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  });
}

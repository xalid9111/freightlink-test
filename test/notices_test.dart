// "Bildirişlər" (owner, 17.11.2026): one bell left of the heart on every
// page; its red number = unread notices (everything except chat messages);
// the page /notifications opens each notice's own place. SQL 0128 adds the
// offer / booking notices (supabase/tests/local/165_notice_center.sql).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/data/cargo_media_repository.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_media_providers.dart';
import 'package:freightlink/features/cargo/presentation/widgets/cargo_picture.dart';
import 'package:freightlink/features/notices/notices.dart';
import 'package:freightlink/repositories/profile_repository.dart';

String _read(String p) => File(p).readAsStringSync();
AppStrings _lang(String l) => AppStrings(Map<String, String>.from(jsonDecode(_read('assets/i18n/$l.json')) as Map));

class _Media implements CargoMediaRepository {
  @override
  Future<Set<String>> favoriteIds() async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

AppNotice _n(String type, {Map<String, dynamic> data = const {}, String title = '', String body = '', bool read = false}) =>
    AppNotice(id: type, type: type, title: title, body: body, data: data, isRead: read);

void main() {
  final az = _lang('az');

  group('one notice', () {
    test('a new offer on my load: the amount, the route, the load page', () {
      final n = _n('cargo_offer_new',
          data: {'cargo_id': 'c1', 'amount': 6000, 'currency': 'USD'}, body: 'Bakı → Sankt-Peterburq');
      expect(n.text(az), 'Yükünüzə yeni təklif: 6000 USD');
      expect(n.detail(), 'Bakı → Sankt-Peterburq');
      expect(n.route, '/load/c1');
    });
    test('accepted / rejected → the carrier; amounts without ".00"', () {
      expect(_n('cargo_offer_accepted', data: {'cargo_id': 'c1', 'amount': '5500.50', 'currency': 'USD'}).text(az),
          'Təklifiniz qəbul edildi: 5500.5 USD');
      expect(_n('cargo_offer_rejected', data: {'cargo_id': 'c1', 'amount': 300, 'currency': 'AZN'}).text(az),
          'Təklifiniz rədd edildi: 300 AZN');
    });
    test('TIR Park: booking / receipt / worker → the park panel', () {
      final b = _n('tirpark_booking', data: {'plate': '99-ZB-911'}, body: 'Ələt Park');
      expect(b.text(az), 'Parkınıza yeni rezervasiya');
      expect(b.detail(), '99-ZB-911 · Ələt Park');
      expect(b.route, '/tirpark/manage');
      expect(_n('tirpark_payment_review', title: 'Yeni ödəniş: 10-AA-100', body: 'Park · 3.00 AZN').detail(), '10-AA-100 · Park · 3.00 AZN');
      expect(_n('tirpark_worker_request', title: 'İşçi təsdiq gözləyir: Vəli', body: 'Park').detail(), 'Vəli · Park');
    });
    test('İş Mərkəzi notices keep their own texts and places', () {
      final j = _n('job_match_vacancy', data: {'vacancy_id': 'v1'});
      expect(j.text(az), az.t('job_ntf_match_vacancy'));
      expect(j.route, '/jobs/v/v1');
      expect(_n('job_application', title: 'Yeni müraciət').route, '/jobs/applications');
    });
    test('an unknown kind shows the server text and opens nothing', () {
      final u = _n('something_new', title: 'Salam');
      expect(u.text(az), 'Salam');
      expect(u.route, isNull);
    });
    test('a settled worker request / receipt leaves the list and the count (owner, 18.11.2026)', () {
      final w = _n('tirpark_worker_request', data: {'park_id': 'p', 'worker_id': 'u'});
      final j = _n('job_application');
      expect(w.isAction, isTrue);
      expect(_n('tirpark_payment_review').isAction, isTrue);
      expect(j.isAction, isFalse);
      expect(visibleNotices([w, j], {'tirpark_worker_request'}, parkManagement: true), [j]);
      expect(unreadNoticeCount(visibleNotices([w, j], {'tirpark_worker_request'}, parkManagement: true)), 1);
      expect(visibleNotices([w, j], const {}, parkManagement: true), [w, j]);
      // Park management off (owner, 20.11.2026): its notices are not shown.
      expect(visibleNotices([w, j], const {}), [j]);
      final src = _read('lib/features/notices/notices.dart');
      expect(src, contains("if (st != null && st != 'pending') out.add(n.id);"), reason: 'only a definite answer hides it');
      expect(src, contains("if (st != null && st != 'payment_review') out.add(n.id);"));
      expect(src, contains('ref.watch(shownNoticesProvider)'));
    });
    test('a TIRPark notice opens its tab with go (pushed it stayed black, owner 18.11.2026)', () {
      expect(_n('tirpark_worker_request').opensInTab, isTrue);
      expect(_n('cargo_offer_new', data: {'cargo_id': 'c'}).opensInTab, isFalse);
      expect(_n('job_application').opensInTab, isFalse);
      final src = _read('lib/features/notices/notices.dart');
      expect(src, contains('if (n.opensInTab) {\n                    context.go(r);'));
      // /tirpark/manage lives inside the TIRPark tab; /load and /jobs are full-screen pages.
      final router = _read('lib/core/router/app_router.dart');
      expect(router.indexOf("path: 'manage'"), greaterThan(router.indexOf("path: '/tirpark'")));
    });
    test('count = unread only; "99+" over 99', () {
      expect(unreadNoticeCount([_n('a'), _n('b', read: true), _n('c')]), 2);
      expect(noticeBadgeLabel(7), '7');
      expect(noticeBadgeLabel(120), '99+');
    });
    test('every notice text in all 6 languages', () {
      for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final s = _lang(l);
        for (final k in ['ntf_title', 'ntf_read_all', 'ntf_empty', 'ntf_offer_new', 'ntf_offer_accepted', 'ntf_offer_rejected',
            'ntf_tp_booking', 'ntf_tp_payment', 'ntf_tp_worker']) {
          expect(s.t(k), isNot(k), reason: '$l $k');
        }
        expect(s.t('ntf_offer_new', {'amount': '1 USD'}), contains('1 USD'));
      }
    });
  });

  testWidgets('Yüklər header: the bell left of the heart, with the red number', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('u1'),
        currentUserProvider.overrideWithValue(null),
        publicProfileProvider('u1').overrideWith((ref) async => const PublicProfile(id: 'u1', fullName: 'Founder')),
        cargoFavoriteIdsProvider.overrideWith((ref) => CargoFavoritesController(_Media())),
        myNoticesProvider.overrideWith((ref) => Stream.value([_n('a'), _n('b'), _n('c', read: true)])),
      ],
      child: MaterialApp(home: Scaffold(body: Align(alignment: Alignment.topRight, child: HeaderCircles(strings: az)))),
    ));
    await tester.pumpAndSettle();
    final bell = find.byKey(const ValueKey('notice-bell'));
    expect(bell, findsOneWidget);
    expect(tester.getCenter(bell).dx, lessThan(tester.getCenter(find.byKey(const ValueKey('hdr-favorites'))).dx));
    expect(find.descendant(of: bell, matching: find.text('2')), findsOneWidget);
    expect(tester.getSize(bell).width, 42, reason: 'the same round button as the heart');
  });

  group('wired on every page', () {
    test('the bell stands left of the heart on Yüklər, TIR Bazarı, Mesajlar, Profil and the maps', () {
      final pages = {
        'lib/features/cargo/presentation/widgets/cargo_picture.dart': "key: const ValueKey('hdr-favorites')",
        'lib/features/market/presentation/market_home_screen.dart': 'openFavorites(context, FavTab.market)',
        'lib/features/chat/presentation/conversations_screen.dart': "key: const ValueKey('msg-favorites')",
        'lib/features/auth/presentation/profile_screen.dart': "key: const ValueKey('profile-favorites')",
        'lib/features/tirpark/presentation/map_page_header.dart': "key: const ValueKey('map-favorites')",
        'lib/core/layout/desk_header_actions.dart': "key: const ValueKey('desk-favorites')",
        'lib/features/cargo/presentation/cargo_marketplace_desktop.dart': "key: const ValueKey('desk-favorites')",
      };
      pages.forEach((file, heart) {
        final src = _read(file);
        final b = src.indexOf('NoticeBell(');
        expect(b, greaterThan(0), reason: '$file has no bell');
        expect(src.indexOf(heart), greaterThan(b), reason: '$file: the bell is left of the heart');
      });
    });
    test('the maps (Parklar · Servislər · Mağazalar) use the Xəritə header with the bell', () {
      expect(_read('lib/features/tirpark/presentation/tir_park_screen.dart'), contains('MapPageHeader(s: s)'));
      expect(_read('lib/features/services/presentation/services_map_screen.dart'), contains('MapPageHeader(s: s)'));
    });
    test('/notifications is routed; a visitor is asked to sign in first', () {
      expect(_read('lib/core/router/app_router.dart'), contains("path: '/notifications'"));
      final n = _read('lib/features/notices/notices.dart');
      expect(n, contains('if (askSignIn(context)) return;'));
      expect(n, contains('liveWithResync('), reason: 'never waits for realtime alone');
      expect(n, isNot(contains("from('messages')")), reason: 'chat messages stay in Mesajlar');
    });
    test('SQL 0128 is additive and never blocks the offer / booking', () {
      final sql = _read('supabase/migrations/0128_notice_center.sql');
      expect(RegExp(r'\b(drop table|truncate|delete from|alter table)\b', caseSensitive: false).hasMatch(sql), isFalse);
      expect(RegExp(r'exception when others then').allMatches(sql).length, 2);
      expect(sql, contains("on conflict ((data ->> 'dedupe'))"));
    });
  });
}

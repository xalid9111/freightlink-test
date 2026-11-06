// Owner's six fixes (07.11.2026): the service / shop card opens the profile
// (its buttons keep their own work), no mini map on the profile (Marşrut
// stays), a shop is shown as a shop, a chat from a page carries the page,
// Google / Apple sign-in through Supabase OAuth (active only when switched
// on). The parking-spot removal is in map_add_buttons_test / SQL 115, 137.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/data/auth_repository_impl.dart' show oauthProvidersFromSettings;
import 'package:freightlink/features/auth/domain/auth_repository.dart';
import 'package:freightlink/features/auth/presentation/login_screen.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/chat/presentation/conversation_thread_screen.dart' show chatPageLabel, ChatPageBanner;
import 'package:freightlink/features/services/presentation/services_map_screen.dart' show ServiceListCard;
import 'package:freightlink/models/message_model.dart';
import 'package:freightlink/models/service_models.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

ServiceProvider _svc(List<String> cats, {String kind = 'center'}) => ServiceProvider(
      id: 's1', ownerId: 'u9', kind: kind, name: 'Avto Hissə', categories: cats, lat: 40.4, lng: 49.8,
      isMobile: false, is24h: false, isActive: true, status: 'approved', isVerified: false, addedByAdmin: false,
      photos: const [], ratingAvg: 0, ratingCount: 0, phone: '+994501234567',
    );

class _FakeAuth implements AuthRepository {
  final Set<String> on;
  int google = 0, apple = 0;
  _FakeAuth(this.on);
  @override
  Future<Set<String>> oauthProviders() async => on;
  @override
  Future<bool> signInWithGoogle() async {
    google++;
    return true;
  }

  @override
  Future<bool> signInWithApple() async {
    apple++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('2) the service / shop card', () {
    for (final shop in [false, true]) {
      testWidgets('${shop ? 'Mağazalar' : 'Servislər'}: the card body opens the profile; Zəng et / Mesaj yaz / Marşrut / rəy do not', (tester) async {
        tester.view.physicalSize = const Size(400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var opened = 0;
        await tester.pumpWidget(ProviderScope(
          overrides: [stringsProvider.overrideWithValue(_az)],
          child: MaterialApp(
            home: Scaffold(
              body: ServiceListCard(
                p: _svc(shop ? ['spare_parts', 'shop_new'] : ['tyres']),
                s: _az,
                lang: 'az',
                categories: const [],
                selected: true,
                route: null,
                hasGps: false,
                shop: shop,
                onTap: () => opened++,
              ),
            ),
          ),
        ));
        await tester.tap(find.text('Avto Hissə'));
        await tester.pump();
        expect(opened, 1, reason: 'the name opens the profile');
        await tester.tapAt(tester.getTopRight(find.byType(ServiceListCard)) + const Offset(-60, 10));
        await tester.pump();
        expect(opened, 2, reason: 'an empty part of the card too');
        await tester.tap(find.text(_az.t('svc_call')).first);
        await tester.pumpAndSettle();
        expect(opened, 2, reason: '"Zəng et" keeps its own work');
        await tester.tapAt(const Offset(5, 5)); // close the call sheet
        await tester.pumpAndSettle();
      });
    }
    test('wired in the list (Servislər and Mağazalar use the same card)', () {
      final m = src('lib/features/services/presentation/services_map_screen.dart');
      expect(m, contains("onTap: () => context.pushOnce('/service/\${p.id}'),"));
      expect(m.contains('onTap: () => onSelect(p),'), isFalse);
    });
  });

  test('3) no mini map on the profile; the address and "Marşrut" stay', () {
    final d = src('lib/features/services/presentation/service_detail_screen.dart');
    expect(d.contains('FlutterMap('), isFalse);
    expect(d, contains('ServiceContactBar(p: p, s: s)'), reason: 'Zəng et · Mesaj yaz · Marşrut');
    expect(d, contains("label: s.t('svc_location'),"), reason: 'the address');
    final w = src('lib/features/services/presentation/service_widgets.dart');
    expect(w, contains('showNavigationPicker('), reason: 'Marşrut opens the navigation apps');
  });

  test('4) a shop is shown as a shop (title and kind), a service as before', () {
    expect(_svc(['spare_parts', 'shop_new']).isShop, isTrue);
    expect(_svc(['tyres']).isShop, isFalse);
    final d = src('lib/features/services/presentation/service_detail_screen.dart');
    expect(d, contains("title: Text(s.t(async.valueOrNull?.isShop == true ? 'shop_profile_title' : 'svc_profile_title')),"));
    expect(d, contains("Text(s.t(p.isShop ? 'svc_shop' : (p.isCenter ? 'svc_kind_center' : 'svc_kind_individual')),"));
    expect(_az.t('shop_profile_title'), 'Mağaza');
    expect(_az.t('svc_profile_title'), 'Servis');
  });

  group('5) a chat from a page carries the page', () {
    ConversationModel conv(String? kind) => ConversationModel.fromJson({
          'id': 'c1',
          'cargo_id': null,
          'cargo_owner_id': 'u1',
          'carrier_user_id': 'u9',
          'service_id': kind == null ? null : 's1',
          'service_name': kind == null ? null : 'Avto Hissə',
          'service_kind': kind,
        });

    test('the label names the page and its kind; other chats stay as they were', () {
      expect(chatPageLabel(conv('shop'), _az), 'Mağaza: Avto Hissə');
      expect(chatPageLabel(conv('service'), _az), 'Servis: Avto Hissə');
      expect(chatPageLabel(conv(null), _az), isNull);
    });

    testWidgets('the banner over the chat (both sides) opens the page', (tester) async {
      final r = GoRouter(routes: [
        GoRoute(path: '/', builder: (c, s) => Scaffold(body: ChatPageBanner(conversation: conv('shop'), strings: _az))),
        GoRoute(path: '/service/:id', builder: (c, s) => Text('page ${s.pathParameters['id']}')),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      expect(find.text('Mağaza: Avto Hissə'), findsOneWidget);
      expect(find.text(_az.t('chat_ctx_hint')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-page-banner')));
      await tester.pumpAndSettle();
      expect(find.text('page s1'), findsOneWidget);
    });

    test('wired: "Mesaj yaz" opens the page chat; the list and the thread name it; SQL 0100 guards it', () {
      expect(src('lib/features/services/presentation/service_widgets.dart'),
          contains('openServicePage(widget.p.id, owner)'));
      expect(src('lib/features/chat/presentation/conversations_screen.dart'), contains('final page = chatPageLabel(item.conversation, strings);'));
      expect(src('lib/features/chat/presentation/conversation_thread_screen.dart'), contains('ChatPageBanner(conversation: c, strings: strings)'));
      final sql = src('supabase/migrations/0100_no_user_spots_service_chat_context.sql');
      expect(sql, contains('and service_id is null and service_name is null and service_kind is null'), reason: 'users cannot fake a page');
      expect(sql, contains('where c.cargo_id is null and c.shipment_id is null and c.service_id is null'),
          reason: 'the person-to-person chat is never a page chat (nothing merged)');
    });
  });

  group('6) Google / Apple sign-in', () {
    test('the providers switched on are read from Supabase /auth/v1/settings', () {
      expect(oauthProvidersFromSettings('{"external":{"google":true,"apple":false,"email":true}}'), {'google', 'email'});
      expect(oauthProvidersFromSettings('not json'), isEmpty);
      expect(oauthProvidersFromSettings('{}'), isEmpty);
    });

    Future<_FakeAuth> pumpLogin(WidgetTester tester, Set<String> on) async {
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _FakeAuth(on);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(_az),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp.router(
          // The test font is much wider than Arial: smaller text keeps the
          // login page's existing rows inside the screen.
          builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(0.6)), child: child!),
          routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const LoginScreen())]),
        ),
      ));
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('not switched on in Supabase: both buttons greyed out with a plain note; nothing starts', (tester) async {
      final auth = await pumpLogin(tester, const {});
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('oauth-google'))).onPressed, isNull);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('oauth-apple'))).onPressed, isNull);
      expect(find.byKey(const ValueKey('oauth-google-off')), findsOneWidget);
      expect(find.byKey(const ValueKey('oauth-apple-off')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('oauth-google')), warnIfMissed: false);
      expect(auth.google, 0);
    });

    testWidgets('Google on, Apple off: Google starts the sign-in, Apple stays greyed out', (tester) async {
      final auth = await pumpLogin(tester, const {'google'});
      expect(find.byKey(const ValueKey('oauth-google-off')), findsNothing);
      expect(find.byKey(const ValueKey('oauth-apple-off')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('oauth-google')));
      await tester.tap(find.byKey(const ValueKey('oauth-google')));
      await tester.pump();
      expect(auth.google, 1);
      expect(auth.apple, 0);
    });

    test('wired: Supabase OAuth back to the app\'s own address; the profile row from the trigger', () {
      final impl = src('lib/features/auth/data/auth_repository_impl.dart');
      expect(impl, contains('_client.auth.signInWithOAuth(provider, redirectTo: appBaseUrl())'));
      expect(impl, contains("code: 'oauth_not_configured'"));
      expect(impl.contains("code: 'not_implemented'"), isFalse);
      final sql = src('supabase/migrations/0100_no_user_spots_service_chat_context.sql');
      expect(sql, contains("nullif(new.raw_user_meta_data->>'name', '')"));
      final repo = src('.env.example');
      expect(repo.toLowerCase().contains('client_secret'), isFalse, reason: 'no secret in the repository');
    });
  });
}

import 'package:flutter/widgets.dart' show GlobalKey, Listenable, NavigatorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/profile_screen.dart';
import '../../features/auth/presentation/settings_screen.dart';
import '../../features/auth/presentation/change_password_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/cargo/presentation/cargo_marketplace_screen.dart';
import '../../features/cargo/presentation/cargo_quick_form.dart';
import '../../features/cargo/presentation/en_route_screen.dart';
import '../../features/cargo/presentation/favorite_cargo_screen.dart';
import '../../features/cargo/presentation/my_cargo_screen.dart';
import '../../features/cargo/presentation/cargo_detail_screen.dart';
import '../../features/cargo/presentation/search_screen.dart';
import '../../features/shipment/presentation/shipments_screen.dart';
import '../../features/chat/presentation/conversations_screen.dart';
import '../../features/chat/presentation/conversation_thread_screen.dart';
import '../../features/chat/presentation/group_thread_screen.dart';
import '../../features/chat/presentation/new_group_screen.dart';
import '../../features/admin/presentation/admin_shell.dart';
import '../../features/ads/presentation/advertise_screen.dart';
import '../../features/ads/presentation/ad_create_screen.dart';
import '../../features/ads/presentation/ad_order_screen.dart';
import '../../features/ads/presentation/public_profile_screen.dart';
import '../../features/ads/presentation/profile_catalog.dart';
import '../../features/services/presentation/service_detail_screen.dart';
import '../../features/services/presentation/service_edit_screen.dart';
import '../../features/services/presentation/services_map_screen.dart';
import '../autofix/route_error_screen.dart';
import '../config/supabase_config.dart';
import 'go_router_refresh_stream.dart';
import 'main_shell.dart';
import '../../features/jobs/presentation/job_center_screen.dart';
import '../../features/jobs/presentation/job_results_screen.dart';
import '../../features/jobs/presentation/job_seeker_form.dart';
import '../../features/jobs/presentation/job_vacancy_form.dart';
import 'password_recovery.dart';
import '../../features/finance/presentation/finance_screen.dart';
import '../widgets/deferred_page.dart';
import '../../features/market/presentation/market_module.dart' deferred as market;

/// Phase 1 shipped `appRouter` as a bare top-level GoRouter. Phase 3
/// promoted it to a Riverpod provider for auth-aware redirects. A later
/// pass added the bottom-navigation shell. This pass adds the real
/// screens under each branch: cargo detail (/cargo/:id) nests under
/// the Home branch (keeps the bottom nav visible, which makes sense
/// for a detail view you'll want to back out of quickly); cargo create
/// (/cargo/create) is attached to the root navigator instead, so it
/// opens full-screen without the bottom nav bar — standard go_router
/// pattern for "this route should cover the whole shell", used here
/// because a multi-section form benefits from the extra vertical space
/// and doesn't want stray tab-switching mid-fill-out. A conversation
/// thread (/messages/:id) nests under the Messages branch like cargo
/// detail. Nothing about the shell structure or redirect logic changed.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStream = SupabaseConfig.client.auth.onAuthStateChange;
  final recovery = ref.watch(passwordRecoveryProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/login',
    // Unknown route / broken link → reported to AutoFix + a way back.
    errorBuilder: (context, state) => RouteErrorScreen(location: state.uri.toString(), error: state.error),
    // Re-check redirects only when sign-in state can change. A token
    // refresh (every hour, and on every app resume) does not change who is
    // signed in, and re-running the whole router on it caused extra
    // rebuilds / a second transition on iPhone.
    refreshListenable: Listenable.merge([
      GoRouterRefreshStream(authStream.where((s) => s.event != AuthChangeEvent.tokenRefreshed)),
      recovery,
    ]),
    redirect: (context, state) {
      final signedIn = SupabaseConfig.client.auth.currentSession != null;
      final loc = state.matchedLocation;

      // Password reset link: the screen handles signed-in (recovery) and
      // signed-out (token_hash link / expired link) states itself.
      if (loc == '/reset-password') return null;
      // A recovery session may only be used to set the new password.
      if (signedIn && recovery.value) return '/reset-password';
      final onAuthScreen = loc == '/login' || loc == '/role-select' || loc.startsWith('/register');

      // Remember where the user was going (e.g. /admin opened from a
      // bookmark) and send them back there right after login.
      if (!signedIn && !onAuthScreen) {
        return Uri(path: '/login', queryParameters: {'from': state.uri.toString()}).toString();
      }
      if (signedIn && onAuthScreen) {
        // Just registered as "Usta / Servis" → fill in the service profile.
        final kind = SupabaseConfig.client.auth.currentUser?.userMetadata?['service_kind'];
        if (loc.startsWith('/register') && (kind == 'individual' || kind == 'center')) {
          return '/service-edit?kind=$kind';
        }
        final from = state.uri.queryParameters['from'];
        if (from != null && from.length > 1 && from.startsWith('/') && !from.startsWith('/login')) return from;
        return '/cargo';
      }
      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Package 1B: password management (Supabase Auth only).
      GoRoute(
        path: '/reset-password',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ResetPasswordScreen(tokenHash: state.uri.queryParameters['token_hash']),
      ),
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 4, child: SettingsScreen()),
      ),
      GoRoute(
        path: '/change-password',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 4, child: ChangePasswordScreen()),
      ),
      // No "Hansı işlə məşğulsunuz?" step any more: one account for
      // everyone, activities are chosen in Profil (0039). Old links land
      // on the registration form.
      GoRoute(
        path: '/role-select',
        redirect: (context, state) => '/register',
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          final role = state.uri.queryParameters['role'] ?? 'cargo_owner';
          final service = state.uri.queryParameters['service'];
          return RegisterScreen(
            role: role,
            serviceKind: (service == 'individual' || service == 'center') ? service : null,
          );
        },
      ),
      GoRoute(
        path: '/cargo/create',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: CargoQuickForm()),
      ),
      // "Yolüstü yük" (owner, 21.10.2026): small loads on the carrier's road.
      GoRoute(
        path: '/cargo/en-route',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: EnRouteScreen()),
      ),
      // "Seçilmiş yüklər" (owner, 22.10.2026): the heart at the top right.
      GoRoute(
        path: '/cargo/favorites',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: FavoriteCargoScreen()),
      ),
      // İş Mərkəzi — SmartMatch (owner, 26.10.2026): from the Loads header
      // and from Profil.
      GoRoute(
        path: '/jobs',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: JobCenterScreen()),
      ),
      GoRoute(
        path: '/jobs/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: JobSeekerFormScreen()),
      ),
      GoRoute(
        path: '/jobs/vacancy/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: JobVacancyFormScreen()),
      ),
      GoRoute(
        path: '/jobs/vacancy/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 0, child: JobVacancyFormScreen(id: state.pathParameters['id'])),
      ),
      GoRoute(
        path: '/jobs/work',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: JobResultsScreen(employer: false)),
      ),
      GoRoute(
        path: '/jobs/drivers',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            DeskFrame(section: 0, child: JobResultsScreen(employer: true, vacancyId: state.uri.queryParameters['vacancy'])),
      ),
      GoRoute(
        path: '/cargo-edit/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 0, child: CargoQuickForm(editCargoId: state.pathParameters['id']!)),
      ),
      // Admin Panel — separate full-screen area, outside the bottom-nav
      // shell. Access is enforced on the server (is_admin()).
      GoRoute(
        path: '/admin',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AdminShell(section: 'dashboard'),
      ),
      GoRoute(
        path: '/admin/:section',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => AdminShell(section: state.pathParameters['section']!),
      ),
      // Full-screen copies of detail/chat pages, opened from pages that
      // themselves sit above the tab shell (My loads, profiles, new group):
      // pushing a tab route from there would land UNDER the current page.
      GoRoute(
        path: '/load/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 0, child: CargoDetailScreen(cargoId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/chat/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 3, child: ConversationThreadScreen(conversationId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/chat-group/:gid',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 3, child: GroupThreadScreen(groupId: state.pathParameters['gid']!)),
      ),
      GoRoute(
        path: '/user/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 4, child: PublicProfileScreen(userId: state.pathParameters['id']!)),
      ),
      // WhatsApp-style catalog of a user's work (store icon in chats).
      GoRoute(
        path: '/user/:id/catalog',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 4, child: CatalogScreen(userId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/ads',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 4, child: AdvertiseScreen()),
      ),
      // Reklam yarat (template) and one order (payment / receipt / status).
      GoRoute(
        path: '/ad-create',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 4, child: AdCreateScreen(
          initialTemplateId: state.uri.queryParameters['tpl'],
          editOrderId: state.uri.queryParameters['order'],
          serviceId: state.uri.queryParameters['service'],
        )),
      ),
      GoRoute(
        path: '/ad-order/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 4, child: AdOrderScreen(id: state.pathParameters['id']!)),
      ),
      // Profile → Maliyyə və ödənişlər (0037): finance owner only (server-checked).
      GoRoute(
        path: '/finance',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 4, child: FinanceScreen()),
      ),
      // Services module (migration 0017): profile page, create / edit own
      // service profile, "join as a mechanic / service".
      GoRoute(
        path: '/service/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 5, child: ServiceDetailScreen(id: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/service-edit',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 5, child: ServiceEditScreen(initialKind: state.uri.queryParameters['kind'])),
      ),
      GoRoute(
        path: '/service-edit/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 5, child: ServiceEditScreen(id: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/service-join',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 5, child: ServiceJoinScreen()),
      ),
      GoRoute(
        path: '/my-cargo',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeskFrame(section: 0, child: MyCargoScreen()),
      ),
      // TIR Bazarı pages (deferred module, full screen like the other forms).
      GoRoute(
        path: '/market/new',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 6, child: DeferredPage(load: market.loadLibrary, builder: (_) => market.MarketEditScreen())),
      ),
      GoRoute(
        path: '/market/edit/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 6, child: DeferredPage(
          load: market.loadLibrary,
          builder: (_) => market.MarketEditScreen(listingId: state.pathParameters['id']),
        )),
      ),
      GoRoute(
        path: '/market/l/:id',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 6, child: DeferredPage(
          load: market.loadLibrary,
          builder: (_) => market.MarketDetailScreen(listingId: state.pathParameters['id']!),
        )),
      ),
      GoRoute(
        path: '/market/mine',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 6, child: DeferredPage(load: market.loadLibrary, builder: (_) => market.MyMarketListingsScreen())),
      ),
      GoRoute(
        path: '/market/favorites',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeskFrame(section: 6, child: DeferredPage(load: market.loadLibrary, builder: (_) => market.MarketFavoritesScreen())),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell, location: state.uri.path),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/cargo',
              builder: (context, state) => const CargoMarketplaceScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => CargoDetailScreen(cargoId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/shipments', builder: (context, state) => const ShipmentsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/messages',
              builder: (context, state) => const ConversationsScreen(),
              routes: [
                // Specific paths first — ':id' would otherwise match them.
                GoRoute(
                  path: 'new-group',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) => const NewGroupScreen(),
                ),
                GoRoute(
                  path: 'group/:gid',
                  builder: (context, state) => GroupThreadScreen(groupId: state.pathParameters['gid']!),
                ),
                // One thread per person (all load chats + the direct chat).
                GoRoute(
                  path: 'with/:uid',
                  builder: (context, state) => ConversationThreadScreen(otherUserId: state.pathParameters['uid']!),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) => ConversationThreadScreen(conversationId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          ]),
          // Branch 5 — Services map (added last so existing branch
          // indices stay unchanged).
          StatefulShellBranch(routes: [
            GoRoute(path: '/services', builder: (context, state) => const ServicesMapScreen()),
          ]),
          // Branch 6 — TIR Bazarı: a separate part of the app, downloaded
          // only when the tab is opened (deferred).
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/market',
              builder: (context, state) => DeferredPage(load: market.loadLibrary, builder: (_) => market.MarketHomeScreen()),
            ),
          ]),
        ],
      ),
    ],
  );
});

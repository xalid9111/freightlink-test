import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/supabase_config.dart';
import '../localization/locale_controller.dart';
import '../theme/app_theme.dart';

/// Site open / closed (owner, 25.10.2026, migration 0068). While the site
/// is closed only administrators use the app; everybody else sees the
/// owner's notice. [admin] comes from the server (is_admin()), not from
/// the app.
class SiteStatus {
  final bool closed;
  final String? message;
  final bool admin;
  const SiteStatus({this.closed = false, this.message, this.admin = false});

  static const open = SiteStatus();

  factory SiteStatus.fromJson(Map<String, dynamic> j) => SiteStatus(
        closed: j['closed'] == true,
        message: (j['message'] as String?)?.trim().isEmpty ?? true ? null : (j['message'] as String).trim(),
        admin: j['admin'] == true,
      );

  /// Whether this person must see the notice instead of the app.
  bool get blocks => closed && !admin;
}

/// How often an open app checks again (a closed site reaches people who
/// are already inside within this time).
const kSiteStatusEvery = Duration(seconds: 60);

/// Reads the state. Before 0068 is run, offline, or on any error the site
/// counts as open — a glitch never locks everybody out.
Future<SiteStatus> fetchSiteStatus() async {
  try {
    final res = await SupabaseConfig.client.rpc('site_status').timeout(const Duration(seconds: 15));
    if (res is Map) return SiteStatus.fromJson(Map<String, dynamic>.from(res));
  } on PostgrestException catch (_) {
    // PGRST202 (0068 not run yet) and the rest: open.
  } catch (_) {}
  return SiteStatus.open;
}

/// Admins only (checked + logged on the server): close with the notice, or open.
Future<SiteStatus> setSiteStatus({required bool closed, String? message}) async {
  final res = await SupabaseConfig.client
      .rpc('admin_set_site_status', params: {'p_closed': closed, 'p_message': message}).timeout(const Duration(seconds: 15));
  return SiteStatus.fromJson(Map<String, dynamic>.from(res as Map));
}

/// The state now and every [kSiteStatusEvery]; again when the signed-in
/// account changes.
final siteStatusProvider = StreamProvider<SiteStatus>((ref) async* {
  ref.watch(currentUserIdProvider);
  while (true) {
    yield await fetchSiteStatus();
    await Future<void>.delayed(kSiteStatusEvery);
  }
});

/// Put around the whole app (MaterialApp.builder): shows the notice instead
/// of the app while the site is closed for this person.
class SiteGate extends ConsumerStatefulWidget {
  final Widget child;
  const SiteGate({super.key, required this.child});

  @override
  ConsumerState<SiteGate> createState() => _SiteGateState();
}

class _SiteGateState extends ConsumerState<SiteGate> {
  /// A signed-out visitor tapped "Admin girişi": the login page shows.
  bool _adminLogin = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(currentUserIdProvider); // signed in / out → rebuild
    final status = ref.watch(siteStatusProvider).valueOrNull ?? SiteStatus.open;
    if (!status.blocks) return widget.child;
    final signedIn = SupabaseConfig.client.auth.currentSession != null;
    if (!signedIn && _adminLogin) return widget.child;
    return SiteClosedScreen(
      message: status.message,
      signedIn: signedIn,
      onAdminLogin: () => setState(() => _adminLogin = true),
      onSignOut: () async {
        await SupabaseConfig.client.auth.signOut();
        if (mounted) setState(() => _adminLogin = false);
      },
      onRetry: () => ref.invalidate(siteStatusProvider),
    );
  }
}

/// The notice a visitor sees while the site is closed.
class SiteClosedScreen extends ConsumerWidget {
  final String? message;
  final bool signedIn;
  final VoidCallback onAdminLogin, onRetry;
  final Future<void> Function() onSignOut;
  const SiteClosedScreen(
      {super.key,
      required this.message,
      required this.signedIn,
      required this.onAdminLogin,
      required this.onSignOut,
      required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Material(
      key: const ValueKey('site-closed'),
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_clock_outlined, size: 56, color: AppColors.accent),
                const SizedBox(height: 16),
                Text(s.t('site_closed_title'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 12),
                Text(
                  message ?? s.t('site_closed_default'),
                  key: const ValueKey('site-closed-message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.4, color: AppColors.text),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  key: const ValueKey('site-closed-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(s.t('site_closed_retry')),
                ),
                const SizedBox(height: 8),
                if (signedIn)
                  TextButton(
                    key: const ValueKey('site-closed-sign-out'),
                    onPressed: onSignOut,
                    child: Text(s.t('site_closed_sign_out')),
                  )
                else
                  TextButton(
                    key: const ValueKey('site-closed-admin-login'),
                    onPressed: onAdminLogin,
                    child: Text(s.t('site_closed_admin_login')),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

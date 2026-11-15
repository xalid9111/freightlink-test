import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/supabase_config.dart';
import '../localization/locale_controller.dart';
import 'auth_link_problem.dart';

/// The app's own messenger, so notices can be shown from above the pages.
final GlobalKey<ScaffoldMessengerState> appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// "Bu link artıq işləmir …" (owner, 15.11.2026, AutoFix): when an expired /
/// other-browser e-mail link was opened, says what happened once (at most
/// every 15 s) and, signed out, offers the login page where "Şifrəni
/// unutdum" sends a new link.
class AuthLinkNotice extends ConsumerStatefulWidget {
  final GoRouter router;
  final Widget child;
  const AuthLinkNotice({super.key, required this.router, required this.child});

  @override
  ConsumerState<AuthLinkNotice> createState() => _AuthLinkNoticeState();
}

class _AuthLinkNoticeState extends ConsumerState<AuthLinkNotice> {
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    authLinkProblems.addListener(_show);
    if (authLinkProblems.value > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  @override
  void dispose() {
    authLinkProblems.removeListener(_show);
    super.dispose();
  }

  void _show() {
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) < const Duration(seconds: 15)) return;
    final m = appMessengerKey.currentState;
    if (m == null) return;
    _last = now;
    final s = ref.read(stringsProvider);
    bool signedIn;
    try {
      signedIn = SupabaseConfig.client.auth.currentSession != null;
    } catch (_) {
      signedIn = false;
    }
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('auth-link-notice'),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        content: Text(s.t('auth_link_problem')),
        action: signedIn
            ? null
            : SnackBarAction(label: s.t('auth_link_login'), onPressed: () => widget.router.go('/login')),
      ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

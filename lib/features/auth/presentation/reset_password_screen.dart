import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/password_recovery.dart';
import '../../../core/theme/app_theme.dart';
import '../data/password_service.dart';
import 'change_password_screen.dart' show PasswordField;

/// /reset-password — opened from the e-mailed reset link.
///
/// The form is shown ONLY inside a password-recovery session (Supabase
/// emits AuthChangeEvent.passwordRecovery after the link is verified).
/// A normal signed-in session gets a pointer to Profile → Change password
/// instead, so this screen can never be used to skip the current-password
/// check.
///
/// Two link formats are supported:
///  * default Supabase link (PKCE `?code=`): exchanged automatically by
///    supabase_flutter on start-up — works in the browser that requested it;
///  * `#/reset-password?token_hash=…&type=recovery` (custom e-mail template,
///    recommended for iOS home-screen apps whose storage is separate from
///    Safari): verified here with verifyOTP.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? tokenHash;
  const ResetPasswordScreen({super.key, this.tokenHash});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _Phase { checking, form, invalid, notRecovery }

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  _Phase _phase = _Phase.checking;
  bool _busy = false;
  String? _error;
  Timer? _giveUp;

  late final PasswordRecoveryState _recovery;

  @override
  void initState() {
    super.initState();
    _recovery = ref.read(passwordRecoveryProvider);
    _recovery.addListener(_evaluate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _recovery.removeListener(_evaluate);
    _new
      ..clear()
      ..dispose();
    _repeat
      ..clear()
      ..dispose();
    super.dispose();
  }

  bool get _signedIn => SupabaseConfig.client.auth.currentSession != null;

  Future<void> _start() async {
    final hash = widget.tokenHash;
    if (hash != null && hash.isNotEmpty && !_recovery.value) {
      try {
        await ref.read(passwordServiceProvider).verifyRecoveryToken(hash);
      } on AppException catch (e) {
        if (!mounted) return;
        setState(() {
          _phase = _Phase.invalid;
          _error = ref.read(stringsProvider).error(e.code);
        });
        return;
      }
    }
    _evaluate();
    if (!mounted || _phase != _Phase.checking) return;
    // A default (PKCE) link is still being exchanged while ?code= is in the
    // address bar; otherwise there is nothing to wait for.
    final exchanging = Uri.base.queryParameters.containsKey('code');
    _giveUp = Timer(Duration(seconds: exchanging ? 8 : 2), () {
      if (mounted && _phase == _Phase.checking) {
        setState(() => _phase = _signedIn ? _Phase.notRecovery : _Phase.invalid);
      }
    });
  }

  void _evaluate() {
    if (!mounted || _busy) return;
    if (_recovery.value && _signedIn) {
      _giveUp?.cancel();
      if (_phase != _Phase.form) setState(() => _phase = _Phase.form);
    } else if (_phase == _Phase.form && !_signedIn) {
      setState(() => _phase = _Phase.invalid); // session ended meanwhile
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final strings = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passwordServiceProvider).setPasswordAfterRecovery(_new.text);
      _new.clear();
      _repeat.clear();
      _recovery.complete();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.check_circle_outline, color: AppColors.online, size: 36),
          title: Text(strings.t('pw_success_title')),
          content: Text(strings.t('pw_reset_success_body')),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(strings.t('pw_ok')))],
        ),
      );
      if (mounted) context.go('/cargo');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = strings.error(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = strings.t('error_pw_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leave without setting a password: end the recovery session.
  /// A recovery session is signed out; a normal session is left alone
  /// (the router then sends a signed-in user from /login to the app).
  Future<void> _cancel() async {
    final wasRecovery = _recovery.value || _phase == _Phase.form;
    _recovery.complete();
    if (wasRecovery) {
      try {
        await SupabaseConfig.client.auth.signOut();
      } catch (_) {
        // Local session is removed even if the network call fails.
      }
    }
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    Widget body;
    switch (_phase) {
      case _Phase.checking:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(strings.t('pw_reset_checking')),
        ]);
      case _Phase.invalid:
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.link_off, size: 40, color: AppColors.accent),
          const SizedBox(height: 12),
          Text(_error ?? strings.t('error_pw_link_invalid'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _cancel, child: Text(strings.t('pw_reset_go_login'))),
        ]);
      case _Phase.notRecovery:
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.info_outline, size: 40, color: AppColors.accent),
          const SizedBox(height: 12),
          Text(strings.t('pw_reset_use_change'), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => context.go('/change-password'), child: Text(strings.t('pw_reset_go_change'))),
        ]);
      case _Phase.form:
        body = Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(strings.t('pw_reset_body')),
              const SizedBox(height: 16),
              PasswordField(
                controller: _new,
                label: strings.t('pw_new'),
                strings: strings,
                autofill: AutofillHints.newPassword,
                enabled: !_busy,
                helper: strings.t('pw_rules'),
                validator: (v) {
                  if (v == null || v.isEmpty) return strings.t('pw_required');
                  if (v.length < kMinPasswordLength) return strings.t('error_pw_too_short');
                  return null;
                },
              ),
              const SizedBox(height: 14),
              PasswordField(
                controller: _repeat,
                label: strings.t('pw_confirm'),
                strings: strings,
                autofill: AutofillHints.newPassword,
                enabled: !_busy,
                onSubmitted: (_) => _submit(),
                validator: (v) {
                  if (v == null || v.isEmpty) return strings.t('pw_required');
                  if (v != _new.text) return strings.t('pw_mismatch');
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(strings.t('pw_submit')),
              ),
              const SizedBox(height: 6),
              TextButton(onPressed: _busy ? null : _cancel, child: Text(strings.t('pw_reset_cancel'))),
            ]),
          ),
        );
    }
    return PopScope(
      // A recovery session must end with a new password or a sign-out.
      canPop: _phase != _Phase.form,
      child: Scaffold(
        appBar: AppBar(title: Text(strings.t('pw_reset_title')), automaticallyImplyLeading: _phase != _Phase.form),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: body),
            ),
          ),
        ),
      ),
    );
  }
}

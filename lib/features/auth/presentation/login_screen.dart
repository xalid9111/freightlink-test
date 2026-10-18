import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/localization/locale_controller.dart';
import 'change_password_screen.dart' show ForgotPasswordButton;
import 'providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final strings = ref.read(stringsProvider);
    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // No explicit navigation on success: GoRouter's redirect (see
      // app_router.dart) reacts to the auth state change and sends a
      // signed-in user to /cargo on its own.
    } on AppException catch (e) {
      setState(() => _errorText = strings.error(e.code));
    } catch (e) {
      setState(() => _errorText = strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      strings.t('app_tagline'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: strings.t('common_email'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return strings.t('login_email_required');
                        if (!v.contains('@')) return strings.t('login_email_invalid');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: strings.t('common_password'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? strings.t('login_password_required') : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ForgotPasswordButton(
                        email: null,
                        prefill: () => _emailCtrl.text.trim(),
                        strings: strings,
                        enabled: !_submitting,
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 18, width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(strings.t('login_button')),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(strings.t('login_no_account')),
                        TextButton(
                          onPressed: () => context.go('/register'), // one account for everyone (0039)
                          child: Text(strings.t('login_signup_link')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const _OAuthRow(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Google/Apple buttons are present (per brief §5 architecture
/// requirement) but call the still-unimplemented repository methods,
/// which surface a clear "not connected yet" message rather than
/// silently doing nothing — see AuthRepositoryImpl.signInWithGoogle/Apple.
class _OAuthRow extends ConsumerWidget {
  const _OAuthRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);

    // Future<dynamic> (not Future<void>) is the parameter type on
    // purpose: Future<AppUser> Function() is not a subtype of
    // Future<void> Function() in Dart's type system (the void-return
    // exception only applies to a literal `void` return type, not a
    // generic like Future<void>) — using Future<dynamic> here accepts
    // signInWithGoogle/signInWithApple's real Future<AppUser> return
    // type without a compile error, and the value is intentionally
    // discarded (the auth stream, not this return value, is what
    // drives navigation on success).
    Future<void> tryOAuth(Future<dynamic> Function() call) async {
      try {
        await call();
      } on AppException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.error(e.code))));
        }
      }
    }

    final repo = ref.read(authRepositoryProvider);
    return Column(
      children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
        OutlinedButton.icon(
          onPressed: () => tryOAuth(repo.signInWithGoogle),
          icon: const Icon(Icons.g_mobiledata),
          label: Text(strings.t('oauth_google')),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => tryOAuth(repo.signInWithApple),
          icon: const Icon(Icons.apple),
          label: Text(strings.t('oauth_apple')),
        ),
      ],
    );
  }
}

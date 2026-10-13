import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../data/password_service.dart';

/// Profile → "Şifrəni dəyiş". Current + new + repeat, show/hide, one
/// submit at a time. All work is done by Supabase Auth (PasswordService);
/// nothing is stored locally and fields are cleared after use.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _new, _repeat]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // double-tap guard (button is also disabled)
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final strings = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passwordServiceProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      for (final c in [_current, _new, _repeat]) {
        c.clear();
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, color: AppColors.online, size: 36),
          title: Text(strings.t('pw_success_title')),
          content: Text(strings.t('pw_success_body')),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(strings.t('pw_ok')))],
        ),
      );
      if (mounted) Navigator.of(context).maybePop();
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == 'pw_wrong_current') _current.clear();
      setState(() => _error = strings.error(e.code));
    } catch (_) {
      if (mounted) setState(() => _error = strings.t('error_pw_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final service = ref.watch(passwordServiceProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('pw_change_title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: service.hasPasswordLogin
                  ? _buildForm(context, strings, service)
                  : _OAuthOnlyCard(strings: strings, service: service),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, AppStrings strings, PasswordService service) {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PasswordField(
              controller: _current,
              label: strings.t('pw_current'),
              strings: strings,
              autofill: AutofillHints.password,
              enabled: !_busy,
              validator: (v) => (v == null || v.isEmpty) ? strings.t('pw_required') : null,
            ),
            const SizedBox(height: 14),
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
                if (v == _current.text) return strings.t('error_pw_same');
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
            const SizedBox(height: 8),
            ForgotPasswordButton(email: service.email, strings: strings, enabled: !_busy),
          ],
        ),
      ),
    );
  }
}

/// Password input with its own show / hide toggle. No autocorrect /
/// suggestions, so the keyboard does not learn the password.
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final AppStrings strings;
  final String autofill;
  final bool enabled;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.strings,
    required this.autofill,
    this.enabled = true,
    this.helper,
    this.validator,
    this.onSubmitted,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: [widget.autofill],
      textInputAction: widget.onSubmitted == null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: widget.strings.t(_obscure ? 'pw_show' : 'pw_hide'),
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      validator: widget.validator,
    );
  }
}

/// "Şifrəni unutmusunuz?" — sends a Supabase reset link. Same answer
/// whether or not the address has an account; 60 s cooldown against
/// repeated taps / mail flooding (Supabase also rate-limits).
class ForgotPasswordButton extends ConsumerStatefulWidget {
  /// Signed in: the account's own address (shown read-only).
  final String? email;
  /// Signed out (login screen): current text of the e-mail field.
  final String Function()? prefill;
  final AppStrings strings;
  final bool enabled;
  final String? labelKey;
  const ForgotPasswordButton({
    super.key,
    required this.email,
    required this.strings,
    this.prefill,
    this.enabled = true,
    this.labelKey,
  });

  @override
  ConsumerState<ForgotPasswordButton> createState() => _ForgotPasswordButtonState();
}

class _ForgotPasswordButtonState extends ConsumerState<ForgotPasswordButton> {
  bool _sending = false;
  int _wait = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) {
        t.cancel();
        if (mounted) setState(() => _wait = 0);
        return;
      }
      setState(() => _wait--);
    });
  }

  Future<void> _ask() async {
    final s = widget.strings;
    final ctrl = TextEditingController(text: widget.email ?? widget.prefill?.call() ?? '');
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('pw_forgot_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('pw_forgot_body')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              readOnly: widget.email != null, // signed in: own address only
              decoration: InputDecoration(labelText: s.t('common_email'), border: const OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: Text(s.t('pw_forgot_send'))),
        ],
      ),
    );
    ctrl.dispose();
    if (address == null || address.isEmpty || !mounted) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(passwordServiceProvider).sendPasswordReset(address);
      _startCooldown();
      messenger.showSnackBar(SnackBar(content: Text(s.t('pw_forgot_sent')), duration: const Duration(seconds: 6)));
    } on AppException catch (e) {
      if (e.code == 'pw_rate_limited') _startCooldown();
      messenger.showSnackBar(SnackBar(content: Text(s.error(e.code))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('error_pw_generic'))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final label = _wait > 0 ? s.t('pw_forgot_wait', {'s': '$_wait'}) : s.t(widget.labelKey ?? 'pw_forgot');
    return TextButton(
      onPressed: (!widget.enabled || _sending || _wait > 0) ? null : _ask,
      child: _sending
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label, textAlign: TextAlign.center),
    );
  }
}

/// Accounts that sign in with Google / Apple only have no password to
/// change. Explain that, and offer a link to SET a FreightLink password.
class _OAuthOnlyCard extends StatelessWidget {
  final AppStrings strings;
  final PasswordService service;
  const _OAuthOnlyCard({required this.strings, required this.service});

  String _providerName() {
    final p = service.providers.where((e) => e != 'email').toList();
    if (p.isEmpty) return 'Google / Apple';
    return p.map((e) => switch (e) { 'google' => 'Google', 'apple' => 'Apple', _ => e }).join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.key_off_outlined, size: 36, color: AppColors.accent),
            const SizedBox(height: 10),
            Text(strings.t('pw_oauth_title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(strings.t('pw_oauth_body', {'provider': _providerName()}), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            if (service.email != null)
              ForgotPasswordButton(email: service.email, strings: strings, labelKey: 'pw_oauth_send'),
          ],
        ),
      ),
    );
  }
}

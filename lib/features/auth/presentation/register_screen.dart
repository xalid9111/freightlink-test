import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/widgets/phone_country_field.dart';
import 'providers/auth_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  final String role; // cargo_owner | carrier — chosen on RoleSelectScreen
  /// "Usta / Servis" registration: individual | center (null otherwise).
  /// The account itself keeps an ordinary role; the service profile is a
  /// separate record created right after signup.
  final String? serviceKind;
  const RegisterScreen({super.key, required this.role, this.serviceKind});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _phone; // international number (+994…), filled by PhoneCountryField; required
  bool _obscure = true;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _roleLabel(AppStrings strings) => widget.serviceKind != null
      ? strings.t(widget.serviceKind == 'center' ? 'svc_kind_center' : 'svc_kind_individual')
      : widget.role == AppConstants.roleCarrier
          ? strings.t('role_label_carrier')
          : strings.t('role_label_cargo_owner');

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Phone is required: double-check the captured international number.
    final digits = (_phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) {
      setState(() => _errorText = ref.read(stringsProvider).t('profile_phone_invalid'));
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final strings = ref.read(stringsProvider);
    try {
      final result = await ref.read(authRepositoryProvider).signUp(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            fullName: _nameCtrl.text.trim(),
            role: widget.role,
            phone: _phone,
            extraData: widget.serviceKind == null ? null : {'service_kind': widget.serviceKind},
          );

      if (!mounted) return;

      if (result.needsEmailConfirmation) {
        // No session exists yet (project has "Confirm email" on) — the
        // router's redirect won't fire on its own, so we navigate and
        // explain explicitly instead of leaving the user on a blank
        // register form wondering what happened.
        setState(() => _submitting = false);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(strings.t('register_email_confirm_title')),
            content: Text(strings.t('register_email_confirm_body')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.t('register_email_confirm_ok')),
              ),
            ],
          ),
        );
        if (mounted) context.go('/login');
        return;
      }
      // Session exists immediately (confirm-email is off) — the
      // router's redirect reacts to the auth state change on its own
      // and sends the now-signed-in user to /cargo. A new mechanic /
      // service goes straight to filling in the service profile.
      if (widget.serviceKind != null) {
        context.go('/service-edit?kind=${widget.serviceKind}');
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _errorText = strings.error(e.code));
    } catch (e) {
      if (mounted) setState(() => _errorText = strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t('register_title_prefix', {'role': _roleLabel(strings)})),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/role-select'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.t(widget.serviceKind != null ? 'svc_register_note' : 'register_role_locked_note'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: strings.t('register_name_label'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().length < 2) ? strings.t('register_name_required') : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: strings.t('register_email_label'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return strings.t('register_email_required');
                        if (!v.contains('@') || !v.contains('.')) return strings.t('register_email_invalid');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    // Phone is a public.users profile field, not the Supabase
                    // Auth identity (see AuthRepositoryImpl) — sign-in stays
                    // e-mail + password. Country picker (searchable) puts the
                    // right calling code in front automatically. Required:
                    // other users reach you by phone / WhatsApp.
                    PhoneCountryField(
                      label: strings.t('register_phone_label'),
                      onChanged: (e164) => _phone = e164,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: strings.t('register_password_label'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 8) return strings.t('register_password_too_short');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: strings.t('register_confirm_label'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v != _passwordCtrl.text) ? strings.t('register_confirm_mismatch') : null,
                      onFieldSubmitted: (_) => _submit(),
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
                          : Text(strings.t('register_submit')),
                    ),
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

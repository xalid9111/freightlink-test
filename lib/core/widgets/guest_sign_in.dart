import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../router/guest_access.dart';

/// Shown to a visitor (not signed in) where a phone number / contact would
/// be (owner, 07.11.2026): no number, one button that opens sign-in and
/// comes back to this page afterwards.
class GuestSignInButton extends StatelessWidget {
  final AppStrings s;
  /// The text key (default: "sign in to contact").
  final String label;
  const GuestSignInButton({super.key, required this.s, this.label = 'guest_contact_sign_in'});

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        key: const ValueKey('guest-sign-in'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        onPressed: () => askSignIn(context),
        icon: const Icon(Icons.login),
        label: Text(s.t(label)),
      );
}

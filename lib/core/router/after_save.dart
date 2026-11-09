import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/published_notice.dart';

/// One rule for every add / edit form (owner, 09.11.2026, "yadda saxladıqdan
/// sonra avtomatik geri qayıtma"): the form stays open until the server has
/// answered; only after a successful answer
///
/// 1. a short notice tells that it worked ([notice]; green with
///    [published], the "… dərc olundu ✓" look), and
/// 2. the user goes back to the page the form was opened from — the
///    previous page of this navigator, which reads the refreshed data the
///    form invalidated before calling this;
/// 3. a form opened straight from a link (nothing to go back to) goes to
///    its section's main page, [fallback].
///
/// A failure never calls this: the form stays with what was typed and
/// shows the error. A new item that belongs to a section list (a new load,
/// ad, service, shop, park request) keeps going straight to that section
/// (context.go) as before.
void leaveAfterSave(BuildContext context, {required String fallback, String? notice, bool published = false}) {
  if (notice != null) {
    if (published) {
      showPublishedNotice(context, notice);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(notice)));
    }
  }
  final nav = Navigator.of(context);
  if (nav.canPop()) {
    nav.pop();
    return;
  }
  GoRouter.of(context).go(fallback);
}

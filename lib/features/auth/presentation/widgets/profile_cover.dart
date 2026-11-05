import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../covers/profile_covers.dart';

/// The camera on the cover (Profil, owner 04.11.2026): the same background
/// as the seller's page ("Səhifəm və kataloqum"), so the same sheet
/// (owner 05.11.2026, 0096): admin templates of the shop section, an own
/// picture (a GIF stays animated), or "Yerini düzəlt" — saved in
/// profile_details.cover_url as before.
Future<void> editProfileCover({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings s,
  required String userId,
  required String? current,
  required double aspect,
}) =>
    changeShopCover(context: context, ref: ref, s: s, userId: userId, current: current, aspect: aspect);

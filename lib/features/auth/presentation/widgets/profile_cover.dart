import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/utils/gif.dart';
import '../../../../core/widgets/framed_image.dart';
import '../../../../core/widgets/image_frame_editor.dart';
import '../../../../repositories/profile_page_repository.dart';

/// The camera on the cover (Profil, owner 04.11.2026): the same as on
/// "Səhifəm və kataloqum" — a new picture (a GIF stays animated), or, when
/// there is one, "Yerini düzəlt" to move / zoom it. Saved with the existing
/// ProfilePageRepository (profile_details.cover_url); nothing new on the server.
Future<void> editProfileCover({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings s,
  required String userId,
  required String? current,
  required double aspect,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  var pick = 'new';
  if (current != null && current.isNotEmpty) {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('cover-new'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(s.t('photo_new')),
            onTap: () => Navigator.of(ctx).pop('new'),
          ),
          ListTile(
            key: const ValueKey('cover-adjust'),
            leading: const Icon(Icons.crop_free),
            title: Text(s.t('photo_adjust')),
            onTap: () => Navigator.of(ctx).pop('adjust'),
          ),
        ]),
      ),
    );
    if (chosen == null) return;
    pick = chosen;
  }
  try {
    if (pick == 'adjust') {
      final f = await navigator.push<ImageFraming>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageFrameEditorScreen(
          image: NetworkImage(ImageFraming.baseOf(current!)),
          initial: ImageFraming.of(current),
          aspect: aspect,
          circle: false,
          title: s.t('profile_change_cover'),
          s: s,
        ),
      ));
      if (f == null) return;
      await ref.read(profilePageRepositoryProvider).setCoverFraming(current!, f);
      ref.invalidate(profileDetailsProvider(userId));
      return;
    }
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (file == null) return;
    final picked = await file.readAsBytes();
    final gif = isGifBytes(picked);
    if (gif && picked.length > kGifMaxBytes) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('profile_gif_too_big'))));
      return;
    }
    final framing = await navigator.push<ImageFraming>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageFrameEditorScreen(
        image: MemoryImage(picked),
        aspect: aspect,
        circle: false,
        title: s.t('profile_change_cover'),
        s: s,
      ),
    ));
    if (framing == null) return;
    await ref
        .read(profilePageRepositoryProvider)
        .uploadCover(picked, contentType: gif ? 'image/gif' : (file.mimeType ?? 'image/jpeg'), framing: framing);
    ref.invalidate(profileDetailsProvider(userId));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('profile_photo_error'))));
  }
}

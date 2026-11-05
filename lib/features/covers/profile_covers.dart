import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/gif.dart';
import '../../core/widgets/framed_image.dart';
import '../../core/widgets/image_frame_editor.dart';
import '../../core/widgets/mouse_drag_scroll.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../../repositories/profile_page_repository.dart';

/// Profile backgrounds — "Fon şəklini dəyiş" (owner, 05.11.2026, 0096).
/// One flow for a TIR park, a service and a shop (the seller's page): the
/// owner picks an admin template of that section or uploads his own
/// picture, sees it in the background's frame (move / zoom), and saves.
/// The round profile picture and the gallery are separate and untouched.
enum CoverSection { park, service, shop }

extension CoverSectionX on CoverSection {
  String get wire => name;
}

class CoverTemplate {
  final String id, name, imageUrl;
  final List<CoverSection> sections;
  final bool isActive;
  const CoverTemplate({required this.id, required this.name, required this.imageUrl, required this.sections, this.isActive = true});

  factory CoverTemplate.fromJson(Map<String, dynamic> j) => CoverTemplate(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        imageUrl: '${j['image_url']}',
        sections: [
          for (final x in (j['sections'] as List? ?? const []))
            for (final s in CoverSection.values)
              if (s.wire == '$x') s,
        ],
        isActive: j['is_active'] != false,
      );
}

/// A park's / a service's own pictures (null = the default look).
class PlaceMedia {
  final String? cover, logo;
  const PlaceMedia({this.cover, this.logo});
}

/// The link without its place / zoom or cache part: the same picture.
String coverBase(String url) => url.split('?').first.split('#').first;

const _timeout = Duration(seconds: 20);

class CoverRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  /// Active templates of a section (an admin: [all] of them); empty
  /// before SQL 0096.
  Future<List<CoverTemplate>> templates({CoverSection? section, bool all = false}) async {
    try {
      var q = _c.from('cover_templates').select();
      if (!all) q = q.eq('is_active', true);
      if (section != null) q = q.contains('sections', [section.wire]);
      final rows = await q.order('sort_order').order('created_at').timeout(_timeout);
      return [for (final r in rows as List) CoverTemplate.fromJson(Map<String, dynamic>.from(r as Map))];
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205') return const [];
      rethrow;
    }
  }

  /// My own picture into my profile-media folder (0031); one file per
  /// place, replaced each time. Returns its link (new on every upload).
  Future<String> upload(String name, Uint8List bytes, {String? contentType}) async {
    final me = _c.auth.currentUser?.id;
    if (me == null) throw StateError('not signed in');
    final type = contentType ?? 'image/jpeg';
    final ext = switch (type) { 'image/png' => 'png', 'image/gif' => 'gif', 'image/webp' => 'webp', _ => 'jpg' };
    final path = '$me/covers/$name.$ext';
    await _c.storage.from('profile-media').uploadBinary(path, bytes, fileOptions: FileOptions(upsert: true, contentType: type));
    return '${_c.storage.from('profile-media').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<PlaceMedia> parkMedia(String id) async {
    try {
      final r = await _c.from('tir_parks').select('cover_url,logo_url').eq('id', id).maybeSingle().timeout(_timeout);
      return PlaceMedia(cover: r?['cover_url'] as String?, logo: r?['logo_url'] as String?);
    } catch (_) {
      return const PlaceMedia(); // before SQL 0096: the default look
    }
  }

  Future<PlaceMedia> serviceMedia(String id) async {
    try {
      final r = await _c.from('service_providers').select('cover_url').eq('id', id).maybeSingle().timeout(_timeout);
      return PlaceMedia(cover: r?['cover_url'] as String?);
    } catch (_) {
      return const PlaceMedia();
    }
  }

  Future<void> setParkCover(String id, String? url) =>
      _c.rpc('tir_park_set_cover', params: {'p_park': id, 'p_url': url}).timeout(_timeout);
  Future<void> setParkLogo(String id, String? url) =>
      _c.rpc('tir_park_set_logo', params: {'p_park': id, 'p_url': url}).timeout(_timeout);
  Future<void> setServiceCover(String id, String? url) =>
      _c.rpc('service_set_cover', params: {'p_service': id, 'p_url': url}).timeout(_timeout);

  /// Admin: add (id null) or change a template (checked + logged on the server).
  Future<void> adminSave({String? id, required String name, required String imageUrl, required List<CoverSection> sections, bool active = true}) =>
      _c.rpc('admin_cover_template_save', params: {
        'p_id': id,
        'p_name': name,
        'p_image_url': imageUrl,
        'p_sections': [for (final s in sections) s.wire],
        'p_active': active,
      }).timeout(_timeout);

  Future<void> adminDelete(String id) => _c.rpc('admin_cover_template_delete', params: {'p_id': id}).timeout(_timeout);
}

final coverRepositoryProvider = Provider<CoverRepository>((ref) => CoverRepository());

final coverTemplatesProvider = FutureProvider.autoDispose.family<List<CoverTemplate>, CoverSection>((ref, section) {
  ref.watch(currentUserIdProvider);
  return ref.watch(coverRepositoryProvider).templates(section: section);
});

/// Admin: every template, active or not.
final adminCoverTemplatesProvider = FutureProvider.autoDispose<List<CoverTemplate>>((ref) {
  return ref.watch(coverRepositoryProvider).templates(all: true);
});

/// A park's or a service's background (and the park's round picture).
final placeMediaProvider = FutureProvider.autoDispose.family<PlaceMedia, (CoverSection, String)>((ref, k) {
  ref.watch(currentUserIdProvider);
  final repo = ref.watch(coverRepositoryProvider);
  return k.$1 == CoverSection.park ? repo.parkMedia(k.$2) : repo.serviceMedia(k.$2);
});

/// Picks a picture from the device (a GIF up to 5 MB stays animated).
/// Null = cancelled or too big ([onTooBig] is told).
Future<(Uint8List, String)?> pickCoverPicture({VoidCallback? onTooBig}) async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > kGifMaxBytes) {
    onTooBig?.call();
    return null;
  }
  final type = isGifBytes(bytes) ? 'image/gif' : (file.mimeType ?? 'image/jpeg');
  return (bytes, type);
}

/// "Fon şəklini dəyiş": the sheet (templates / own picture), then the
/// picture in the background's frame, then [save] with the chosen link.
/// [upload] stores the owner's own picture and returns its link.
Future<bool> changeCover({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings s,
  required CoverSection section,
  required String? current,
  required double aspect,
  required Future<String> Function(Uint8List bytes, String contentType) upload,
  required Future<void> Function(String url) save,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final choice = await showModalBottomSheet<_CoverChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => CoverPickerSheet(s: s, section: section, current: current),
  );
  if (choice == null) return false;
  try {
    ImageProvider image;
    Uint8List? bytes;
    String? type;
    var initial = ImageFraming.centre;
    if (choice.upload) {
      final picked = await pickCoverPicture(onTooBig: () => messenger.showSnackBar(SnackBar(content: Text(s.t('profile_gif_too_big')))));
      if (picked == null) return false;
      (bytes, type) = picked;
      image = MemoryImage(bytes);
    } else if (choice.adjust) {
      image = NetworkImage(ImageFraming.baseOf(current!));
      initial = ImageFraming.of(current);
    } else {
      image = NetworkImage(choice.templateUrl!);
    }
    // The preview: the picture in the background's own frame (move / zoom).
    final framing = await navigator.push<ImageFraming>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageFrameEditorScreen(
        image: image,
        initial: initial,
        aspect: aspect,
        circle: false,
        title: s.t('cover_change'),
        s: s,
      ),
    ));
    if (framing == null) return false;
    final String url;
    if (bytes != null) {
      url = framing.applyTo(await upload(bytes, type!));
    } else if (choice.adjust) {
      url = framing.applyTo(current!);
    } else {
      url = framing.applyTo(choice.templateUrl!);
    }
    await save(url);
    return true;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('cover_error'))));
    return false;
  }
}

/// The round picture (a park's logo): own picture, circle frame.
Future<bool> changeRoundPicture({
  required BuildContext context,
  required AppStrings s,
  required Future<String> Function(Uint8List bytes, String contentType) upload,
  required Future<void> Function(String url) save,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    final picked = await pickCoverPicture(onTooBig: () => messenger.showSnackBar(SnackBar(content: Text(s.t('profile_gif_too_big')))));
    if (picked == null) return false;
    final framing = await navigator.push<ImageFraming>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageFrameEditorScreen(
        image: MemoryImage(picked.$1),
        aspect: 1,
        circle: true,
        title: s.t('cover_logo_change'),
        s: s,
      ),
    ));
    if (framing == null) return false;
    await save(framing.applyTo(await upload(picked.$1, picked.$2)));
    return true;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('cover_error'))));
    return false;
  }
}

class _CoverChoice {
  final String? templateUrl;
  final bool upload, adjust;
  const _CoverChoice({this.templateUrl, this.upload = false, this.adjust = false});
}

/// The sheet of the owner's picture (bottom, easy to close): templates of
/// this section, own picture, and "Yerini düzəlt" for the current one.
class CoverPickerSheet extends ConsumerWidget {
  final AppStrings s;
  final CoverSection section;
  final String? current;
  const CoverPickerSheet({super.key, required this.s, required this.section, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coverTemplatesProvider(section));
    final list = async.valueOrNull ?? const <CoverTemplate>[];
    final now = current == null ? null : coverBase(current!);
    Widget card({required Widget child}) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: child,
        );
    Widget iconTile(IconData icon, Color color) => Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        );
    return SingleChildScrollView(
      key: const ValueKey('cover-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const SizedBox(width: 48),
          Expanded(
            child: Text(s.t('cover_pick_title'),
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          IconButton(
            key: const ValueKey('cover-sheet-close'),
            tooltip: s.t('common_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ]),
        const SizedBox(height: 4),
        Text(s.t('cover_pick_sub'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, height: 1.35)),
        const SizedBox(height: 14),
        card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              iconTile(Icons.image_outlined, AppColors.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(s.t('cover_templates'), style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.text))),
            ]),
            const SizedBox(height: 12),
            if (async.isLoading && !async.hasValue)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              Text(s.t('cover_templates_none'), key: const ValueKey('cover-templates-none'), style: TextStyle(color: AppColors.textSoft))
            else
              SizedBox(
                height: 92,
                child: MouseDragScroll(child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final t = list[i];
                      final chosen = now != null && coverBase(t.imageUrl) == now;
                      return Semantics(
                        button: true,
                        label: t.name,
                        child: InkWell(
                          key: ValueKey('cover-template-${t.id}'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).pop(_CoverChoice(templateUrl: t.imageUrl)),
                          child: Container(
                            width: 148,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: chosen ? AppColors.online : AppColors.line, width: chosen ? 3 : 1),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(fit: StackFit.expand, children: [
                              Image.network(t.imageUrl, fit: BoxFit.cover, cacheWidth: 450,
                                  errorBuilder: (_, __, ___) => Container(color: AppColors.cardAlt)),
                              if (chosen)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    decoration: BoxDecoration(color: AppColors.online, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.check, size: 16, color: Colors.white),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ]),
        ),
        Material(
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: AppColors.line)),
          child: InkWell(
            key: const ValueKey('cover-upload'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).pop(const _CoverChoice(upload: true)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                iconTile(Icons.file_upload_outlined, AppColors.online),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.t('cover_upload'), style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(s.t('cover_upload_sub'), style: TextStyle(color: AppColors.textSoft)),
                  ]),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSoft),
              ]),
            ),
          ),
        ),
        if ((current ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('cover-adjust'),
            onPressed: () => Navigator.of(context).pop(const _CoverChoice(adjust: true)),
            icon: const Icon(Icons.crop_free),
            label: Text(s.t('photo_adjust')),
          ),
        ],
      ]),
    );
  }
}

/// The top of a park / service page (owner's design, 05.11.2026): the
/// background, the round picture half over its lower edge, the name and a
/// line under it. The owner gets "Fon şəklini dəyiş" (and a camera on the
/// round picture when [onAvatarEdit] is given); others may get [badge].
class PlaceCoverHeader extends StatelessWidget {
  final String? coverUrl;
  final Widget fallback;
  final Widget avatar;
  final String name;
  final Widget? subtitle;
  final VoidCallback? onChangeCover, onAvatarEdit;
  final Widget? badge;
  final String changeLabel;
  final double aspect;
  final double avatarSize;
  const PlaceCoverHeader({
    super.key,
    required this.coverUrl,
    required this.fallback,
    required this.avatar,
    required this.name,
    required this.changeLabel,
    this.subtitle,
    this.onChangeCover,
    this.onAvatarEdit,
    this.badge,
    this.aspect = kPlaceCoverAspect,
    this.avatarSize = 104,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxWidth / aspect;
      final over = avatarSize * 0.62;
      return Stack(clipBehavior: Clip.none, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(fit: StackFit.expand, children: [
                (coverUrl ?? '').isNotEmpty
                    ? FramedImage(
                        key: const ValueKey('place-cover'),
                        image: NetworkImage(coverUrl!),
                        framing: ImageFraming.of(coverUrl),
                        errorBuilder: (_, __, ___) => fallback,
                      )
                    : KeyedSubtree(key: const ValueKey('place-cover-default'), child: fallback),
                if (onChangeCover != null)
                  Positioned(right: 12, bottom: 12, child: CoverChangeButton(label: changeLabel, onTap: onChangeCover!))
                else if (badge != null)
                  Positioned(right: 12, bottom: 12, child: badge!),
              ]),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: avatarSize + 26, top: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: over - 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name,
                    key: const ValueKey('place-name'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (subtitle != null) ...[const SizedBox(height: 4), subtitle!],
              ]),
            ),
          ),
        ]),
        Positioned(
          left: 14,
          top: h - over,
          child: SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                key: const ValueKey('place-avatar'),
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: AppColors.background, width: 4),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: ClipOval(child: avatar),
              ),
              if (onAvatarEdit != null)
                Positioned(
                  right: -2,
                  bottom: 2,
                  child: Material(
                    color: AppColors.card,
                    shape: CircleBorder(side: BorderSide(color: AppColors.line)),
                    child: InkWell(
                      key: const ValueKey('place-avatar-edit'),
                      customBorder: const CircleBorder(),
                      onTap: onAvatarEdit,
                      child: Padding(padding: const EdgeInsets.all(7), child: Icon(Icons.photo_camera, size: 20, color: AppColors.text)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]);
    });
  }
}

/// "Fon şəklini dəyiş" on a background (the same on every page).
class CoverChangeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Key buttonKey;
  const CoverChangeButton({super.key, required this.label, required this.onTap, this.buttonKey = const ValueKey('cover-change')});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const StadiumBorder(side: BorderSide(color: Colors.white, width: 1.5)),
        child: InkWell(
          key: buttonKey,
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.image_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );
}

/// The shop's background (the seller's page and the Profil card share it):
/// the same sheet, saved in profile_details.cover_url (0031).
Future<bool> changeShopCover({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings s,
  required String userId,
  required String? current,
  required double aspect,
}) async {
  final ok = await changeCover(
    context: context,
    ref: ref,
    s: s,
    section: CoverSection.shop,
    current: current,
    aspect: aspect,
    upload: (b, t) => ref.read(coverRepositoryProvider).upload('shop', b, contentType: t),
    save: (url) => ref.read(profilePageRepositoryProvider).setCoverUrl(url),
  );
  if (ok) ref.invalidate(profileDetailsProvider(userId));
  return ok;
}

/// Width / height of a place's background.
const double kPlaceCoverAspect = 2.6;

/// A round picture with its place / zoom, or [fallback].
Widget roundPicture(String? url, Widget fallback) => (url ?? '').isEmpty
    ? fallback
    : FramedImage(image: NetworkImage(url!), framing: ImageFraming.of(url), errorBuilder: (_, __, ___) => fallback);

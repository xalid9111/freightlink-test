import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../repositories/profile_page_repository.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'catalog_reorder_grid.dart';

/// Pick a photo, write a short caption, upload it to my catalog.
Future<void> addCatalogPhoto(BuildContext context, WidgetRef ref, AppStrings s) async {
  final messenger = ScaffoldMessenger.of(context);
  XFile? file;
  try {
    file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('profile_photo_error'))));
    return;
  }
  if (file == null || !context.mounted) return;
  final bytes = await file.readAsBytes();
  if (bytes.length > 5 * 1024 * 1024) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('catalog_too_big'))));
    return;
  }
  if (!context.mounted) return;
  final caption = await showDialog<String>(
    context: context,
    builder: (ctx) => _CaptionDialog(s: s, preview: Image.memory(bytes, height: 180, fit: BoxFit.cover)),
  );
  if (caption == null) return;
  try {
    await ref.read(profilePageRepositoryProvider).addCatalogItem(bytes, caption: caption, contentType: file.mimeType);
    final uid = ref.read(currentUserIdProvider);
    if (uid != null) ref.invalidate(profileCatalogProvider(uid));
    messenger.showSnackBar(SnackBar(content: Text(s.t('catalog_added'))));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('$e'.contains('catalog_full') ? 'catalog_full' : 'catalog_add_failed'))));
  }
}

class _CaptionDialog extends StatefulWidget {
  final AppStrings s;
  final Widget? preview;
  final String? initial;
  const _CaptionDialog({required this.s, this.preview, this.initial});

  @override
  State<_CaptionDialog> createState() => _CaptionDialogState();
}

class _CaptionDialogState extends State<_CaptionDialog> {
  late final _ctrl = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return AlertDialog(
      title: Text(s.t('catalog_caption_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.preview != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(12), child: widget.preview),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _ctrl,
              maxLines: 3,
              maxLength: ProfilePageRepository.maxCaption,
              inputFormatters: [LengthLimitingTextInputFormatter(ProfilePageRepository.maxCaption)],
              decoration: InputDecoration(
                hintText: s.t('catalog_caption_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: Text(s.t('catalog_save'))),
      ],
    );
  }
}

/// Square photo tiles. [limit] shows only the first n (profile preview).
class CatalogGrid extends ConsumerWidget {
  final String userId;
  final int? limit;
  const CatalogGrid({super.key, required this.userId, this.limit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final isMe = ref.watch(currentUserIdProvider) == userId;
    final items = ref.watch(profileCatalogProvider(userId)).valueOrNull ?? const <CatalogItem>[];
    final shown = limit == null ? items : items.take(isMe ? limit! - 1 : limit!).toList();
    final tiles = <Widget>[
      if (isMe) _AddPhotoTile(s: s),
      for (var i = 0; i < shown.length; i++)
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CatalogViewer(userId: userId, initialIndex: items.indexOf(shown[i])),
          )),
          child: _Thumb(item: shown[i]),
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: tiles,
    );
  }
}

/// The "add photo" tile (owner only).
class _AddPhotoTile extends ConsumerWidget {
  final AppStrings s;
  const _AddPhotoTile({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => addCatalogPhoto(context, ref, s),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.accent),
            const SizedBox(height: 6),
            Text(s.t('catalog_add'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
          ],
        ),
      ),
    );
  }
}

/// One square photo thumbnail.
class _Thumb extends StatelessWidget {
  final CatalogItem item;
  const _Thumb({required this.item});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        item.imageUrl,
        fit: BoxFit.cover,
        cacheWidth: 360, // grid thumbnail, not the 1600 px original
        errorBuilder: (_, __, ___) => Container(color: AppColors.cardAlt, child: const Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

/// All catalog photos of a user. The owner can also change their order:
/// press and hold a photo, drag it, then "Yadda saxla".
class CatalogScreen extends ConsumerStatefulWidget {
  final String userId;
  const CatalogScreen({super.key, required this.userId});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  /// The order the owner arranged but has not saved yet (null = none).
  List<String>? _pending;
  bool _saving = false;

  Future<void> _save(AppStrings s) async {
    final ids = _pending;
    if (ids == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(profilePageRepositoryProvider).reorderCatalog(ids);
      if (!mounted) return;
      setState(() => _pending = null);
      ref.invalidate(profileCatalogProvider(widget.userId));
      messenger.showSnackBar(SnackBar(content: Text(s.t('catalog_order_saved'))));
    } catch (_) {
      // Photos changed on another device meanwhile, no connection, or the
      // database update (0035) is not installed yet: nothing was changed.
      ref.invalidate(profileCatalogProvider(widget.userId));
      messenger.showSnackBar(SnackBar(content: Text(s.t('catalog_order_failed'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final s = ref.watch(stringsProvider);
    final async = ref.watch(profileCatalogProvider(userId));
    final isMe = ref.watch(currentUserIdProvider) == userId;
    final items = async.valueOrNull ?? const <CatalogItem>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('profile_catalog')),
        actions: [
          if (isMe && _pending != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(onPressed: () => _save(s), child: Text(s.t('catalog_save'))),
            ),
        ],
      ),
      body: async.isLoading && !async.hasValue
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(profileCatalogProvider(userId)),
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (items.isEmpty && !isMe)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Center(child: Text(s.t('catalog_empty'), style: const TextStyle(color: AppColors.textSoft))),
                    ),
                  if (isMe && items.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(s.t('catalog_reorder_hint'), style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
                    ),
                  if (isMe)
                    CatalogReorderGrid(
                      items: items,
                      leading: _AddPhotoTile(s: s),
                      tileBuilder: (item) => _Thumb(item: item),
                      onOpen: (item) => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CatalogViewer(userId: userId, initialIndex: items.indexOf(item)),
                      )),
                      onOrderChanged: (ids) {
                        final server = [for (final i in items) i.id];
                        setState(() => _pending = listEquals(ids, server) ? null : ids);
                      },
                    )
                  else
                    CatalogGrid(userId: userId),
                ],
              ),
            ),
    );
  }
}

/// Full-screen photos with their captions; swipe between them. The owner
/// can edit the caption or delete the photo.
class CatalogViewer extends ConsumerStatefulWidget {
  final String userId;
  final int initialIndex;
  const CatalogViewer({super.key, required this.userId, this.initialIndex = 0});

  @override
  ConsumerState<CatalogViewer> createState() => _CatalogViewerState();
}

class _CatalogViewerState extends ConsumerState<CatalogViewer> {
  late final _page = PageController(initialPage: widget.initialIndex < 0 ? 0 : widget.initialIndex);
  late int _index = widget.initialIndex < 0 ? 0 : widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _edit(CatalogItem item, AppStrings s) async {
    final caption = await showDialog<String>(context: context, builder: (_) => _CaptionDialog(s: s, initial: item.caption));
    if (caption == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(profilePageRepositoryProvider).updateCaption(item.id, caption);
      ref.invalidate(profileCatalogProvider(widget.userId));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('error_generic'))));
    }
  }

  Future<void> _delete(CatalogItem item, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.t('catalog_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('chat_delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(profilePageRepositoryProvider).deleteCatalogItem(item);
      ref.invalidate(profileCatalogProvider(widget.userId));
      nav.pop();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('error_generic'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final items = ref.watch(profileCatalogProvider(widget.userId)).valueOrNull ?? const <CatalogItem>[];
    final isMe = ref.watch(currentUserIdProvider) == widget.userId;
    final current = items.isEmpty ? null : items[_index.clamp(0, items.length - 1)];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(items.isEmpty ? '' : '${_index + 1} / ${items.length}'),
        actions: [
          if (isMe && current != null) ...[
            IconButton(tooltip: s.t('catalog_edit_caption'), icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(current, s)),
            IconButton(tooltip: s.t('chat_delete'), icon: const Icon(Icons.delete_outline), onPressed: () => _delete(current, s)),
          ],
        ],
      ),
      body: items.isEmpty
          ? const SizedBox.shrink()
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => InteractiveViewer(
                      child: Center(child: Image.network(items[i].imageUrl, fit: BoxFit.contain)),
                    ),
                  ),
                ),
                if ((current?.caption ?? '').isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    color: Colors.black,
                    child: SafeArea(
                      top: false,
                      child: Text(current!.caption!, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
                    ),
                  ),
              ],
            ),
    );
  }
}

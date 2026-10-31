import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/gif.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../services/presentation/services_providers.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_widgets.dart';

/// One park (TIRPark PR 2, 0078): pictures, rating, place · distance,
/// amenities, the note and the comments ("Şərh yaz"). Admins add, replace
/// and delete its pictures (a GIF too).
class TirParkDetailScreen extends ConsumerStatefulWidget {
  final String parkId;
  /// Opened from "Şərh yaz": the comment form opens at once.
  final bool write;
  const TirParkDetailScreen({super.key, required this.parkId, this.write = false});

  @override
  ConsumerState<TirParkDetailScreen> createState() => _TirParkDetailScreenState();
}

class _TirParkDetailScreenState extends ConsumerState<TirParkDetailScreen> {
  bool _busy = false;
  bool _opened = false;

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _writeReview(TirPark park, TirParkReview? mine) async {
    final s = ref.read(stringsProvider);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReviewSheet(park: park, mine: mine, s: s),
    );
    if (saved == true) {
      ref.invalidate(tirParkReviewsProvider(park.id));
      ref.invalidate(tirParksProvider);
    }
  }

  Future<void> _deleteReview(TirParkReview r, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('tp_review_delete_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          TextButton(
            key: const ValueKey('tp-review-delete-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(s.t('tp_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tirParkRepositoryProvider).deleteReview(r.id);
      ref.invalidate(tirParkReviewsProvider(widget.parkId));
      ref.invalidate(tirParksProvider);
    } catch (_) {
      _snack(s.t('tp_err_generic'));
    }
  }

  /// Picks a picture (GIF kept as is, up to 5 MB) and uploads it.
  Future<String?> _pickAndUpload(TirPark park, AppStrings s) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final gif = isGifBytes(bytes);
    if (bytes.length > kGifMaxBytes) {
      _snack(s.t('profile_gif_too_big'));
      return null;
    }
    return ref.read(tirParkRepositoryProvider).uploadPhoto(park.id, bytes, contentType: gif ? 'image/gif' : file.mimeType);
  }

  Future<void> _photos(TirPark park, List<String> next, AppStrings s) async {
    setState(() => _busy = true);
    try {
      await ref.read(tirParkRepositoryProvider).setPhotos(park.id, next);
      ref.invalidate(tirParksProvider);
    } catch (_) {
      _snack(s.t('tp_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(TirPark park, AppStrings s) async {
    setState(() => _busy = true);
    try {
      final url = await _pickAndUpload(park, s);
      if (url != null) await _photos(park, [...park.photoUrls, url], s);
    } catch (_) {
      _snack(s.t('tp_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photoMenu(TirPark park, int i, AppStrings s) async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('tp-photo-replace'),
            leading: const Icon(Icons.swap_horiz),
            title: Text(s.t('tp_photo_replace')),
            onTap: () => Navigator.pop(ctx, 'replace'),
          ),
          ListTile(
            key: const ValueKey('tp-photo-delete'),
            leading: Icon(Icons.delete_outline, color: AppColors.danger),
            title: Text(s.t('tp_delete'), style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (pick == 'delete') {
      await _photos(park, [...park.photoUrls]..removeAt(i), s);
    } else if (pick == 'replace') {
      setState(() => _busy = true);
      try {
        final url = await _pickAndUpload(park, s);
        if (url != null) await _photos(park, [...park.photoUrls]..[i] = url, s);
      } catch (_) {
        _snack(s.t('tp_err_generic'));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final parksAsync = ref.watch(tirParksProvider);
    final park = (parksAsync.valueOrNull ?? const <TirPark>[]).where((p) => p.id == widget.parkId).firstOrNull;
    final me = ref.watch(currentUserProvider);
    final isAdmin = me?.role == AppConstants.roleAdmin;
    // Pictures: admins only (owner, 31.10.2026; checked on the server, 0078).
    final canEdit = park != null && isAdmin;
    final reviews = ref.watch(tirParkReviewsProvider(widget.parkId));
    final list = reviews.valueOrNull ?? const <TirParkReview>[];
    final mine = list.where((r) => r.userId == me?.id).firstOrNull;
    final here = ref.watch(userLocationProvider).point;

    if (park != null && widget.write && !_opened && park.isApproved && reviews.hasValue) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _writeReview(park, mine);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(park?.name ?? s.t('tp_parks'), maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: park == null
          ? Center(
              child: parksAsync.isLoading
                  ? const CircularProgressIndicator()
                  : Text(s.t('tp_not_found'), style: TextStyle(color: AppColors.textSoft)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                _Photos(
                  park: park,
                  canEdit: canEdit,
                  busy: _busy,
                  s: s,
                  onAdd: () => _addPhoto(park, s),
                  onEdit: (i) => _photoMenu(park, i, s),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Text(park.name, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: AppColors.text))),
                  if (park.ratingCount > 0) ...[
                    Icon(Icons.star_rounded, color: AppColors.promoPremium),
                    const SizedBox(width: 3),
                    Text(park.ratingAvg.toStringAsFixed(1), key: const ValueKey('tp-rating'), style: TextStyle(fontSize: 17, color: AppColors.text)),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((park.city ?? '').isNotEmpty) park.city!,
                    if (here != null) distanceLabel(distanceKm(here.latitude, here.longitude, park.lat, park.lng)),
                  ].join(' · '),
                  style: TextStyle(color: AppColors.textSoft),
                ),
                if (park.isPending) ...[
                  const SizedBox(height: 6),
                  Text(s.t('tp_pending'), style: TextStyle(color: AppColors.promoVip)),
                ],
                if (park.amenities.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final a in park.amenities) TirParkAmenityPill(code: a, s: s)]),
                ],
                if ((park.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(park.note!, style: TextStyle(color: AppColors.text, height: 1.35)),
                ],
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: Text(s.t('tp_reviews_n', {'n': '${list.length}'}),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                  if (park.isApproved)
                    OutlinedButton.icon(
                      key: const ValueKey('tp-write'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: BorderSide(color: AppColors.accent)),
                      onPressed: () => _writeReview(park, mine),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(mine == null ? s.t('tp_write') : s.t('tp_review_edit')),
                    ),
                ]),
                const SizedBox(height: 8),
                if (reviews.isLoading && !reviews.hasValue)
                  const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                else if (list.isEmpty)
                  Text(park.isApproved ? s.t('tp_reviews_none') : s.t('tp_reviews_after_approval'),
                      style: TextStyle(color: AppColors.textSoft))
                else
                  for (final r in list)
                    _ReviewTile(
                      r: r,
                      s: s,
                      canDelete: r.userId == me?.id || isAdmin,
                      onDelete: () => _deleteReview(r, s),
                    ),
              ],
            ),
    );
  }
}

/// Pictures: swipe through; the author / an admin adds (+), and replaces
/// or deletes one by a tap on its small copy.
class _Photos extends StatelessWidget {
  final TirPark park;
  final bool canEdit, busy;
  final AppStrings s;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  const _Photos({required this.park, required this.canEdit, required this.busy, required this.s, required this.onAdd, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final urls = park.photoUrls;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: urls.isEmpty
              ? Container(
                  color: AppColors.cardAlt,
                  child: Icon(Icons.local_parking, size: 64, color: AppColors.textSoft),
                )
              : PageView(
                  key: const ValueKey('tp-photos'),
                  children: [
                    for (final u in urls)
                      Image.network(u, fit: BoxFit.cover, cacheWidth: 1200,
                          errorBuilder: (_, __, ___) => Container(color: AppColors.cardAlt)),
                  ],
                ),
        ),
      ),
      if (canEdit) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 64,
          child: MouseDragScroll(child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < urls.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  key: ValueKey('tp-thumb-$i'),
                  onTap: busy ? null : () => onEdit(i),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(urls[i], width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192,
                        errorBuilder: (_, __, ___) => Container(width: 64, color: AppColors.cardAlt)),
                  ),
                ),
              ),
            if (urls.length < kTirParkMaxPhotos)
              InkWell(
                key: const ValueKey('tp-photo-add'),
                onTap: busy ? null : onAdd,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: busy
                      ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.add_a_photo_outlined, color: AppColors.accent),
                ),
              ),
          ])),
        ),
        const SizedBox(height: 4),
        Text(s.t('tp_photos_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
      ],
    ]);
  }
}

class _ReviewTile extends StatelessWidget {
  final TirParkReview r;
  final AppStrings s;
  final bool canDelete;
  final VoidCallback onDelete;
  const _ReviewTile({required this.r, required this.s, required this.canDelete, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = (r.name ?? '').trim().isEmpty ? '—' : r.name!.trim();
    return Container(
      key: ValueKey('tp-review-${r.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        UserAvatar(imageUrl: r.avatarUrl, initials: name.characters.first.toUpperCase(), radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text))),
              for (var i = 1; i <= 5; i++)
                Icon(i <= r.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 16, color: AppColors.promoPremium),
            ]),
            if ((r.comment ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(r.comment!, style: TextStyle(color: AppColors.text, height: 1.3)),
            ],
            if (r.createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(r.createdAt!.toLocal().toString().substring(0, 10), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
              ),
          ]),
        ),
        if (canDelete)
          IconButton(
            key: ValueKey('tp-review-delete-${r.id}'),
            tooltip: s.t('tp_delete'),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline, size: 20, color: AppColors.textSoft),
          ),
      ]),
    );
  }
}

/// "Şərh yaz": 1…5 stars (required) and a text (optional).
class _ReviewSheet extends ConsumerStatefulWidget {
  final TirPark park;
  final TirParkReview? mine;
  final AppStrings s;
  const _ReviewSheet({required this.park, required this.mine, required this.s});

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late int _stars = widget.mine?.rating ?? 0;
  late final _text = TextEditingController(text: widget.mine?.comment ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = widget.s;
    if (_stars < 1) {
      setState(() => _error = s.t('tp_review_stars_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tirParkRepositoryProvider).saveReview(widget.park.id, _stars, _text.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      setState(() => _error = s.t('tp_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.park.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey('tp-star-$i'),
                  iconSize: 36,
                  onPressed: () => setState(() => _stars = i),
                  icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.promoPremium),
                ),
            ]),
            TextField(
              key: const ValueKey('tp-review-text'),
              controller: _text,
              maxLength: 1000,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(hintText: s.t('tp_review_hint')),
            ),
            if (_error != null) Text(_error!, key: const ValueKey('tp-review-error'), style: TextStyle(color: AppColors.danger)),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('tp-review-save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(s.t('tp_review_send')),
            ),
          ]),
        ),
      ),
    );
  }
}

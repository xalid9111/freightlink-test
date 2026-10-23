import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mouse_drag_scroll.dart';
import '../../../../models/cargo_model.dart';
import '../../data/cargo_media_repository.dart';
import '../providers/cargo_media_providers.dart';

/// "Şəkillər" on the load form (owner, 22–23.10.2026): up to 6 pictures,
/// the first is the main one (shown on the Loads list). The chosen ones
/// are shown first — remove, move left / right, make main — then the
/// admin's pictures for the load type in one sideways row and
/// "Öz şəklini yüklə". Not required.
class CargoPictureField extends ConsumerStatefulWidget {
  final AppStrings strings;
  /// Template group of the chosen load type (null = none chosen / typed).
  final String? category;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  /// Called with each picture uploaded here, so the form can delete the
  /// ones that are not kept.
  final ValueChanged<String> onUploaded;
  const CargoPictureField({
    super.key,
    required this.strings,
    required this.category,
    required this.value,
    required this.onChanged,
    required this.onUploaded,
  });

  @override
  ConsumerState<CargoPictureField> createState() => _CargoPictureFieldState();
}

class _CargoPictureFieldState extends ConsumerState<CargoPictureField> {
  bool _uploading = false;

  static const _max = CargoModel.maxPictures;

  void _say(String key) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.t(key))));
  }

  Future<void> _upload() async {
    final left = _max - widget.value.length;
    if (left <= 0) return _say('cargo_pics_full');
    // Resized on the phone before upload (fast, small files).
    final files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80, limit: left);
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    final next = [...widget.value];
    try {
      for (final file in files.take(left)) {
        final name = file.name.contains('.') ? file.name : '${file.name}.jpg';
        final ext = name.split('.').last.toLowerCase();
        final bytes = await file.readAsBytes();
        final problem = CargoMediaRepository.checkUpload(bytes.length, ext);
        if (problem != null) {
          _say(problem);
          continue;
        }
        final url = await ref.read(cargoMediaRepositoryProvider).upload(bytes, ext);
        widget.onUploaded(url);
        next.add(url);
        widget.onChanged([...next]);
      }
    } catch (_) {
      _say('cargo_pic_upload_failed');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toggleTemplate(String url) {
    final v = widget.value;
    if (v.contains(url)) return widget.onChanged([...v]..remove(url));
    if (v.length >= _max) return _say('cargo_pics_full');
    widget.onChanged([...v, url]);
  }

  void _move(int i, int d) {
    final v = [...widget.value];
    final j = i + d;
    if (j < 0 || j >= v.length) return;
    final x = v.removeAt(i);
    v.insert(j, x);
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final cat = widget.category;
    final templates = cat == null
        ? const <CargoTemplate>[]
        : (ref.watch(cargoTemplatesProvider(cat)).valueOrNull ?? const <CargoTemplate>[]);
    final value = widget.value;
    final full = value.length >= _max;

    Widget frame({required Widget child, required bool selected, VoidCallback? onTap, Key? key}) => InkWell(
          key: key,
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 96,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.tileBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.accent : AppColors.tileLine, width: selected ? 2.4 : 1),
            ),
            child: child,
          ),
        );

    Widget small(IconData icon, String tip, VoidCallback? onTap, {Key? key}) => IconButton(
          key: key,
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          iconSize: 18,
          onPressed: onTap,
          icon: Icon(icon, color: onTap == null ? AppColors.line : AppColors.textSoft),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text(s.t(cat == null ? 'cargo_pic_pick_type' : 'cargo_pic_hint'),
              style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        ),
        const SizedBox(width: 8),
        Text('${value.length} / $_max',
            key: const ValueKey('cargo-pic-count'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: full ? AppColors.accent : AppColors.textSoft)),
      ]),
      // The chosen pictures, main first.
      if (value.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < value.length; i++)
            Column(key: ValueKey('cargo-pic-chosen-$i'), mainAxisSize: MainAxisSize.min, children: [
              Stack(children: [
                frame(
                  selected: i == 0,
                  child: Image.network(value[i], fit: BoxFit.cover, cacheWidth: 300,
                      errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: AppColors.textSoft)),
                ),
                if (i == 0)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(8)),
                      child: Text(s.t('cargo_pics_main'),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                  ),
              ]),
              SizedBox(
                width: 96,
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  small(Icons.chevron_left, '←', i == 0 ? null : () => _move(i, -1)),
                  small(Icons.star_outline, s.t('cargo_pics_make_main'), i == 0 ? null : () => _move(i, -i),
                      key: ValueKey('cargo-pic-main-$i')),
                  small(Icons.close, s.t('cargo_pic_remove'), () => widget.onChanged([...value]..removeAt(i)),
                      key: ValueKey('cargo-pic-remove-$i')),
                  small(Icons.chevron_right, '→', i == value.length - 1 ? null : () => _move(i, 1)),
                ]),
              ),
            ]),
        ]),
      ],
      const SizedBox(height: 10),
      // Templates of the load type + own upload.
      SizedBox(
        height: 72,
        child: MouseDragScroll(child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final t in templates) ...[
              frame(
                key: ValueKey('cargo-pic-${t.id}'),
                selected: value.contains(t.imageUrl),
                onTap: () => _toggleTemplate(t.imageUrl),
                child: Image.network(t.imageUrl, fit: BoxFit.cover, cacheWidth: 300,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
              const SizedBox(width: 10),
            ],
            frame(
              key: const ValueKey('cargo-pic-upload'),
              selected: false,
              onTap: _uploading ? null : (full ? () => _say('cargo_pics_full') : _upload),
              child: _uploading
                  ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_photo_alternate_outlined, color: full ? AppColors.textSoft : AppColors.accent),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(s.t('cargo_pic_upload'),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.text)),
                      ),
                    ]),
            ),
          ],
        )),
      ),
    ]);
  }
}

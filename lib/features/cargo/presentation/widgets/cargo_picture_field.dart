import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mouse_drag_scroll.dart';
import '../../data/cargo_media_repository.dart';
import '../providers/cargo_media_providers.dart';

/// "Şəkil" on the load form (owner, 22.10.2026): the admin's pictures for
/// the chosen load type in one sideways row, then "Öz şəklini yüklə".
/// Not required; tapping the chosen picture again removes it.
class CargoPictureField extends ConsumerStatefulWidget {
  final AppStrings strings;
  /// Template group of the chosen load type (null = none chosen / typed).
  final String? category;
  final String? value;
  final ValueChanged<String?> onChanged;
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

  Future<void> _upload() async {
    final s = widget.strings;
    // Resized on the phone before upload (fast, small files).
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final name = file.name.contains('.') ? file.name : '${file.name}.jpg';
      final url = await ref.read(cargoMediaRepositoryProvider).upload(bytes, name.split('.').last);
      widget.onUploaded(url);
      widget.onChanged(url);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('cargo_pic_upload_failed'))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final cat = widget.category;
    final templates = cat == null
        ? const <CargoTemplate>[]
        : (ref.watch(cargoTemplatesProvider(cat)).valueOrNull ?? const <CargoTemplate>[]);
    final value = widget.value;
    final own = value != null && !templates.any((t) => t.imageUrl == value);

    Widget tile({required Widget child, required bool selected, required VoidCallback? onTap, Key? key}) => InkWell(
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(cat == null ? s.t('cargo_pic_pick_type') : s.t('cargo_pic_hint'),
          style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
      const SizedBox(height: 10),
      SizedBox(
        height: 72,
        child: MouseDragScroll(child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            if (own) ...[
              tile(
                key: const ValueKey('cargo-pic-own'),
                selected: true,
                onTap: () => widget.onChanged(null),
                child: Image.network(value, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
              const SizedBox(width: 10),
            ],
            for (final t in templates) ...[
              tile(
                key: ValueKey('cargo-pic-${t.id}'),
                selected: value == t.imageUrl,
                onTap: () => widget.onChanged(value == t.imageUrl ? null : t.imageUrl),
                child: Image.network(t.imageUrl, fit: BoxFit.cover, cacheWidth: 300,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
              const SizedBox(width: 10),
            ],
            tile(
              key: const ValueKey('cargo-pic-upload'),
              selected: false,
              onTap: _uploading ? null : _upload,
              child: _uploading
                  ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_photo_alternate_outlined, color: AppColors.accent),
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
      if (value != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('cargo-pic-remove'),
            onPressed: () => widget.onChanged(null),
            icon: Icon(Icons.close, size: 16, color: AppColors.textSoft),
            label: Text(s.t('cargo_pic_remove'), style: TextStyle(color: AppColors.textSoft)),
          ),
        ),
    ]);
  }
}

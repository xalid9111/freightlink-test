import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/page_hero.dart';
import '../../domain/cargo_categories.dart';
import '../providers/category_providers.dart';

/// The five load-type tiles (TENT · REF · KONTEYNER · SAMOSVAL · QRUPAJ)
/// as a quick filter, plus "Digər növlər" (Açıq, Sistern) under them.
/// White tiles with dark pictures in night and day (owner, 21.10.2026).
class CargoTypeTiles extends ConsumerWidget {
  final AppStrings strings;
  final double tileHeight;
  final VoidCallback? onChanged;
  const CargoTypeTiles({super.key, required this.strings, this.tileHeight = 78, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(cargoCategoryFilterProvider);
    void set(CargoCategoryFilter n) {
      ref.read(cargoCategoryFilterProvider.notifier).state = n;
      onChanged?.call();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final t in kCategoryTruckTypes) ...[
          Expanded(
            child: CargoTypeTile(
              key: ValueKey('cat-$t'),
              code: t,
              label: strings.t('cat_$t'),
              selected: f.truckType == t,
              height: tileHeight,
              onTap: () => set(f.tapTruck(t)),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: CargoTypeTile(
            key: const ValueKey('cat-groupage'),
            code: 'groupage',
            label: strings.t('cat_groupage'),
            selected: f.groupage,
            height: tileHeight,
            onTap: () => set(f.tapGroupage()),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Text(strings.t('cat_other_types'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        const SizedBox(width: 8),
        for (final t in kOtherTruckTypes) ...[
          _SmallChip(
            key: ValueKey('cat-$t'),
            label: strings.t('truck_$t'),
            selected: f.truckType == t,
            onTap: () => set(f.tapTruck(t)),
          ),
          const SizedBox(width: 6),
        ],
      ]),
    ]);
  }
}

/// One white tile: dark picture + short label; selected = light orange.
class CargoTypeTile extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final double height;
  final VoidCallback onTap;
  const CargoTypeTile(
      {super.key, required this.code, required this.label, required this.selected, required this.onTap, this.height = 78});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tileSelectedBg : AppColors.tileBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.accent : AppColors.tileLine, width: selected ? 1.6 : 1),
            // Night: the chosen tile glows orange (owner's night picture).
            boxShadow: selected && !AppColors.isDay
                ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 12)]
                : null,
          ),
          child: Column(children: [
            Expanded(child: Image.asset(categoryIconAsset(code, night: !AppColors.isDay), fit: BoxFit.contain)),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.accent : AppColors.tileFg)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SmallChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tileSelectedBg : AppColors.tileBg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.accent : AppColors.tileLine),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: selected ? AppColors.accent : AppColors.tileFg)),
        ),
      ),
    );
  }
}

/// "Böyük yüklər" / "Kiçik yüklər": two picture cards; a tap shows the
/// loads of that size from the same load pool. Admins change the pictures
/// with the pencil (no deploy needed).
class CargoSizeCards extends ConsumerWidget {
  final AppStrings strings;
  final double height;
  final VoidCallback? onChanged;
  const CargoSizeCards({super.key, required this.strings, this.height = 64, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(cargoCategoryFilterProvider);
    final pictures = ref.watch(cargoSizeCardsProvider).valueOrNull ?? const {};
    final admin = isAdminUser(ref);
    return Row(children: [
      for (final c in kSizeCards) ...[
        if (c.size != kSizeCards.first.size) const SizedBox(width: 10),
        Expanded(
          child: _SizeCard(
            key: ValueKey('size-${c.size}'),
            title: strings.t(c.titleKey),
            subtitle: strings.t(c.subtitleKey),
            asset: 'assets/images/cargo/size_${c.size}.png',
            imageUrl: pictures[c.size],
            selected: f.size == c.size,
            height: height,
            onTap: () {
              ref.read(cargoCategoryFilterProvider.notifier).state = f.tapSize(c.size);
              onChanged?.call();
            },
            onEdit: admin ? () => _editPicture(context, ref, c.size, pictures[c.size]) : null,
            editTooltip: strings.t('cargo_size_edit_title'),
          ),
        ),
      ],
    ]);
  }

  Future<void> _editPicture(BuildContext context, WidgetRef ref, String size, String? current) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _SizeCardEditor(strings: strings, size: size, current: current),
    );
    if (changed == true) ref.invalidate(cargoSizeCardsProvider);
  }
}

class _SizeCard extends StatelessWidget {
  final String title, subtitle, editTooltip, asset;
  final String? imageUrl;
  final bool selected;
  final double height;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  const _SizeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.imageUrl,
    required this.selected,
    required this.height,
    required this.onTap,
    required this.onEdit,
    required this.editTooltip,
  });

  @override
  Widget build(BuildContext context) {
    // Owner's picture (21.10.2026): a light card (dark at night), the
    // cut-out picture on the left, the texts on the right, a round arrow;
    // the chosen card is orange-framed with a soft orange glow.
    final day = AppColors.isDay;
    final bg = selected ? AppColors.tileSelectedBg : (day ? AppColors.cardAlt : AppColors.tileBg);
    final picture = imageUrl == null
        ? Image.asset(asset, fit: BoxFit.contain)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(imageUrl!,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => Image.asset(asset, fit: BoxFit.contain)),
          );
    final arrowSize = (height * 0.34).clamp(18.0, 28.0);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.accent : AppColors.tileLine, width: selected ? 1.6 : 1),
            boxShadow: selected ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.30), blurRadius: 10)] : null,
          ),
          child: Row(children: [
            SizedBox(width: height * 1.05, child: picture),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(title,
                        maxLines: 1, style: TextStyle(color: AppColors.tileFg, fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(subtitle, maxLines: 1, style: TextStyle(color: AppColors.textSoft, fontSize: 10.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Pencil (admins) on top, the round arrow at the bottom — never over the texts.
            SizedBox(
              width: arrowSize,
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                if (onEdit != null)
                  Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onEdit,
                      child: Tooltip(
                        message: editTooltip,
                        child: const Padding(padding: EdgeInsets.all(3), child: Icon(Icons.edit, size: 11, color: Colors.white)),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Container(
                  width: arrowSize,
                  height: arrowSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.accent : (day ? AppColors.line : Colors.white12),
                  ),
                  child: Icon(Icons.chevron_right, size: arrowSize * 0.75, color: selected ? Colors.white : AppColors.tileFg),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Admin: choose / remove the picture of one size card.
class _SizeCardEditor extends ConsumerStatefulWidget {
  final AppStrings strings;
  final String size;
  final String? current;
  const _SizeCardEditor({required this.strings, required this.size, required this.current});

  @override
  ConsumerState<_SizeCardEditor> createState() => _SizeCardEditorState();
}

class _SizeCardEditorState extends ConsumerState<_SizeCardEditor> {
  late String? _url = widget.current;
  bool _busy = false;
  String? _error;

  AppStrings get s => widget.strings;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1000, imageQuality: 85);
    if (x == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await x.readAsBytes();
      final ext = x.name.contains('.') ? x.name.split('.').last : 'jpg';
      final url = await ref.read(pageHeroRepositoryProvider).upload(bytes, ext);
      if (mounted) setState(() => _url = url);
    } catch (_) {
      if (mounted) setState(() => _error = 'mk_hero_upload_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(cargoSizeCardsRepositoryProvider).save(widget.size, _url);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'cargo_size_save_failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${s.t('cargo_size_edit_title')} — ${s.t(widget.size == kLoadSizeBig ? 'cargo_size_big' : 'cargo_size_small')}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _url == null
                  ? Container(color: AppColors.sizeCardBg, child: const Icon(Icons.image_outlined, color: Colors.white38, size: 48))
                  : Image.network(_url!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('size-card-pick'),
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(s.t('cargo_size_pick')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('size-card-remove'),
                onPressed: _busy || _url == null ? null : () => setState(() => _url = null),
                icon: const Icon(Icons.delete_outline),
                label: Text(s.t('cargo_size_remove')),
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(s.t(_error!), style: TextStyle(color: AppColors.danger)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(s.t('common_cancel'))),
        FilledButton(
          key: const ValueKey('size-card-save'),
          onPressed: _busy ? null : _save,
          child: Text(s.t('catalog_save')),
        ),
      ],
    );
  }
}

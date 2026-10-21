import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mouse_drag_scroll.dart';
import '../../../../core/widgets/page_hero.dart';
import '../../domain/cargo_categories.dart';
import '../providers/category_providers.dart';

/// The load-type choices (owner, 21.10.2026): TENT · REF · KONTEYNER ·
/// SAMOSVAL · QRUPAJ · AÇIQ · SİSTERN — only the picture and the name, no
/// tile behind them; the chosen one is orange. One row that scrolls
/// sideways with a finger when it does not fit the screen.
class CargoTypeTiles extends ConsumerWidget {
  final AppStrings strings;
  final double tileHeight;
  final VoidCallback? onChanged;
  const CargoTypeTiles({super.key, required this.strings, this.tileHeight = 64, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(cargoCategoryFilterProvider);
    void set(CargoCategoryFilter n) {
      ref.read(cargoCategoryFilterProvider.notifier).state = n;
      onChanged?.call();
    }

    return SizedBox(
      height: tileHeight,
      child: MouseDragScroll(child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: kCategoryChoices.length,
          // 4½ choices fit a phone: the cut one shows there is more to the side.
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final c = kCategoryChoices[i];
            final groupage = c == 'groupage';
            return CargoTypeChoice(
              key: ValueKey('cat-$c'),
              code: c,
              label: strings.t('cat_$c'),
              selected: groupage ? f.groupage : f.truckType == c,
              onTap: () => set(groupage ? f.tapGroupage() : f.tapTruck(c)),
            );
          },
        )),
    );
  }
}

/// One choice: the truck picture and its name — white at night, dark in
/// day mode — orange with a short orange line when chosen.
class CargoTypeChoice extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const CargoTypeChoice({super.key, required this.code, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.text;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            height: 27,
            child: Image.asset(categoryIconAsset(code, night: !AppColors.isDay),
                fit: BoxFit.contain, color: color, colorBlendMode: BlendMode.srcIn),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 2.5,
            width: selected ? 24 : 0,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
          ),
        ]),
      ),
    );
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

/// "Böyük yüklər" / "Kiçik yüklər": two picture cards; a tap shows the
/// loads of that size from the same load pool. Admins change the pictures
/// with the pencil (no deploy needed).
class CargoSizeCards extends ConsumerWidget {
  final AppStrings strings;
  final double height;
  final VoidCallback? onChanged;
  const CargoSizeCards({super.key, required this.strings, this.height = 40, this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(cargoCategoryFilterProvider);
    final pictures = ref.watch(cargoSizeCardsProvider).valueOrNull ?? const {};
    final admin = isAdminUser(ref);
    return Row(children: [
      for (final c in kSizeCards) ...[
        if (c.size != kSizeCards.first.size) const SizedBox(width: 12),
        Expanded(
          child: _SizeCard(
            key: ValueKey('size-${c.size}'),
            title: strings.t(c.titleKey),
            subtitle: strings.t(c.subtitleKey),
            asset: 'assets/images/cargo/size_${c.size}.png',
            // The pallet is drawn 35 % smaller, so it reads as a small load (owner, 21.10.2026).
            assetScale: c.size == kLoadSizeSmall ? 0.65 : 1,
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
  final double assetScale;
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
    this.assetScale = 1,
    required this.imageUrl,
    required this.selected,
    required this.height,
    required this.onTap,
    required this.onEdit,
    required this.editTooltip,
  });

  @override
  Widget build(BuildContext context) {
    // Icon look (owner, 21.10.2026): no card behind it — a small picture,
    // the name and one line under it; orange when chosen.
    final picture = imageUrl == null
        ? Center(
            child: FractionallySizedBox(
              widthFactor: assetScale,
              heightFactor: assetScale,
              child: Image.asset(asset, fit: BoxFit.contain),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(imageUrl!,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => Image.asset(asset, fit: BoxFit.contain)),
          );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Row(children: [
          SizedBox(width: height * 1.3, child: picture),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(title,
                      maxLines: 1,
                      style: TextStyle(
                          color: selected ? AppColors.accent : AppColors.text, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(subtitle, maxLines: 1, style: TextStyle(color: AppColors.textSoft, fontSize: 10)),
                ),
                const SizedBox(height: 3),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 2.5,
                  width: selected ? 24 : 0,
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: editTooltip,
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: onEdit,
              icon: Icon(Icons.edit, color: AppColors.textSoft),
            ),
        ]),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../admin/data/admin_repository.dart';
import '../../admin/presentation/admin_widgets.dart';
import '../data/cargo_media_repository.dart';
import '../domain/cargo_categories.dart';
import '../domain/cargo_pictures.dart';
import 'providers/cargo_media_providers.dart';

/// Admin → "Yük şəkilləri" (owner, 22.10.2026, 0058): up to 10 pictures
/// per load type that load owners pick for their card. Add, remove and
/// reorder; every change is checked on the server and logged. Removing a
/// picture never changes the loads that already use it.
/// Admin pages are in Azerbaijani (like the rest of the admin panel).
const _kTypeNames = {
  'tent': 'Tent',
  'ref': 'Ref',
  'container': 'Konteyner',
  'dump': 'Samosval',
  'groupage': 'Qrupaj',
  'open': 'Açıq',
  'tanker': 'Sistern',
  'gazelle': 'Qazel',
  'manipulator': 'Manipulyator',
  'tow_truck': 'Evakuator',
  'van': 'Furqon',
  'lowbed': 'Lowbed',
  'car_carrier': 'Avtodaşıyıcı',
};

class AdminCargoPicturesPage extends ConsumerStatefulWidget {
  const AdminCargoPicturesPage({super.key});

  @override
  ConsumerState<AdminCargoPicturesPage> createState() => _AdminCargoPicturesPageState();
}

class _AdminCargoPicturesPageState extends ConsumerState<AdminCargoPicturesPage> {
  String _cat = kCategoryChoices.first;
  bool _busy = false;

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted && done != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) {
        final t = '$e'.contains('template_limit') ? 'Bu növ üçün ən çox $kMaxCargoTemplates şəkil olar.' : adminErrorText(e);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(t)));
      }
    } finally {
      ref.invalidate(cargoTemplatesProvider(_cat));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (file == null) return;
    final cat = _cat;
    await _run(() async {
      final repo = ref.read(cargoMediaRepositoryProvider);
      final bytes = await file.readAsBytes();
      final name = file.name.contains('.') ? file.name : '${file.name}.jpg';
      final url = await repo.upload(bytes, name.split('.').last, templateCategory: cat);
      await repo.addTemplate(cat, url);
    }, done: 'Şəkil əlavə olundu');
  }

  Future<void> _move(List<CargoTemplate> list, int i, int d) async {
    final j = i + d;
    if (j < 0 || j >= list.length) return;
    final ids = [for (final t in list) t.id];
    final x = ids.removeAt(i);
    ids.insert(j, x);
    await _run(() => ref.read(cargoMediaRepositoryProvider).reorderTemplates(_cat, ids));
  }

  Future<void> _delete(CargoTemplate t) async {
    final ok = await confirmAction(
      context,
      'Şəkli sil',
      'Bu şəkil şablonlardan silinsin?\n\nBu şəkli artıq seçmiş yüklərdə şəkil qalır.',
      ok: 'Sil',
      danger: true,
    );
    if (!ok) return;
    await _run(() => ref.read(cargoMediaRepositoryProvider).deleteTemplate(t.id), done: 'Silindi');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cargoTemplatesProvider(_cat));
    final list = async.valueOrNull ?? const <CargoTemplate>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('Yük verən yük paylaşanda kart üçün bu şəkillərdən birini seçir və ya öz şəklini yükləyir. '
            'Hər yük növü üçün ən çox $kMaxCargoTemplates şəkil. Şəkillərdə maşın olmasın — yalnız yük.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 13, height: 1.35)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in kCategoryChoices)
            ChoiceChip(
              key: ValueKey('adm-pic-cat-$c'),
              label: Text(_kTypeNames[c] ?? c),
              selected: _cat == c,
              onSelected: (_) => setState(() => _cat = c),
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text('${_kTypeNames[_cat] ?? _cat} · ${list.length} / $kMaxCargoTemplates',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          FilledButton.icon(
            key: const ValueKey('adm-pic-add'),
            onPressed: _busy || list.length >= kMaxCargoTemplates ? null : _add,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('Şəkil əlavə et'),
          ),
        ]),
        const SizedBox(height: 12),
        if (async.isLoading && list.isEmpty)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          const EmptyNote('Bu növ üçün hələ şəkil yoxdur')
        else
          for (var i = 0; i < list.length; i++)
            Card(
              key: ValueKey('adm-pic-${list[i].id}'),
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: Row(children: [
                SizedBox(
                  width: 120,
                  height: 80,
                  child: Image.network(list[i].imageUrl, fit: BoxFit.cover, cacheWidth: 300,
                      errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: AppColors.textSoft)),
                ),
                const SizedBox(width: 12),
                Text('${i + 1}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
                const Spacer(),
                IconButton(
                  tooltip: 'Yuxarı',
                  onPressed: _busy || i == 0 ? null : () => _move(list, i, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Aşağı',
                  onPressed: _busy || i == list.length - 1 ? null : () => _move(list, i, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Sil',
                  onPressed: _busy ? null : () => _delete(list[i]),
                  icon: Icon(Icons.delete_outline, color: AppColors.danger),
                ),
              ]),
            ),
      ],
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../covers/profile_covers.dart';
import 'admin_widgets.dart' show runAdmin;

const _sectionNames = {CoverSection.park: 'Park', CoverSection.service: 'Servis', CoverSection.shop: 'Mağaza'};

/// Admin → "Fon şablonları" (owner, 05.11.2026, 0096): the backgrounds park,
/// service and shop owners pick from. Add (picture + name + sections),
/// edit, switch on / off, delete. Checked and logged on the server.
class AdminCoverTemplatesPage extends ConsumerWidget {
  const AdminCoverTemplatesPage({super.key});

  Future<void> _delete(BuildContext context, WidgetRef ref, CoverTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Şablonu silmək?'),
        content: Text('"${t.name}" siyahıdan silinəcək. Onu artıq seçmiş profillərin fonu dəyişməyəcək.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (await runAdmin(context, () => ref.read(coverRepositoryProvider).adminDelete(t.id), success: 'Silindi')) {
      ref.invalidate(adminCoverTemplatesProvider);
      ref.invalidate(coverTemplatesProvider);
    }
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, CoverTemplate t, bool on) async {
    final ok = await runAdmin(
        context,
        () => ref.read(coverRepositoryProvider).adminSave(id: t.id, name: t.name, imageUrl: t.imageUrl, sections: t.sections, active: on));
    if (ok) {
      ref.invalidate(adminCoverTemplatesProvider);
      ref.invalidate(coverTemplatesProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminCoverTemplatesProvider);
    final list = async.valueOrNull ?? const <CoverTemplate>[];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
        Text('Fon şablonları', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
        FilledButton.icon(
          key: const ValueKey('admin-cover-add'),
          onPressed: () => showCoverTemplateEditor(context),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Şablon əlavə et'),
        ),
      ]),
      const SizedBox(height: 4),
      Text(
          'Park, servis və mağaza sahibləri "Fon şəklini dəyiş" pəncərəsində yalnız aktiv və öz bölməsinə aid şablonları görür. '
          'Silinən şablonu artıq seçmiş profillərin fonu dəyişmir.',
          style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
      const SizedBox(height: 12),
      if (async.isLoading && !async.hasValue) const Center(child: CircularProgressIndicator()),
      if (async.hasError) Text('Yüklənmədi: ${async.error}', style: TextStyle(color: AppColors.danger)),
      if (async.hasValue && list.isEmpty)
        Text('Hələ şablon yoxdur (0096_profile_covers.sql işə salınıbmı?)', style: TextStyle(color: AppColors.textSoft)),
      for (final t in list)
        Card(
          key: ValueKey('admin-cover-${t.id}'),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(t.imageUrl, width: 120, height: 64, fit: BoxFit.cover, cacheWidth: 360,
                    errorBuilder: (_, __, ___) => Container(width: 120, height: 64, color: AppColors.cardAlt)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final sct in t.sections)
                      Chip(visualDensity: VisualDensity.compact, label: Text(_sectionNames[sct]!, style: const TextStyle(fontSize: 12))),
                  ]),
                ]),
              ),
              Column(children: [
                Switch(value: t.isActive, onChanged: (v) => _toggle(context, ref, t, v)),
                Text(t.isActive ? 'Aktiv' : 'Passiv', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
              ]),
              IconButton(
                tooltip: 'Redaktə et',
                onPressed: () => showCoverTemplateEditor(context, template: t),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Sil',
                onPressed: () => _delete(context, ref, t),
                icon: Icon(Icons.delete_outline, color: AppColors.danger),
              ),
            ]),
          ),
        ),
    ]);
  }
}

/// Add or edit one template: picture, name, sections, on / off.
Future<void> showCoverTemplateEditor(BuildContext context, {CoverTemplate? template}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _TemplateEditor(template: template),
    );

class _TemplateEditor extends ConsumerStatefulWidget {
  final CoverTemplate? template;
  const _TemplateEditor({this.template});

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final Set<CoverSection> _sections = {...?widget.template?.sections};
  late bool _active = widget.template?.isActive ?? true;
  Uint8List? _bytes;
  String? _type;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await pickCoverPicture(onTooBig: () => setState(() => _error = 'Şəkil çox böyükdür (5 MB-a qədər).'));
    if (picked == null || !mounted) return;
    setState(() {
      _bytes = picked.$1;
      _type = picked.$2;
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 60) return setState(() => _error = 'Ad yazın (60 simvola qədər).');
    if (_sections.isEmpty) return setState(() => _error = 'Ən azı bir bölmə seçin.');
    if (_bytes == null && widget.template == null) return setState(() => _error = 'Şəkil seçin.');
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(coverRepositoryProvider);
    final nav = Navigator.of(context);
    final ok = await runAdmin(context, () async {
      final url = _bytes != null
          ? await repo.upload('template-${DateTime.now().millisecondsSinceEpoch}', _bytes!, contentType: _type)
          : widget.template!.imageUrl;
      await repo.adminSave(
          id: widget.template?.id,
          name: name,
          imageUrl: url,
          sections: [for (final s in CoverSection.values) if (_sections.contains(s)) s],
          active: _active);
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(adminCoverTemplatesProvider);
      ref.invalidate(coverTemplatesProvider);
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t == null ? 'Yeni fon şablonu' : 'Şablonu redaktə et',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 12),
        InkWell(
          key: const ValueKey('admin-cover-pick'),
          onTap: _busy ? null : _pick,
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: kPlaceCoverAspect,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _bytes != null
                  ? Image.memory(_bytes!, fit: BoxFit.cover)
                  : t != null
                      ? Image.network(t.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.cardAlt))
                      : Container(
                          color: AppColors.cardAlt,
                          alignment: Alignment.center,
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.accent),
                            const SizedBox(height: 6),
                            Text('Şəkil seç (JPG, PNG, WEBP, GIF · 5 MB-a qədər)', style: TextStyle(color: AppColors.textSoft)),
                          ]),
                        ),
            ),
          ),
        ),
        if (t != null) ...[
          const SizedBox(height: 4),
          Text('Şəkli dəyişmək üçün üstünə basın.', style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('admin-cover-name'),
          controller: _name,
          maxLength: 60,
          decoration: const InputDecoration(labelText: 'Şablonun adı'),
        ),
        const SizedBox(height: 4),
        Text('Hansı bölmələr üçün', style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final sct in CoverSection.values)
            FilterChip(
              key: ValueKey('admin-cover-sec-${sct.wire}'),
              label: Text(_sectionNames[sct]!),
              selected: _sections.contains(sct),
              onSelected: (v) => setState(() => v ? _sections.add(sct) : _sections.remove(sct)),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Aktiv'),
          subtitle: const Text('Passiv şablonu istifadəçilər görmür.'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        if (_error != null) Text(_error!, style: TextStyle(color: AppColors.danger)),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('admin-cover-save'),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Yadda saxla'),
        ),
      ]),
    );
  }
}

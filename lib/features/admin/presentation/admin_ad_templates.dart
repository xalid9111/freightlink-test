import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../ads/data/ads_repository.dart';
import '../../ads/presentation/ad_creative_view.dart';
import '../../ads/presentation/ads_providers.dart';
import 'admin_widgets.dart';

/// Scales any picture to COVER 1200×400 (centre crop) and returns PNG bytes.
Future<Uint8List> cropToAdBanner(ui.Image img) async {
  final w = img.width.toDouble(), h = img.height.toDouble();
  const target = AdBannerSpec.ratio;
  final src = w / h > target
      ? Rect.fromLTWH((w - h * target) / 2, 0, h * target, h)
      : Rect.fromLTWH(0, (h - w / target) / 2, w, w / target);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, AdBannerSpec.width.toDouble(), AdBannerSpec.height.toDouble()),
      Paint()..filterQuality = FilterQuality.high);
  final out = await recorder.endRecording().toImage(AdBannerSpec.width, AdBannerSpec.height);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// The two independent switches (both OFF at the start):
///  * ads in the home load list,
///  * the "Reklam ver" entry for customers.
/// Neither deletes orders or changes payments.
class HomeAdsSwitchCard extends ConsumerStatefulWidget {
  const HomeAdsSwitchCard({super.key});

  @override
  ConsumerState<HomeAdsSwitchCard> createState() => _HomeAdsSwitchCardState();
}

class _HomeAdsSwitchCardState extends ConsumerState<HomeAdsSwitchCard> {
  bool _busy = false;

  Future<void> _set({required bool feed, required bool on}) async {
    final ok = await confirmAction(
      context,
      feed ? (on ? 'Reklamları yük siyahısında göstər' : 'Reklamları yük siyahısından götür') : (on ? '"Reklam ver" girişini aç' : '"Reklam ver" girişini bağla'),
      feed
          ? (on
              ? 'Yük siyahısında (yeri "Reklamın yeri və müddəti" ilə təyin olunur) yalnız ödənişi təsdiqlənmiş və vaxtı çatmış reklamlar görünəcək.'
              : 'Yük siyahısında heç bir reklam görünməyəcək. Sifarişlər və ödənişlər dəyişmir.')
          : (on
              ? 'Müştərilər Profil → Reklam ver ilə yeni reklam sifariş edə biləcək.'
              : 'Yeni sifariş qəbul olunmayacaq. Mövcud sifarişlər və ödənişlər qalır, müştəri onları görə bilir.'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final repo = ref.read(adsRepositoryProvider);
    final done = await runAdmin(context, () => feed ? repo.setHomeAdsEnabled(on) : repo.setAdsOrderingEnabled(on));
    if (done) {
      ref.invalidate(homeAdsEnabledProvider);
      ref.invalidate(liveAdsProvider);
      ref.invalidate(adsOrderingEnabledProvider);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _row({required IconData icon, required String title, required String onText, required String offText, required AsyncValue<bool> value, required bool feed}) {
    final v = value.valueOrNull ?? false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: v ? AppColors.online.withValues(alpha: 0.10) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: v ? AppColors.online.withValues(alpha: 0.5) : AppColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: v ? AppColors.online : AppColors.textSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(v ? onText : offText, style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
              ],
            ),
          ),
          if (value.isLoading || _busy)
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Switch(value: v, onChanged: (x) => _set(feed: feed, on: x)),
        ],
      ),
    );
  }

  /// Admin: where the ads sit in the loads list and how long each stays.
  Future<void> _editLayout(AdFeedLayout cur) async {
    var first = cur.firstAfter;
    var every = cur.every;
    var minutes = cur.rotateMinutes;
    var repeat = cur.repeat;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Widget stepper(String label, String hint, int value, int min, int max, int step, ValueChanged<int> onSet) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        Text(hint, style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: value - step < min ? null : () => setD(() => onSet(value - step)),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: value + step > max ? null : () => setD(() => onSet(value + step)),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            );
          }

          // Small picture of the list: loads 1…N with the ad places in order.
          final rows = <Widget>[];
          var adNo = 0;
          for (var i = 1; i <= first + every * 2 && i <= 30; i++) {
            rows.add(_previewRow('Yük $i', false));
            if (i == first || (i > first && (i - first) % every == 0)) {
              adNo++;
              rows.add(_previewRow('REKLAM YERİ $adNo → sırada $adNo. reklam', true));
            }
          }
          return AlertDialog(
            title: const Text('Reklamın yeri və müddəti'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  stepper('İlk reklam', 'neçənci yükdən sonra çıxır', first, 1, 50, 1, (v) => first = v),
                  stepper('Sonrakı reklamlar', 'neçə yükdən bir çıxır', every, 2, 50, 1, (v) => every = v),
                  stepper('Sıra dəyişmə vaxtı',
                      minutes == 0 ? 'dəqiqə · 0 = sıra dəyişmir' : 'dəqiqədən bir: sonuncu reklam önə keçir, digərləri bir yer aşağı',
                      minutes, 0, 1440, minutes >= 60 ? 15 : (minutes >= 10 ? 5 : 1), (v) => minutes = v),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: repeat,
                    onChanged: (v) => setD(() => repeat = v),
                    title: const Text('Eyni reklam təkrar göstərilsin', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    subtitle: Text(
                      repeat
                          ? 'Reklam az olanda eyni reklam bir neçə yerdə çıxır.'
                          : 'Hər reklam yalnız bir yerdə çıxır. Reklamdan çox yer varsa, artıq yerlər boş qalır.',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft),
                    ),
                  ),
                  const Text('Reklamların sırasını Reklamlar → "Reklamlar" siyahısında ↑ ↓ düymələri ilə dəyişin. '
                      'Az yük olanda birinci reklam son yükdən sonra çıxır.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                  const SizedBox(height: 10),
                  const Text('Önizləmə', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
                  const SizedBox(height: 6),
                  ...rows,
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yadda saxla')),
            ],
          );
        },
      ),
    );
    if (save != true || !mounted) return;
    final repo = ref.read(adsRepositoryProvider);
    final done = await runAdmin(context, () => repo.setFeedLayout(firstAfter: first, every: every, rotateMinutes: minutes, repeat: repeat));
    if (done) ref.invalidate(adsFeedLayoutProvider);
  }

  static Widget _previewRow(String text, bool ad) => Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: ad ? 7 : 4),
        decoration: BoxDecoration(
          color: ad ? AppColors.accent.withValues(alpha: 0.18) : AppColors.cardAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ad ? AppColors.accent : AppColors.line),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 11.5, fontWeight: ad ? FontWeight.w800 : FontWeight.w500, color: ad ? AppColors.accent : AppColors.textSoft)),
      );

  String _layoutText(AdFeedLayout l) =>
      'İlk reklam ${l.firstAfter} yükdən sonra, sonra hər ${l.every} yükdən bir · '
      '${l.rotateMinutes == 0 ? 'sıra dəyişmir' : 'sıra hər ${l.rotateMinutes} dəq dəyişir'} · '
      '${l.repeat ? 'təkrar var' : 'təkrar yoxdur'}';

  @override
  Widget build(BuildContext context) {
    final layoutAsync = ref.watch(adsFeedLayoutProvider);
    final layout = layoutAsync.valueOrNull ?? AdFeedLayout.defaults;
    return Column(
      children: [
        _row(
          icon: Icons.view_agenda_outlined,
          title: 'Reklamlar yük siyahısında',
          onText: 'Aktivdir — ${_layoutText(layout)}',
          offText: 'Deaktivdir — yük siyahısında reklam yoxdur',
          value: ref.watch(homeAdsEnabledProvider),
          feed: true,
        ),
        _row(
          icon: Icons.campaign_outlined,
          title: '"Reklam ver" girişi',
          onText: 'Aktivdir — müştərilər sifariş verə bilir',
          offText: 'Deaktivdir — yeni sifariş qəbul olunmur',
          value: ref.watch(adsOrderingEnabledProvider),
          feed: false,
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.tune, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reklamın yeri və müddəti', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(_layoutText(layout), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: layoutAsync.isLoading ? null : () => _editLayout(layout),
                child: const Text('Tənzimlə'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Admin → Reklam şablonları: background images for the standard
/// 1200×400 layout — add, replace, rename, order, on/off, delete.
class AdminTemplatesPanel extends ConsumerWidget {
  const AdminTemplatesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminAdTemplatesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Standart: 1200×400 px. Loqo (30,120) 160×160 · Şirkət adı (220,45) 440×85 · Fəaliyyət (220,150) 440×75 · '
          'Telefon (220,250) 440×70 · Maşın / mənzərə zonası (690,20) 490×360. '
          'Fonda yazı, loqo və telefon olmamalıdır — onları müştəri əlavə edir.',
          style: TextStyle(color: AppColors.textSoft, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _open(context, ref, null, 0),
            icon: const Icon(Icons.add),
            label: const Text('Fon əlavə et'),
          ),
        ),
        const SizedBox(height: 12),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyNote('Yüklənmədi — 0023 SQL işə salınıb? ($e)'),
          data: (all) {
            final list = all.where((t) => t.isStandard).toList()..sort((a, b) => a.sort.compareTo(b.sort));
            final old = all.where((t) => !t.isStandard).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isEmpty) const EmptyNote('Hələ fon yoxdur'),
                for (var i = 0; i < list.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdCreativeView(creative: list[i].sample()),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text('${i + 1}. ${list[i].name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ),
                                AdminChip(switch (list[i].audience) {
                                  'service' => 'Servis',
                                  'all' => 'Hər ikisi',
                                  _ => 'Yük',
                                }, color: list[i].audience == 'service' ? AppColors.blue : AppColors.textSoft),
                                IconButton(
                                  tooltip: 'Yuxarı',
                                  onPressed: i == 0 ? null : () => _swap(context, ref, list, i, i - 1),
                                  icon: const Icon(Icons.arrow_upward, size: 20),
                                ),
                                IconButton(
                                  tooltip: 'Aşağı',
                                  onPressed: i == list.length - 1 ? null : () => _swap(context, ref, list, i, i + 1),
                                  icon: const Icon(Icons.arrow_downward, size: 20),
                                ),
                                IconButton(
                                  tooltip: 'Redaktə',
                                  onPressed: () => _open(context, ref, list[i], list[i].sort),
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                ),
                                Switch(
                                  value: list[i].isActive,
                                  onChanged: (v) async {
                                    if (await runAdmin(context, () => ref.read(adsRepositoryProvider).setTemplateActive(list[i].id, v),
                                        success: v ? 'Fon aktivdir' : 'Fon deaktivdir')) {
                                      if (context.mounted) _refresh(ref);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (old.isNotEmpty) ...[
                  const SectionTitle('Köhnə şablonlar (1350×300) — istifadə olunmur'),
                  for (final t in old)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AdminRow(
                        title: t.name,
                        subtitle: 'Köhnə format — müştərilərə göstərilmir',
                        dimmed: true,
                        chips: const [AdminChip('Köhnə')],
                        onTap: () => _delete(context, ref, t),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(adminAdTemplatesProvider);
    ref.invalidate(adTemplatesProvider);
    ref.invalidate(serviceAdTemplatesProvider);
  }

  Future<void> _swap(BuildContext context, WidgetRef ref, List<AdTemplate> list, int a, int b) async {
    final repo = ref.read(adsRepositoryProvider);
    // Renumber the whole list so the order is always 1..n.
    final order = [...list];
    final x = order.removeAt(a);
    order.insert(b, x);
    final ok = await runAdmin(context, () async {
      for (var i = 0; i < order.length; i++) {
        final t = order[i];
        if (t.sort != i + 1) {
          await repo.saveTemplateV2(id: t.id, name: t.name, imageUrl: t.imageUrl, active: t.isActive, sort: i + 1);
        }
      }
    }, success: 'Sıra yeniləndi');
    if (ok && context.mounted) _refresh(ref);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AdTemplate t) async {
    if (!await confirmAction(context, 'Silinsin?', '"${t.name}" silinəcək. Bu fonla verilmiş sifarişlər və reklamlar dəyişmir.', ok: 'Sil', danger: true)) {
      return;
    }
    if (!context.mounted) return;
    if (await runAdmin(context, () => ref.read(adsRepositoryProvider).deleteTemplate(t.id), success: 'Silindi') && context.mounted) {
      _refresh(ref);
    }
  }

  Future<void> _open(BuildContext context, WidgetRef ref, AdTemplate? t, int sort) async {
    final count = ref.read(adminAdTemplatesProvider).valueOrNull?.where((x) => x.isStandard).length ?? 0;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminTemplateEditor(template: t, nextSort: count + 1)),
    );
    if (saved == true && context.mounted) _refresh(ref);
  }
}

/// Add / edit one background: image (any photo is centre-cropped to
/// 1200×400), name, active. Positions are fixed — nothing else to set.
class AdminTemplateEditor extends ConsumerStatefulWidget {
  final AdTemplate? template;
  final int nextSort;
  const AdminTemplateEditor({super.key, this.template, this.nextSort = 100});

  @override
  ConsumerState<AdminTemplateEditor> createState() => _AdminTemplateEditorState();
}

class _AdminTemplateEditorState extends ConsumerState<AdminTemplateEditor> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late String? _imageUrl = widget.template?.imageUrl;
  late bool _active = widget.template?.isActive ?? true;
  /// Who may use the background: 'cargo', 'service' or 'all' (0029).
  late String _audience = widget.template?.audience ?? 'cargo';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _error = null);
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'], withData: true);
    final f = res?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return;
    setState(() => _busy = true);
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      if (!mounted) return;
      if (img.width < 900 || img.height < 300) {
        setState(() => _error = 'Şəkil kiçikdir: ${img.width}×${img.height}. Ən az 900×300, ideal 1200×400 px.');
        return;
      }
      final exact = img.width == AdBannerSpec.width && img.height == AdBannerSpec.height;
      final upload = exact ? bytes : await cropToAdBanner(img);
      final url = await ref.read(adsRepositoryProvider).uploadTemplateImage(upload, exact ? (f.extension ?? 'jpg') : 'png');
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Şəkil yüklənmədi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _imageUrl == null) {
      setState(() => _error = 'Ad və şəkil lazımdır.');
      return;
    }
    setState(() => _busy = true);
    final ok = await runAdmin(
      context,
      () async {
        final repo = ref.read(adsRepositoryProvider);
        final t = await repo.saveTemplateV2(
          id: widget.template?.id,
          name: _name.text.trim(),
          imageUrl: _imageUrl!,
          active: _active,
          sort: widget.template?.sort ?? widget.nextSort,
        );
        if (t.audience != _audience) await repo.setTemplateAudience(t.id, _audience);
      },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final preview = AdCreative(
      version: 2,
      imageUrl: _imageUrl ?? '',
      texts: const {'company': 'DELTA-GEO', 'activity': 'Logistics', 'phone': '+994 00 000 00 00'},
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template == null ? 'Yeni fon' : 'Fon: ${widget.template!.name}'),
        actions: [TextButton(onPressed: _busy ? null : _save, child: const Text('Yadda saxla'))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
        children: [
          const Text('Önizləmə (nümunə mətnlə, loqo yeri boş)', style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
          const SizedBox(height: 6),
          AdCreativeView(creative: preview, radius: BorderRadius.circular(12), showPlaceholders: true),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickImage,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.image_outlined),
            label: Text(_imageUrl == null ? 'Fon şəkli yüklə (1200×400)' : 'Fon şəklini dəyiş'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _name, maxLength: 80, decoration: const InputDecoration(labelText: 'Fonun adı (müştəri görür)')),
          const SizedBox(height: 4),
          const Text('Kim üçündür', style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cargo', label: Text('Yük'), icon: Icon(Icons.local_shipping_outlined)),
              ButtonSegment(value: 'service', label: Text('Servis'), icon: Icon(Icons.home_repair_service_outlined)),
              ButtonSegment(value: 'all', label: Text('Hər ikisi')),
            ],
            selected: {_audience},
            onSelectionChanged: (v) => setState(() => _audience = v.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktiv (müştərilərə göstər)'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Yadda saxla')),
          if (widget.template != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _busy
                  ? null
                  : () async {
                      if (!await confirmAction(context, 'Silinsin?',
                          '"${widget.template!.name}" silinəcək. Bu fonla verilmiş sifarişlər və reklamlar dəyişmir.',
                          ok: 'Sil', danger: true)) {
                        return;
                      }
                      if (!context.mounted) return;
                      final ok = await runAdmin(context, () => ref.read(adsRepositoryProvider).deleteTemplate(widget.template!.id),
                          success: 'Silindi');
                      if (ok && context.mounted) Navigator.pop(context, true);
                    },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Fonu sil'),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/night_theme.dart';
import '../../../core/theme/theme_mode.dart';
import '../data/night_theme_repository.dart';

/// Admin → Dizayn və Rənglər → Gecə rejimi (owner, 29.10.2026; 0076).
/// "Klassik FreightLink", "Bordo Premium" or the admin's own combination:
/// 7 colours (HEX or the colour picker), gradient and glow levels, a live
/// preview, the readability check; Önizlə (this device only), Yadda saxla
/// (a named draft), Yayımla (everybody), Əvvəlki temaya qayıt, Sıfırla.
/// Day mode is never changed from here.
class AdminDesignPage extends ConsumerStatefulWidget {
  const AdminDesignPage({super.key});

  @override
  ConsumerState<AdminDesignPage> createState() => _AdminDesignPageState();
}

const kNightColorLabels = {
  'background': '1. Əsas fon',
  'card': '2. Kartlar və panellər',
  'button': '3. Əsas düymələr',
  'accent': '4. Aktiv ikonlar və vurğular',
  'line': '5. Kontur və sərhəd',
  'text': '6. Əsas mətn',
  'text_soft': '6. İkinci dərəcəli mətn',
};

class _AdminDesignPageState extends ConsumerState<AdminDesignPage> {
  NightThemeSpec? _spec;
  String _choice = 'custom';
  String? _name;
  bool _busy = false;

  NightThemeSpec get spec => _spec ?? NightThemeSpec.classic;

  void _pick(String choice, NightThemeSpec s, {String? name}) => setState(() {
        _choice = choice;
        _spec = s;
        _name = name;
      });

  void _edit(NightThemeSpec s) => setState(() {
        _spec = s;
        if (_choice == 'classic' || _choice == 'bordo') {
          _choice = 'custom';
          _name = null;
        }
      });

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
            FilledButton(key: const ValueKey('design-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Bəli')),
          ],
        ),
      ) ==
      true;

  Future<void> _guard(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on NightThemeNotReady {
      _snack('Əvvəlcə Supabase-də SQL 0076 işə salınmalıdır.');
    } catch (_) {
      _snack('Alınmadı. Yenidən cəhd edin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ctrl = TextEditingController(text: _name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kombinasiyanın adı'),
        content: TextField(
          key: const ValueKey('design-name'),
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(hintText: 'Məs.: Bordo Premium 1, Black Edition'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ləğv et')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Yadda saxla')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _guard(() async {
      await ref.read(nightThemeRepositoryProvider).save(name, spec);
      ref.invalidate(savedNightThemesProvider);
      setState(() => _name = name);
      _snack('Qaralama yadda saxlanıldı: $name');
    });
  }

  Future<void> _publish() async {
    if (!readableEnough(spec)) {
      _snack('Mətn fonda oxunaqlı deyil (kontrast 4.5-dən azdır). Rəngləri dəyişin.');
      return;
    }
    final name = spec.isClassic ? 'Klassik FreightLink' : (_choice == 'bordo' ? 'Bordo Premium' : (_name ?? 'Öz kombinasiyam'));
    if (!await _confirm('Yayımlansın?', '"$name" gecə rejimində bütün istifadəçilərə tətbiq olunacaq. Gündüz rejimi dəyişmir.')) return;
    await _guard(() async {
      await ref.read(nightThemeRepositoryProvider).publish(spec, name);
      ref.invalidate(publishedNightThemeProvider);
      _snack('Yayımlandı: $name');
      await applyPublishedNightTheme(spec.isClassic ? null : spec);
    });
  }

  Future<void> _restore() async {
    if (!await _confirm('Əvvəlki temaya qayıdılsın?', 'Son yayımlanmış əvvəlki gecə rəngləri bərpa olunacaq.')) return;
    await _guard(() async {
      final back = await ref.read(nightThemeRepositoryProvider).restore();
      ref.invalidate(publishedNightThemeProvider);
      _snack('Əvvəlki tema bərpa olundu');
      await applyPublishedNightTheme(back);
    });
  }

  Future<void> _reset() async {
    if (!await _confirm('Sıfırlansın?', 'Klassik FreightLink gecə rəngləri hamı üçün geri qayıdacaq.')) return;
    await _guard(() async {
      await ref.read(nightThemeRepositoryProvider).publish(null, 'Klassik FreightLink');
      ref.invalidate(publishedNightThemeProvider);
      _pick('classic', NightThemeSpec.classic);
      _snack('Klassik FreightLink geri qayıtdı');
      await applyPublishedNightTheme(null);
    });
  }

  Future<void> _deleteSaved(SavedNightTheme t) async {
    if (!await _confirm('Silinsin?', '"${t.name}" qaralaması silinəcək. Yayımlanmış rənglər dəyişmir.')) return;
    await _guard(() async {
      await ref.read(nightThemeRepositoryProvider).delete(t.id);
      ref.invalidate(savedNightThemesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final published = ref.watch(publishedNightThemeProvider);
    final saved = ref.watch(savedNightThemesProvider);
    // Start from what is published now.
    if (_spec == null && published.hasValue) {
      final p = published.value?.spec;
      _spec = p ?? NightThemeSpec.classic;
      _choice = p == null ? 'classic' : (p.sameAs(NightThemeSpec.bordo) ? 'bordo' : 'custom');
      _name = published.value?.name;
    }
    final s = spec;
    final notReady = saved.error is NightThemeNotReady;
    final pub = published.value;
    Widget chip(String key, String label, bool on, VoidCallback tap, {VoidCallback? onDelete}) => InputChip(
          key: ValueKey(key),
          label: Text(label),
          selected: on,
          onPressed: tap,
          onDeleted: onDelete,
          showCheckmark: false,
          selectedColor: AppColors.accentFill.withValues(alpha: 0.25),
          side: BorderSide(color: on ? AppColors.accent : AppColors.line),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        Text('Dizayn və Rənglər · Gecə rejimi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 4),
        Text('Yalnız gecə rejimi dəyişir. Gündüz rejimi, şəkillər, VIP qızılı, status rəngləri və WhatsApp rəngi olduğu kimi qalır.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
        const SizedBox(height: 8),
        Text(
          'Hazırda yayımlanıb: ${pub?.spec == null ? 'Klassik FreightLink' : (pub?.name ?? 'Öz kombinasiya')}'
          '${pub?.updatedAt == null ? '' : ' · ${pub!.updatedAt!.toLocal().toString().substring(0, 16)}'}',
          key: const ValueKey('design-published'),
          style: TextStyle(color: AppColors.text, fontSize: 14),
        ),
        if (notReady)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('SQL 0076 hələ işə salınmayıb — yadda saxlamaq və yayımlamaq ondan sonra işləyəcək.',
                style: TextStyle(color: AppColors.danger, fontSize: 13.5)),
          ),
        if (nightPreviewActive)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const ValueKey('design-preview-end'),
              onPressed: endNightPreview,
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Bu cihazda önizləməni bitir'),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          chip('design-classic', 'Klassik FreightLink', _choice == 'classic', () => _pick('classic', NightThemeSpec.classic)),
          chip('design-bordo', 'Bordo Premium', _choice == 'bordo', () => _pick('bordo', NightThemeSpec.bordo)),
          chip('design-custom', 'Öz kombinasiyam', _choice == 'custom', () => setState(() => _choice = 'custom')),
          for (final t in saved.valueOrNull ?? const <SavedNightTheme>[])
            chip('design-saved-${t.id}', t.name, _choice == 'saved:${t.id}', () => _pick('saved:${t.id}', t.spec, name: t.name),
                onDelete: () => _deleteSaved(t)),
        ]),
        const SizedBox(height: 16),
        NightThemePreview(spec: s),
        const SizedBox(height: 16),
        for (final k in NightThemeSpec.colorKeys)
          _ColorRow(
            key: ValueKey('design-row-$k-${hexOf(s.colorOf(k))}'),
            colorKey: k,
            label: kNightColorLabels[k]!,
            color: s.colorOf(k),
            onChanged: (c) => _edit(s.withColor(k, c)),
          ),
        _LevelRow(
          label: '7. Gradientin intensivliyi',
          sliderKey: 'design-gradient',
          value: s.gradient,
          onChanged: (v) => _edit(s.withLevels(gradient: v)),
        ),
        _LevelRow(
          label: '8. Kölgə və yumşaq parıltı',
          sliderKey: 'design-glow',
          value: s.glow,
          onChanged: (v) => _edit(s.withLevels(glow: v)),
        ),
        const SizedBox(height: 12),
        Text('Oxunaqlılıq (avtomatik yoxlama)', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 6),
        for (final c in contrastChecks(s))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Icon(c.ok ? Icons.check_circle : Icons.warning_amber_rounded, size: 18, color: c.ok ? AppColors.online : AppColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(c.label, style: TextStyle(color: AppColors.text, fontSize: 13.5))),
              Text('${c.ratio.toStringAsFixed(1)} : 1  (min ${c.need})', style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
            ]),
          ),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            key: const ValueKey('design-preview'),
            onPressed: _busy ? null : () => startNightPreview(s),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Önizlə (yalnız bu cihaz)'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('design-save'),
            onPressed: _busy || notReady ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Yadda saxla'),
          ),
          FilledButton.icon(
            key: const ValueKey('design-publish'),
            onPressed: _busy || notReady ? null : _publish,
            icon: const Icon(Icons.public),
            label: const Text('Yayımla'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('design-restore'),
            onPressed: _busy || notReady || pub?.hasPrevious != true ? null : _restore,
            icon: const Icon(Icons.undo),
            label: const Text('Əvvəlki temaya qayıt'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('design-reset'),
            onPressed: _busy || notReady ? null : _reset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Sıfırla (Klassik)'),
          ),
        ]),
      ],
    );
  }
}

/// One colour: swatch (opens the picker) + HEX field.
class _ColorRow extends StatefulWidget {
  final String colorKey, label;
  final Color color;
  final ValueChanged<Color> onChanged;
  const _ColorRow({super.key, required this.colorKey, required this.label, required this.color, required this.onChanged});

  @override
  State<_ColorRow> createState() => _ColorRowState();
}

class _ColorRowState extends State<_ColorRow> {
  late final _ctrl = TextEditingController(text: hexOf(widget.color));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          InkWell(
            key: ValueKey('design-swatch-${widget.colorKey}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final c = await showDialog<Color>(context: context, builder: (_) => ColorPickerDialog(initial: widget.color, title: widget.label));
              if (c != null) widget.onChanged(c);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.label, style: TextStyle(color: AppColors.text, fontSize: 14))),
          SizedBox(
            width: 112,
            child: TextField(
              key: ValueKey('design-hex-${widget.colorKey}'),
              controller: _ctrl,
              maxLength: 7,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]'))],
              decoration: const InputDecoration(isDense: true, counterText: ''),
              onSubmitted: (v) {
                final c = parseHex(v);
                if (c != null) widget.onChanged(c);
              },
              onChanged: (v) {
                final c = parseHex(v);
                if (c != null && v.replaceAll('#', '').length == 6) widget.onChanged(c);
              },
            ),
          ),
        ]),
      );
}

class _LevelRow extends StatelessWidget {
  final String label, sliderKey;
  final double value;
  final ValueChanged<double> onChanged;
  const _LevelRow({required this.label, required this.sliderKey, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(color: AppColors.text, fontSize: 14))),
          Expanded(
            flex: 4,
            child: Slider(key: ValueKey(sliderKey), value: value, onChanged: onChanged),
          ),
          SizedBox(width: 44, child: Text('${(value * 100).round()}%', style: TextStyle(color: AppColors.textSoft, fontSize: 13))),
        ]),
      );
}

/// Visual colour picker: hue, saturation, brightness + HEX.
class ColorPickerDialog extends StatefulWidget {
  final Color initial;
  final String title;
  const ColorPickerDialog({super.key, required this.initial, required this.title});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late HSVColor _c = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _c.toColor();
    Widget slider(String label, double v, double max, ValueChanged<double> f) => Row(children: [
          SizedBox(width: 74, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(child: Slider(value: v, max: max, onChanged: f)),
        ]);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            key: const ValueKey('picker-swatch'),
            height: 56,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            alignment: Alignment.center,
            child: Text(hexOf(color), style: TextStyle(color: contrastRatio(Colors.white, color) > 3 ? Colors.white : Colors.black)),
          ),
          const SizedBox(height: 8),
          Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: LinearGradient(colors: [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]),
            ),
          ),
          slider('Ton', _c.hue, 360, (v) => setState(() => _c = _c.withHue(v))),
          slider('Doyma', _c.saturation, 1, (v) => setState(() => _c = _c.withSaturation(v))),
          slider('Parlaqlıq', _c.value, 1, (v) => setState(() => _c = _c.withValue(v))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ləğv et')),
        FilledButton(key: const ValueKey('picker-ok'), onPressed: () => Navigator.pop(context, color), child: const Text('Seç')),
      ],
    );
  }
}

/// A small phone screen drawn in [spec]'s colours (the app itself keeps
/// its colours until Önizlə / Yayımla).
class NightThemePreview extends StatelessWidget {
  final NightThemeSpec spec;
  const NightThemePreview({super.key, required this.spec});

  @override
  Widget build(BuildContext context) {
    final s = spec;
    final bars = Color.lerp(s.background, s.button, s.gradient * 0.22)!;
    final glow = s.glow > 0 ? [BoxShadow(color: s.button.withValues(alpha: 0.45 * s.glow), blurRadius: 18 * s.glow, offset: const Offset(0, 4))] : null;
    Widget chip(String t, IconData i, bool on) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on ? s.button : s.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? s.accent : s.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 16, color: on ? Colors.white : s.text),
            const SizedBox(width: 6),
            Text(t, style: TextStyle(color: on ? Colors.white : s.text, fontSize: 12.5)),
          ]),
        );
    return Center(
      child: Container(
        key: const ValueKey('design-preview-panel'),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(color: s.background, borderRadius: BorderRadius.circular(22), border: Border.all(color: s.line)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: bars,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              Icon(Icons.local_shipping, color: s.accent),
              const SizedBox(width: 8),
              Text('TIR ', style: TextStyle(color: s.text, fontSize: 18, fontWeight: FontWeight.w600)),
              Text('Bazarı', style: TextStyle(color: s.accent, fontSize: 18, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.favorite_border, color: s.text),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: s.line), boxShadow: glow),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Al və sat', style: TextStyle(color: s.text, fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text('TIR, qoşqu və digər elanlar', style: TextStyle(color: s.textSoft, fontSize: 12)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: s.button, borderRadius: BorderRadius.circular(12), boxShadow: glow),
                    child: const Text('Elan yerləşdir', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                chip('TIR', Icons.local_shipping, true),
                chip('Orta yük', Icons.fire_truck, false),
                chip('Qoşqu', Icons.rv_hookup, false),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: s.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: s.line)),
                child: Row(children: [
                  Icon(Icons.search, color: s.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Marka, model, şəhər…', style: TextStyle(color: s.textSoft, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          Container(
            color: bars,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (final (i, on) in [
                (Icons.local_shipping_outlined, false),
                (Icons.work_outline, false),
                (Icons.storefront, true),
                (Icons.chat_bubble_outline, false),
                (Icons.person_outline, false),
              ])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: on ? s.accent.withValues(alpha: 0.16) : null, borderRadius: BorderRadius.circular(14)),
                  child: Icon(i, size: 20, color: on ? s.accent : s.textSoft),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

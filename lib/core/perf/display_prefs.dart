import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../autofix/autofix_platform_stub.dart' if (dart.library.js_interop) '../autofix/autofix_platform_web.dart'
    as platform;
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

/// "FPS artırıcı" (owner, 16.11.2026: "1x 2x 3x və 30 / 40 / 50–60 fps"):
/// how sharp the app draws and how often, chosen in Ayarlar → Görünüş, kept
/// on this device. web/index.html applies both BEFORE the app starts (so a
/// change counts from the next opening) and writes what the screen really is
/// (native_dpr, refresh_hz).
class DisplayPrefs {
  static const scaleKey = 'render_scale';
  static const fpsKey = 'fps_cap';
  static const nativeKey = 'native_dpr';
  static const hzKey = 'refresh_hz';
  static const oldAdminKey = 'perf_render2';

  /// The screen's own pixel ratio (1, 2, 3 …).
  final double nativeDpr;

  /// The screen's refresh rate (60 / 120), 0 = not measured yet.
  final int refreshHz;

  /// 1 / 2 / 3; 0 = the screen's own.
  final int scale;

  /// 30 / 40; 0 = as fast as the phone allows.
  final int fpsCap;

  const DisplayPrefs({this.nativeDpr = 1, this.refreshHz = 0, this.scale = 0, this.fpsCap = 0});

  /// What this visit uses (for reports).
  static DisplayPrefs current = const DisplayPrefs();

  int get nativeStep => nativeDpr.round().clamp(1, 3);

  /// The sharpness the app draws at now.
  int get effectiveScale => scale >= 1 && scale < nativeStep ? scale : nativeStep;

  /// 1x … the screen's own (a 2x phone: 1x · 2x); none on a 1x screen.
  List<int> get scaleChoices => nativeStep <= 1 ? const [] : [for (var s = 1; s <= nativeStep; s++) s];

  /// 30 · (40 only on a 90 Hz+ screen, where it is even) · Maks.
  List<int> get fpsChoices => [30, if (refreshHz >= 90) 40, 0];

  /// "scale=2x fps=30" for the scroll reports.
  String get summary => 'scale=${effectiveScale}x fps=${fpsCap == 0 ? 'max' : fpsCap}';

  static Future<DisplayPrefs> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      num? n(String k) {
        final v = p.get(k);
        return v is num ? v : num.tryParse('$v');
      }

      var scale = (n(scaleKey) ?? 0).toInt();
      if (scale == 0 && p.getBool(oldAdminKey) == true) scale = 2;
      return current = DisplayPrefs(
        nativeDpr: (n(nativeKey) ?? 1).toDouble(),
        refreshHz: (n(hzKey) ?? 0).toInt(),
        scale: scale,
        fpsCap: (n(fpsKey) ?? 0).toInt(),
      );
    } catch (_) {
      return current;
    }
  }

  static Future<void> saveScale(int v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(scaleKey, v);
      await p.remove(oldAdminKey);
    } catch (_) {}
  }

  static Future<void> saveFps(int v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(fpsKey, v);
    } catch (_) {}
  }
}

/// Ayarlar → Görünüş: "Görüntü dəqiqliyi" 1x · 2x · 3x and "Kadr sürəti"
/// 30 · (40) · Maks, then "İndi yenidən aç" once something changed.
class DisplaySpeedSettings extends StatefulWidget {
  final AppStrings s;
  const DisplaySpeedSettings({super.key, required this.s});

  @override
  State<DisplaySpeedSettings> createState() => _DisplaySpeedSettingsState();
}

class _DisplaySpeedSettingsState extends State<DisplaySpeedSettings> {
  DisplayPrefs? _p;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    DisplayPrefs.load().then((p) {
      if (mounted) setState(() => _p = p);
    });
  }

  Widget _label(String text) =>
      Text(text, style: TextStyle(color: AppColors.textSoft, fontSize: 13, fontWeight: FontWeight.w400));

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final s = widget.s;
    if (p == null) return const SizedBox.shrink();
    final scaleNow = p.scale >= 1 ? p.scale.clamp(1, p.nativeStep) : p.nativeStep;
    final fpsNow = p.fpsChoices.contains(p.fpsCap) ? p.fpsCap : 0;
    return Padding(
      key: const ValueKey('display-speed'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.scaleChoices.isNotEmpty) ...[
          Center(child: _label(s.t('display_res_title'))),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const ValueKey('display-scale'),
            segments: [
              for (final v in p.scaleChoices) ButtonSegment(value: v, label: Text('${v}x')),
            ],
            selected: {scaleNow},
            showSelectedIcon: false,
            onSelectionChanged: (v) async {
              await DisplayPrefs.saveScale(v.first);
              final n = await DisplayPrefs.load();
              if (mounted) setState(() => (_p = n, _changed = true));
            },
          ),
          const SizedBox(height: 6),
          Text(s.t(scaleNow == 1 ? 'display_res_note_1x' : 'display_res_note'),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
          const SizedBox(height: 14),
        ],
        Center(child: _label(s.t('display_fps_title'))),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          key: const ValueKey('display-fps'),
          segments: [
            for (final v in p.fpsChoices)
              ButtonSegment(value: v, label: Text(v == 0 ? s.t('display_fps_max') : '$v FPS')),
          ],
          selected: {fpsNow},
          showSelectedIcon: false,
          onSelectionChanged: (v) async {
            await DisplayPrefs.saveFps(v.first);
            final n = await DisplayPrefs.load();
            if (mounted) setState(() => (_p = n, _changed = true));
          },
        ),
        const SizedBox(height: 6),
        Text(s.t(fpsNow == 0 ? 'display_fps_note_max' : 'display_fps_note_cap'),
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
        if (_changed) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('display-restart'),
            onPressed: platform.reloadPage,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(s.t('display_restart_now')),
          ),
          const SizedBox(height: 4),
          Text(s.t('display_restart_note'),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
        ],
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_widgets.dart';

/// "TIR parkı əlavə et" after the place is chosen on the map: name, city,
/// amenities, a note. Before saving, the parks around the place are shown
/// (the same park is not added twice); closer than 60 m is refused.
/// Returns true when the park was sent (it then waits for approval).
class TirParkAddSheet extends ConsumerStatefulWidget {
  final double lat, lng;
  final AppStrings s;
  const TirParkAddSheet({super.key, required this.lat, required this.lng, required this.s});

  @override
  ConsumerState<TirParkAddSheet> createState() => _TirParkAddSheetState();
}

class _TirParkAddSheetState extends ConsumerState<TirParkAddSheet> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _note = TextEditingController();
  final _amenities = <String>{};
  List<NearbyPark>? _nearby;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkNearby();
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _checkNearby() async {
    try {
      final list = await ref.read(tirParkRepositoryProvider).near(widget.lat, widget.lng);
      if (mounted) setState(() => _nearby = list);
    } catch (_) {
      if (mounted) setState(() => _nearby = const []);
    }
  }

  bool get _tooClose => (_nearby ?? const []).any((p) => p.distanceM < kTirParkDuplicateM);

  Future<void> _save() async {
    final s = widget.s;
    if (_name.text.trim().length < 2) {
      setState(() => _error = s.t('tp_name_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tirParkRepositoryProvider).add(
            name: _name.text.trim(),
            lat: widget.lat,
            lng: widget.lng,
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            amenities: [for (final a in kTirParkAmenities) if (_amenities.contains(a)) a],
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on TirParkRefused catch (e) {
      setState(() => _error = s.t(switch (e.reason) {
            'duplicate_nearby' => 'tp_err_duplicate',
            'too_many' => 'tp_err_too_many',
            _ => 'tp_err_generic',
          }));
    } on TirParkNotReady {
      setState(() => _error = s.t('tp_not_ready'));
    } catch (_) {
      setState(() => _error = s.t('tp_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final nearby = _nearby;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(s.t('tp_add_title'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 4),
            Text('${widget.lat.toStringAsFixed(5)}, ${widget.lng.toStringAsFixed(5)}',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            const SizedBox(height: 12),
            // Parks already around this place.
            if (nearby == null)
              const LinearProgressIndicator()
            else if (nearby.isNotEmpty)
              Container(
                key: const ValueKey('tp-nearby'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_tooClose ? AppColors.danger : AppColors.promoVip).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: (_tooClose ? AppColors.danger : AppColors.promoVip).withValues(alpha: 0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_tooClose ? s.t('tp_err_duplicate') : s.t('tp_nearby_warn'),
                      style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
                  const SizedBox(height: 6),
                  for (final p in nearby.take(5))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• ${p.name} — ${p.distanceM} m${p.status == 'pending' ? ' (${s.t('tp_pending')})' : ''}',
                        style: TextStyle(fontSize: 13.5, color: AppColors.textSoft),
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('tp-name'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(labelText: s.t('tp_name'), counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('tp-city'),
              controller: _city,
              maxLength: 80,
              decoration: InputDecoration(labelText: s.t('tp_city'), counterText: ''),
            ),
            const SizedBox(height: 14),
            Text(s.t('tp_amenities'), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in kTirParkAmenities)
                FilterChip(
                  key: ValueKey('tp-am-$a'),
                  avatar: Icon(tirParkAmenityIcon(a), size: 16),
                  label: Text(s.t('tp_am_$a')),
                  selected: _amenities.contains(a),
                  onSelected: (on) => setState(() => on ? _amenities.add(a) : _amenities.remove(a)),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('tp-note'),
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s.t('tp_note'), counterText: ''),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const ValueKey('tp-error'), style: TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 14),
            Text(s.t('tp_add_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('tp-save'),
              onPressed: _busy || _tooClose || nearby == null ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(nearby != null && nearby.isNotEmpty ? s.t('tp_add_anyway') : s.t('tp_add_send')),
            ),
          ]),
        ),
      ),
    );
  }
}

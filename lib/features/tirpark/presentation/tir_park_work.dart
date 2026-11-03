import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_owner_panel.dart';

/// Profil → "Park işçisiyəm" (owner, 03.11.2026, 0087; picture "İşçi
/// profili"): the parks I work at — trucks in by their plate, search,
/// time and money so far, "Çıxış". Not working anywhere yet → join with
/// the invitation code the park's owner gave (accepted with my own
/// account; nobody is bound automatically).
class TirParkWorkScreen extends ConsumerStatefulWidget {
  const TirParkWorkScreen({super.key});

  @override
  ConsumerState<TirParkWorkScreen> createState() => _TirParkWorkScreenState();
}

class _TirParkWorkScreenState extends ConsumerState<TirParkWorkScreen> {
  String? _parkId;
  bool _join = false;

  Future<void> _pick(List<TirParkWorkPlace> parks) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final p in parks)
            ListTile(
              key: ValueKey('tpw-park-${p.id}'),
              leading: const Icon(Icons.local_parking),
              title: Text(p.name),
              onTap: () => Navigator.of(ctx).pop(p.id),
            ),
        ]),
      ),
    );
    if (id != null && mounted) setState(() => _parkId = id);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final async = ref.watch(myWorkParksProvider);
    final parks = async.valueOrNull ?? const <TirParkWorkPlace>[];
    if (async.isLoading && !async.hasValue) {
      return Scaffold(appBar: AppBar(title: Text(s.t('tpw_title'))), body: const Center(child: CircularProgressIndicator()));
    }
    if (parks.isEmpty || _join) {
      return Scaffold(
        appBar: AppBar(title: Text(s.t('tpw_join_title'))),
        body: _Join(
          s: s,
          onJoined: () {
            ref.invalidate(myWorkParksProvider);
            setState(() => _join = false);
          },
        ),
      );
    }
    final place = parks.firstWhere((p) => p.id == _parkId, orElse: () => parks.first);
    // The cars list needs only the park's id and name.
    final park = TirPark(id: place.id, name: place.name, lat: 0, lng: 0, city: place.city, status: 'approved');
    void refresh() {
      ref.invalidate(tirParkSummaryProvider(park.id));
      ref.invalidate(tirParkParkedProvider(park.id));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('tpw_title')),
        actions: [
          IconButton(
            key: const ValueKey('tpw-join-more'),
            tooltip: s.t('tpw_join_title'),
            onPressed: () => setState(() => _join = true),
            icon: const Icon(Icons.group_add_outlined),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: const ValueKey('tpw-park'),
              borderRadius: BorderRadius.circular(14),
              onTap: parks.length > 1 ? () => _pick(parks) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(children: [
                  Icon(Icons.location_on, color: AppColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(place.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                  if (parks.length > 1) Icon(Icons.chevron_right, color: AppColors.textSoft),
                ]),
              ),
            ),
          ),
        ),
        Expanded(child: TirParkCars(key: ValueKey('tpw-cars-${park.id}'), park: park, s: s, onChanged: refresh)),
      ]),
    );
  }
}

/// The invitation code → the park's name → "Qəbul et".
class _Join extends ConsumerStatefulWidget {
  final AppStrings s;
  final VoidCallback onJoined;
  const _Join({required this.s, required this.onJoined});

  @override
  ConsumerState<_Join> createState() => _JoinState();
}

class _JoinState extends ConsumerState<_Join> {
  final _code = TextEditingController();
  String? _park;
  String? _error;
  bool _busy = false;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _err(Object e) => switch (e) {
        TirParkRefused(reason: 'invalid_code') => 'tpw_err_code',
        TirParkRefused(reason: 'own_park') => 'tpw_err_own',
        TirParkRefused(reason: 'too_many_attempts') => 'tpm_err_attempts',
        _ => 'tpb_err_generic',
      };

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _error = null;
      _park = null;
    });
    try {
      final name = await ref.read(tirParkRepositoryProvider).invitePreview(_code.text.trim());
      if (mounted) setState(() => _park = name);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final name = await ref.read(tirParkRepositoryProvider).inviteAccept(_code.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpw_joined', {'park': name}))));
      widget.onJoined();
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
        Text(s.t('tpw_join_hint'), style: TextStyle(color: AppColors.textSoft, height: 1.35)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('tpw-code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          maxLength: 12,
          onChanged: (_) {
            if (_park != null || _error != null) {
              setState(() {
                _park = null;
                _error = null;
              });
            }
          },
          style: const TextStyle(letterSpacing: 3),
          decoration: InputDecoration(labelText: s.t('tpw_code'), counterText: ''),
        ),
        if (_error != null) Text(s.t(_error!), key: const ValueKey('tpw-error'), style: TextStyle(color: AppColors.danger)),
        const SizedBox(height: 10),
        if (_park == null)
          FilledButton(
            key: const ValueKey('tpw-check'),
            onPressed: _busy ? null : _check,
            child: Text(s.t('tpw_check')),
          )
        else ...[
          Container(
            key: const ValueKey('tpw-preview'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.online.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.online.withValues(alpha: 0.4)),
            ),
            child: Text(s.t('tpw_preview', {'park': _park!}), style: TextStyle(color: AppColors.text, height: 1.35)),
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('tpw-accept'),
            onPressed: _busy ? null : _accept,
            child: Text(s.t('tpw_accept')),
          ),
        ],
      ]);
}

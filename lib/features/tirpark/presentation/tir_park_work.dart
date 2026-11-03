import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_owner_panel.dart';

/// The 8-character invitation code from whatever was pasted (owner,
/// 03.11.2026): the code alone, or a whole message such as "FreightLink: …
/// → kod: K7M2P9QX". Takes the last 8-character code-like word; otherwise
/// the letters and digits as typed.
String tirParkInviteCode(String raw) {
  final up = raw.toUpperCase();
  final words = RegExp(r'(?<![A-Z0-9])[A-Z2-9]{8}(?![A-Z0-9])').allMatches(up).map((m) => m.group(0)!).toList();
  if (words.isNotEmpty) return words.last;
  final plain = up.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return plain.length > 12 ? plain.substring(plain.length - 8) : plain;
}

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
    final all = async.valueOrNull ?? const <TirParkWorkPlace>[];
    // Only parks whose owner approved me (0088); the others wait or said no.
    final parks = [for (final p in all) if (p.status == 'active') p];
    final waiting = [for (final p in all) if (p.status == 'pending') p];
    final rejected = [for (final p in all) if (p.status == 'rejected') p];
    if (async.isLoading && !async.hasValue) {
      return Scaffold(appBar: AppBar(title: Text(s.t('tpw_title'))), body: const Center(child: CircularProgressIndicator()));
    }
    if (parks.isEmpty) {
      Widget box(String key, IconData icon, Color color, String text) => Container(
            key: ValueKey(key),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: AppColors.text, height: 1.35))),
            ]),
          );
      final onlyWaiting = waiting.isNotEmpty;
      return Scaffold(
        appBar: AppBar(title: Text(s.t(onlyWaiting ? 'tpw_title' : 'tpw_join_title'))),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myWorkParksProvider),
          child: ListView(padding: EdgeInsets.zero, children: [
            for (final p in waiting) box('tpw-waiting-${p.id}', Icons.hourglass_top, AppColors.promoVip, s.t('tpw_waiting', {'park': p.name})),
            if (parks.isEmpty)
              for (final p in rejected) box('tpw-rejected-${p.id}', Icons.block, AppColors.danger, s.t('tpw_rejected', {'park': p.name})),
            if (onlyWaiting)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: OutlinedButton.icon(
                  key: const ValueKey('tpw-refresh'),
                  onPressed: () => ref.invalidate(myWorkParksProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(s.t('tpw_refresh')),
                ),
              )
            else
              _Join(
                s: s,
                onJoined: () => ref.invalidate(myWorkParksProvider),
              ),
          ]),
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
        // No "join another park" here (owner, 03.11.2026): an approved worker
        // stays where the park's owner put him; only the owner takes him off.
        title: Text(s.t('tpw_title')),
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
  // Name and surname (owner, 03.11.2026): the owner sees who asks.
  final _name = TextEditingController();
  String? _park;
  String? _error;
  bool _busy = false;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  String _err(Object e) => switch (e) {
        TirParkRefused(reason: 'invalid_code') => 'tpw_err_code',
        TirParkRefused(reason: 'own_park') => 'tpw_err_own',
        TirParkRefused(reason: 'name_required') => 'tpw_err_name',
        TirParkRefused(reason: 'already_worker') => 'tpw_err_already',
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
      final name = await ref.read(tirParkRepositoryProvider).invitePreview(tirParkInviteCode(_code.text));
      if (mounted) setState(() => _park = name);
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Ad Soyad": two words at least (the server checks the same).
  static bool fullNameOk(String v) => RegExp(r'^\S+\s+\S+').hasMatch(v.trim()) && v.trim().length >= 3 && v.trim().length <= 80;

  Future<void> _accept() async {
    if (!fullNameOk(_name.text)) {
      setState(() => _error = 'tpw_err_name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final park = await ref.read(tirParkRepositoryProvider).inviteAccept(tirParkInviteCode(_code.text), _name.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpw_sent', {'park': park}))));
      widget.onJoined();
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('tpw_join_hint'), style: TextStyle(color: AppColors.textSoft, height: 1.35)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('tpw-code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          // A pasted message is cut down to its code at once.
          onChanged: (v) {
            final code = tirParkInviteCode(v);
            if (code != v && code.length == 8) {
              _code.value = TextEditingValue(text: code, selection: TextSelection.collapsed(offset: code.length));
            }
            if (_park != null || _error != null) {
              setState(() {
                _park = null;
                _error = null;
              });
            }
            // A whole code pasted / typed → the park's name at once (owner, 03.11.2026).
            if (code.length == 8 && !_busy) _check();
          },
          style: const TextStyle(letterSpacing: 3),
          decoration: InputDecoration(labelText: s.t('tpw_code'), counterText: ''),
        ),
        if (_error != null) Text(s.t(_error!), key: const ValueKey('tpw-error'), style: TextStyle(color: AppColors.danger)),
        const SizedBox(height: 10),
        if (_park != null) ...[
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
        ],
        // Name and surname: always on the form, right under the code (owner, 03.11.2026).
        TextField(
          key: const ValueKey('tpw-name'),
          controller: _name,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          onChanged: (_) {
            if (_error == 'tpw_err_name') setState(() => _error = null);
          },
          decoration: InputDecoration(labelText: s.t('tpw_name'), hintText: s.t('tpw_name_hint'), counterText: ''),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const ValueKey('tpw-accept'),
          onPressed: _busy ? null : _accept,
          child: Text(s.t('tpw_send')),
        ),
        if (_park == null)
          TextButton(
            key: const ValueKey('tpw-check'),
            onPressed: _busy ? null : _check,
            child: Text(s.t('tpw_check')),
          ),
      ]));
}

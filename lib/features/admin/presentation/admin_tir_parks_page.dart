import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../tirpark/data/tir_park_repository.dart';
import '../../tirpark/domain/tir_park.dart';

/// Admin → TIRPark (owner, 31.10.2026, 0077): parks added by users wait
/// here ("Təsdiq gözləyir") until an admin approves them; reject / hide
/// keep the record (nothing is deleted). Checked and logged on the server.
class AdminTirParksPage extends ConsumerStatefulWidget {
  const AdminTirParksPage({super.key});

  @override
  ConsumerState<AdminTirParksPage> createState() => _AdminTirParksPageState();
}

const _statusLabel = {'pending': 'Təsdiq gözləyir', 'approved': 'Təsdiqlənib', 'rejected': 'Rədd edilib', 'hidden': 'Gizlədilib'};

class _AdminTirParksPageState extends ConsumerState<AdminTirParksPage> {
  String _filter = 'pending';
  String? _busy;

  Future<void> _set(TirPark p, String status) async {
    setState(() => _busy = p.id);
    try {
      await ref.read(tirParkRepositoryProvider).setStatus(p.id, status);
      ref.invalidate(adminTirParksProvider);
      ref.invalidate(tirParksProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is TirParkNotReady ? 'Əvvəlcə Supabase-də SQL 0077 işə salınmalıdır.' : 'Alınmadı. Yenidən cəhd edin.')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminTirParksProvider);
    final all = async.valueOrNull ?? const <TirPark>[];
    final list = _filter == 'all' ? all : [for (final p in all) if (p.status == _filter) p];
    final pending = all.where((p) => p.isPending).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('TIRPark — parklar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 4),
        Text('İstifadəçilərin əlavə etdiyi parklar təsdiqdən sonra hamıya görünür. Rədd / gizlət heç nəyi silmir.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, label) in [
            ('pending', 'Təsdiq gözləyir ($pending)'),
            ('approved', 'Təsdiqlənib'),
            ('rejected', 'Rədd edilib'),
            ('hidden', 'Gizlədilib'),
            ('all', 'Hamısı'),
          ])
            ChoiceChip(key: ValueKey('atp-f-$k'), label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
        ]),
        const SizedBox(height: 12),
        if (async.isLoading && !async.hasValue) const Center(child: CircularProgressIndicator()),
        if (async.error is TirParkNotReady) Text('SQL 0077 hələ işə salınmayıb.', style: TextStyle(color: AppColors.danger)),
        if (async.hasValue && list.isEmpty) Text('Burada park yoxdur.', style: TextStyle(color: AppColors.textSoft)),
        for (final p in list)
          Card(
            key: ValueKey('atp-${p.id}'),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text))),
                  Text(_statusLabel[p.status] ?? p.status,
                      style: TextStyle(fontSize: 12.5, color: p.isApproved ? AppColors.online : AppColors.promoVip)),
                ]),
                const SizedBox(height: 4),
                Text('${p.city ?? '—'} · ${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}',
                    style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                if (p.amenities.isNotEmpty) Text(p.amenities.join(', '), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                if ((p.note ?? '').isNotEmpty) Text(p.note!, style: TextStyle(fontSize: 13, color: AppColors.text)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (!p.isApproved)
                    FilledButton(
                      key: ValueKey('atp-approve-${p.id}'),
                      onPressed: _busy == p.id ? null : () => _set(p, 'approved'),
                      child: const Text('Təsdiqlə'),
                    ),
                  if (p.status != 'rejected')
                    OutlinedButton(
                      key: ValueKey('atp-reject-${p.id}'),
                      onPressed: _busy == p.id ? null : () => _set(p, 'rejected'),
                      child: const Text('Rədd et'),
                    ),
                  if (p.status != 'hidden')
                    OutlinedButton(
                      key: ValueKey('atp-hide-${p.id}'),
                      onPressed: _busy == p.id ? null : () => _set(p, 'hidden'),
                      child: const Text('Gizlət'),
                    ),
                ]),
              ]),
            ),
          ),
      ],
    );
  }
}

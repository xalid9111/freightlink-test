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
const _managerLabel = {'pending': 'gözləyir', 'approved': 'təsdiqlənib', 'rejected': 'rədd edilib'};
const _bookingLabel = {
  'pending_payment': 'Ödəniş gözləyir',
  'payment_review': 'Ödəniş yoxlanılır',
  'confirmed': 'Təsdiqlənib',
  'checked_in': 'Parka daxil olub',
  'completed': 'Tamamlanıb',
  'cancelled': 'Ləğv edilib',
  'expired': 'Vaxtı bitib',
  'refund_pending': 'Qaytarılma gözləyir',
  'refunded': 'Qaytarılıb',
};

class _AdminTirParksPageState extends ConsumerState<AdminTirParksPage> {
  String _filter = 'pending';
  String? _busy;

  // Manager application (0079): approve / reject; logged on the server.
  Future<void> _manager(TirPark p, String status) async {
    setState(() => _busy = p.id);
    try {
      await ref.read(tirParkRepositoryProvider).adminManagerSet(p.id, status);
      ref.invalidate(adminTirParksProvider);
      ref.invalidate(tirParksProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is TirParkNotReady ? 'Əvvəlcə Supabase-də SQL 0079 işə salınmalıdır.' : 'Alınmadı. Yenidən cəhd edin.')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

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
        // "Park işlədirəm" requests (owner, 03.11.2026, 0086): only a name.
        const _OwnerRequests(),
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
                // Manager application and bookings (0079).
                if (p.managerId != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Rəhbər müraciəti: ${_managerLabel[p.managerStatus] ?? p.managerStatus ?? '—'} · tutum ${p.capacity ?? '—'} · '
                    'boş ${p.bookable ?? '—'} · ${p.price?.toStringAsFixed(2) ?? '—'} ${p.currency} / ${p.priceUnit == 'day' ? 'gün' : 'saat'}'
                    '${(p.phone ?? '').isEmpty ? '' : ' · ${p.phone}'}${(p.hours ?? '').isEmpty ? '' : ' · ${p.hours}'}',
                    key: ValueKey('atp-mgr-${p.id}'),
                    style: TextStyle(fontSize: 13, color: AppColors.text),
                  ),
                  if ((p.address ?? '').isNotEmpty) Text(p.address!, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (p.managerStatus != 'approved')
                      FilledButton(
                        key: ValueKey('atp-mgr-ok-${p.id}'),
                        onPressed: _busy == p.id ? null : () => _manager(p, 'approved'),
                        child: const Text('Rəhbəri təsdiqlə'),
                      ),
                    if (p.managerStatus != 'rejected')
                      OutlinedButton(
                        key: ValueKey('atp-mgr-no-${p.id}'),
                        onPressed: _busy == p.id ? null : () => _manager(p, 'rejected'),
                        child: const Text('Rəhbər müraciətini rədd et'),
                      ),
                  ]),
                  if (p.managerStatus == 'approved') _AdminBookings(parkId: p.id),
                ],
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

/// A managed park's bookings for the admin; the status can be changed
/// (checked and logged on the server, 0079). Refund states are not offered:
/// the payment provider has no refunds yet.
class _AdminBookings extends ConsumerWidget {
  final String parkId;
  const _AdminBookings({required this.parkId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminParkBookingsProvider(parkId));
    final list = async.valueOrNull ?? const <TirParkBooking>[];
    return ExpansionTile(
      key: ValueKey('atp-bookings-$parkId'),
      tilePadding: EdgeInsets.zero,
      title: Text('Rezervasiyalar (${list.length})', style: TextStyle(fontSize: 14, color: AppColors.text)),
      children: [
        if (async.isLoading && !async.hasValue) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
        for (final b in list)
          ListTile(
            key: ValueKey('atp-b-${b.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text('${b.bookingNo} · ${b.trucks} TIR${(b.plate ?? '').isEmpty ? '' : ' · ${b.plate}'} · '
                '${b.amount.toStringAsFixed(2)} ${b.currency}${b.paidMode == 'test' ? ' · TEST' : ''}'),
            subtitle: Text('${b.startAt.toString().substring(0, 16)} → ${b.endAt.toString().substring(0, 16)} · '
                '${_bookingLabel[b.shownStatus] ?? b.shownStatus}'),
            trailing: PopupMenuButton<String>(
              tooltip: 'Statusu dəyiş',
              onSelected: (st) async {
                try {
                  await ref.read(tirParkRepositoryProvider).adminBookingSet(b.id, st);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(e is TirParkRefused && e.reason == 'not_paid' ? 'Ödənilməmiş rezervasiya təsdiqlənə bilməz.' : 'Alınmadı.')));
                  }
                }
                ref.invalidate(adminParkBookingsProvider(parkId));
              },
              itemBuilder: (_) => [
                for (final st in ['payment_review', 'confirmed', 'checked_in', 'completed', 'cancelled', 'expired'])
                  if (st != b.status) PopupMenuItem(value: st, child: Text(_bookingLabel[st]!)),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Park işlədirəm": the owner wrote only the park's name; once approved his
/// owner panel opens and he puts the park on the map himself.
class _OwnerRequests extends ConsumerStatefulWidget {
  const _OwnerRequests();

  @override
  ConsumerState<_OwnerRequests> createState() => _OwnerRequestsState();
}

class _OwnerRequestsState extends ConsumerState<_OwnerRequests> {
  String? _busy;

  Future<void> _set(String id, String status) async {
    setState(() => _busy = id);
    try {
      await ref.read(tirParkRepositoryProvider).adminOwnerRequestSet(id, status);
      ref.invalidate(adminOwnerRequestsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is TirParkNotReady ? 'Əvvəlcə Supabase-də SQL 0086 işə salınmalıdır.' : 'Alınmadı. Yenidən cəhd edin.')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminOwnerRequestsProvider);
    final list = async.valueOrNull ?? const <Map<String, dynamic>>[];
    if (async.hasError) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(async.error is TirParkNotReady ? '"Park işlədirəm" müraciətləri: SQL 0086 işə salınmayıb.' : 'Müraciətlər yüklənmədi.',
            style: TextStyle(color: AppColors.textSoft)),
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();
    const label = {'pending': 'Təsdiq gözləyir', 'approved': 'Təsdiqlənib', 'rejected': 'Rədd edilib'};
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('"Park işlədirəm" müraciətləri', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 6),
        for (final r in list)
          Card(
            key: ValueKey('atp-req-${r['id']}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['park_name'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                Text(
                  [
                    '${r['user_name'] ?? ''}',
                    if ('${r['user_phone'] ?? ''}'.isNotEmpty) '${r['user_phone']}',
                    if ('${r['user_email'] ?? ''}'.isNotEmpty) '${r['user_email']}',
                    label['${r['status']}'] ?? '${r['status']}',
                    if (r['status'] == 'approved') r['park_id'] == null ? 'park hələ qurulmayıb' : 'park qurulub',
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: AppColors.textSoft),
                ),
                if (r['status'] == 'pending') ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton(
                      key: ValueKey('atp-req-ok-${r['id']}'),
                      onPressed: _busy == r['id'] ? null : () => _set('${r['id']}', 'approved'),
                      child: const Text('Təsdiqlə'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      key: ValueKey('atp-req-no-${r['id']}'),
                      onPressed: _busy == r['id'] ? null : () => _set('${r['id']}', 'rejected'),
                      child: const Text('Rədd et'),
                    ),
                  ]),
                ],
              ]),
            ),
          ),
      ]),
    );
  }
}

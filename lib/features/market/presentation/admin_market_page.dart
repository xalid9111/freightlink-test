import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../admin/presentation/admin_widgets.dart';
import '../data/market_repository.dart';
import '../domain/market_models.dart';
import 'market_card.dart';

final _adminMarketProvider = FutureProvider.autoDispose.family<List<MarketListing>, MarketStatus?>((ref, st) {
  return ref.watch(marketRepositoryProvider).adminList(status: st);
});

/// Admin → Satış elanları: approve / reject / deactivate / delete, VIP
/// on / off with a duration (no payment now). Every action is checked and
/// logged on the server (admin_market_*).
class AdminMarketPage extends ConsumerStatefulWidget {
  const AdminMarketPage({super.key});

  @override
  ConsumerState<AdminMarketPage> createState() => _AdminMarketPageState();
}

class _AdminMarketPageState extends ConsumerState<AdminMarketPage> {
  MarketStatus? _status;

  static const _labels = {
    null: 'Hamısı',
    MarketStatus.pending: 'Təsdiq gözləyir',
    MarketStatus.active: 'Aktiv',
    MarketStatus.rejected: 'Rədd edilib',
    MarketStatus.inactive: 'Deaktiv',
    MarketStatus.sold: 'Satılıb',
    MarketStatus.draft: 'Qaralama',
  };

  void _reload() => ref.invalidate(_adminMarketProvider(_status));

  Future<String?> _ask(String title, {String hint = 'Səbəb (istifadəçi görəcək)'}) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, minLines: 1, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Təsdiqlə')),
        ],
      ),
    );
    final t = c.text.trim();
    c.dispose();
    return ok == true ? t : null;
  }

  Future<void> _vip(MarketListing l) async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('VIP müddəti'),
        children: [
          for (final d in const [3, 7, 14, 30])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, d), child: Text('$d gün')),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Müddətsiz')),
        ],
      ),
    );
    if (days == null || !mounted) return;
    final ok = await runAdmin(context, () => ref.read(marketRepositoryProvider).adminSetVip(l.id, true, days: days == 0 ? null : days));
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_adminMarketProvider(_status));
    final repo = ref.read(marketRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const Text('Satış elanları (TIR Bazarı)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in _labels.entries)
            ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => setState(() => _status = e.key)),
        ]),
        const SizedBox(height: 12),
        async.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text('Yüklənmədi: $e (0040_market.sql işə salınıbmı?)', style: const TextStyle(color: AppColors.danger)),
          data: (list) => list.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('Elan yoxdur.', style: TextStyle(color: AppColors.textSoft)))
              : Column(children: [
                  for (final l in list)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          InkWell(
                            onTap: () => context.pushOnce('/market/l/${l.id}'),
                            child: Row(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(width: 84, height: 60, child: MarketPhoto(url: l.cover)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('#${l.listingNo} · ${l.title}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text('${marketPrice(l.price, l.currency)} · ${l.city ?? '—'} · ${l.photos.length} şəkil · ${l.views} baxış',
                                      style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
                                  Text('Status: ${_labels[l.status]}${l.vipActive() ? ' · VIP${l.vipUntil == null ? '' : ' (${l.vipUntil!.day}.${l.vipUntil!.month})'}' : ''}',
                                      style: const TextStyle(fontSize: 12)),
                                ]),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            if (l.status != MarketStatus.active)
                              FilledButton(
                                onPressed: () async {
                                  if (await runAdmin(context, () => repo.adminSetStatus(l.id, MarketStatus.active))) _reload();
                                },
                                child: const Text('Təsdiqlə'),
                              ),
                            if (l.status == MarketStatus.pending)
                              OutlinedButton(
                                onPressed: () async {
                                  final why = await _ask('Rədd et');
                                  if (why == null || !context.mounted) return;
                                  if (await runAdmin(context, () => repo.adminSetStatus(l.id, MarketStatus.rejected, note: why))) _reload();
                                },
                                child: const Text('Rədd et'),
                              ),
                            if (l.status == MarketStatus.active)
                              OutlinedButton(
                                onPressed: () async {
                                  final why = await _ask('Deaktiv et');
                                  if (why == null || !context.mounted) return;
                                  if (await runAdmin(context, () => repo.adminSetStatus(l.id, MarketStatus.inactive, note: why))) _reload();
                                },
                                child: const Text('Deaktiv et'),
                              ),
                            if (!l.vipActive())
                              OutlinedButton.icon(onPressed: () => _vip(l), icon: const Icon(Icons.workspace_premium, size: 18), label: const Text('VIP et'))
                            else
                              OutlinedButton(
                                onPressed: () async {
                                  if (await runAdmin(context, () => repo.adminSetVip(l.id, false))) _reload();
                                },
                                child: const Text('VIP-i söndür'),
                              ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                              onPressed: () async {
                                final why = await _ask('Elanı sil', hint: 'Səbəb (jurnal üçün)');
                                if (why == null || !context.mounted) return;
                                if (await runAdmin(context, () => repo.adminDelete(l.id, reason: why))) _reload();
                              },
                              child: const Text('Sil'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                ]),
        ),
      ],
    );
  }
}

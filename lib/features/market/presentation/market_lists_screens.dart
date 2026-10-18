import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/market_models.dart';
import 'market_card.dart';
import 'market_home_screen.dart' show openNewMarketAd;
import 'market_providers.dart';

/// "Mənim elanlarım": every own ad with its state (draft, waiting for the
/// admin, published, rejected, sold).
class MyMarketListingsScreen extends ConsumerWidget {
  const MyMarketListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final async = ref.watch(myMarketListingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('mk_my_ads'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNewMarketAd(context, ref, s),
        icon: const Icon(Icons.add),
        label: Text(s.t('mk_new_ad')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myMarketListingsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(s.t('home_error_loading')))]),
          data: (list) => list.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(s.t('mk_my_empty'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final l = list[i];
                    return Material(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => context.pushOnce('/market/l/${l.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(width: 92, height: 68, child: MarketPhoto(url: l.cover)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(l.title.isEmpty ? s.t('mk_untitled') : l.title,
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                Text(marketPrice(l.price, l.currency), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Row(children: [
                                  _StatusChip(status: l.status, label: s.t('mk_state_${l.status.name}')),
                                  if (l.vipActive()) ...[const SizedBox(width: 6), const VipBadge()],
                                  const Spacer(),
                                  Icon(Icons.visibility_outlined, size: 15, color: AppColors.textSoft),
                                  const SizedBox(width: 3),
                                  Text('${l.views}', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                                ]),
                              ]),
                            ),
                            // Edit straight from the list (also on the ad page).
                            if (l.status != MarketStatus.sold)
                              IconButton(
                                key: ValueKey('mk-edit-${l.id}'),
                                tooltip: s.t('mk_edit'),
                                icon: Icon(Icons.edit_outlined, color: AppColors.accent),
                                onPressed: () => context.pushOnce('/market/edit/${l.id}'),
                              ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final MarketStatus status;
  final String label;
  const _StatusChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      MarketStatus.active => AppColors.online,
      MarketStatus.pending => AppColors.blue,
      MarketStatus.rejected || MarketStatus.inactive => AppColors.danger,
      MarketStatus.sold => kVipGold,
      MarketStatus.draft => AppColors.textSoft,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// Seçilmişlər (hearts).
class MarketFavoritesScreen extends ConsumerWidget {
  const MarketFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final async = ref.watch(marketFavoritesListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('mk_favorites'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(s.t('home_error_loading'))),
        data: (list) => list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(s.t('mk_fav_empty'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 236,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => MarketCard(l: list[i]),
              ),
      ),
    );
  }
}

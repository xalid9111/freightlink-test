import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import 'providers/cargo_media_providers.dart';
import 'widgets/cargo_card.dart';

/// "Seçilmiş yüklər" (owner, 22.10.2026, 0058): the loads I marked with
/// the heart, newest first. Only my own list; a deleted or closed load
/// is not shown.
class FavoriteCargoScreen extends ConsumerWidget {
  const FavoriteCargoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final async = ref.watch(cargoFavoritesListProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('fav_cargo_title'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(cargoFavoritesListProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [
            Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(s.t('home_error_loading')))),
          ]),
          data: (list) => list.isEmpty
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.favorite_border, size: 44, color: AppColors.textSoft),
                      const SizedBox(height: 12),
                      Text(s.t('fav_cargo_empty'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                    ]),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => CargoCard(
                    cargo: list[i],
                    strings: s,
                    compact: true,
                    // /load/: this page is above the tabs; /cargo/:id opened behind it.
                    onTap: () => context.pushOnce('/load/${list[i].id}'),
                  ),
                ),
        ),
      ),
    );
  }
}

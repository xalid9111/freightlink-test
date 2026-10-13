import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import 'providers/cargo_providers.dart';
import 'widgets/cargo_card.dart';
import '../../../core/router/safe_navigation.dart';

/// "My loads" (Profile → My loads): every load the signed-in owner has
/// posted, any status, with quick Edit. Tap a card for full details.
class MyCargoScreen extends ConsumerWidget {
  const MyCargoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final async = ref.watch(myCargoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('my_cargo_title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushOnce('/cargo/create'),
        icon: const Icon(Icons.add),
        label: Text(strings.t('home_post_cargo')),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myCargoProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(children: [
            Padding(padding: const EdgeInsets.all(24), child: Text(strings.t('home_error_loading'))),
          ]),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(strings.t('my_cargo_empty'), textAlign: TextAlign.center),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = list[i];
                final statusKey = 'shipment_status_${c.status}';
                final status = strings.t(statusKey);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CargoCard(cargo: c, strings: strings, compact: true, onTap: () => context.pushOnce('/load/${c.id}')),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Text(status == statusKey ? c.status : status,
                              style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                          const Spacer(),
                          if (const ['new', 'carrier_found', 'agreed'].contains(c.status))
                            TextButton.icon(
                              onPressed: () => context.pushOnce('/cargo-edit/${c.id}'),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: Text(strings.t('cargo_edit')),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

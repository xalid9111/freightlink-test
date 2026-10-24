import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/autofix/autofix.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/cargo_model.dart';
import 'providers/cargo_media_providers.dart';
import 'providers/cargo_providers.dart';
import 'widgets/cargo_card.dart';
import 'widgets/cargo_vip_sheet.dart';
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
                final now = DateTime.now();
                final open = c.status == 'new' && !c.isHidden;
                final listed = c.isListedOn(now);
                // Owner, 24.10.2026: Aktiv / Deaktiv / Vaxtı keçib.
                final state = !open
                    ? null
                    : listed
                        ? ('cargo_state_active', AppColors.online)
                        : c.isPaused
                            ? ('cargo_state_paused', AppColors.textSoft)
                            : ('cargo_state_expired', AppColors.danger);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CargoCard(cargo: c, strings: strings, compact: true, onTap: () => context.pushOnce('/load/${c.id}')),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          Text(status == statusKey ? c.status : status,
                              style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                          if (state != null)
                            Text('· ${strings.t(state.$1)}',
                                key: ValueKey('my-cargo-state-${c.id}'),
                                style: TextStyle(color: state.$2, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          if (open && listed)
                            TextButton.icon(
                              key: ValueKey('my-cargo-off-${c.id}'),
                              onPressed: () => _deactivate(context, ref, c),
                              icon: const Icon(Icons.pause_circle_outline, size: 18),
                              label: Text(strings.t('cargo_deactivate')),
                            ),
                          // "VIP et" on my listed load (owner, 24.10.2026, 0062).
                          if (open && listed)
                            TextButton.icon(
                              key: ValueKey('my-cargo-vip-${c.id}'),
                              onPressed: () => showCargoVipSheet(context, strings, c),
                              icon: const Icon(Icons.workspace_premium, size: 18, color: AppColors.vipGold),
                              label: Text(c.isVipAt(now) ? strings.t('mk_vip_extend') : strings.t('cargo_vip_btn')),
                            ),
                          if (open && !listed)
                            TextButton.icon(
                              key: ValueKey('my-cargo-on-${c.id}'),
                              onPressed: () => _activate(context, ref, c),
                              icon: const Icon(Icons.play_circle_outline, size: 18),
                              label: Text(strings.t('cargo_activate')),
                            ),
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

void _say(BuildContext context, String text) {
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

void _refresh(ProviderContainer c, String id) {
  c.invalidate(myCargoProvider);
  c.invalidate(marketplaceProvider);
  c.invalidate(cargoDetailProvider(id));
}

/// "Deaktiv et": the load leaves the Loads page; nothing is deleted.
Future<void> _deactivate(BuildContext context, WidgetRef ref, CargoModel c) async {
  final s = ref.read(stringsProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await ref.read(cargoMediaRepositoryProvider).pauseCargo(c.id);
    _refresh(container, c.id);
    if (context.mounted) _say(context, s.t('cargo_deactivated'));
  } catch (e, st) {
    AutoFix.instance.capture(e, st, source: 'cargo.pause');
    if (context.mounted) _say(context, s.t('error_generic'));
  }
}

/// "Aktiv et": choose the loading date, then the load is listed again.
Future<void> _activate(BuildContext context, WidgetRef ref, CargoModel c) async {
  final s = ref.read(stringsProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final picked = await showDatePicker(
    context: context,
    helpText: s.t('cargo_activate_date'),
    initialDate: c.pickupDate.isBefore(today) ? today : c.pickupDate,
    firstDate: today,
    lastDate: today.add(const Duration(days: 365)),
  );
  if (picked == null || !context.mounted) return;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await ref.read(cargoMediaRepositoryProvider).activateCargo(c, picked);
    _refresh(container, c.id);
    if (context.mounted) _say(context, s.t('cargo_activated'));
  } catch (e, st) {
    AutoFix.instance.capture(e, st, source: 'cargo.activate');
    if (context.mounted) _say(context, s.t('error_generic'));
  }
}

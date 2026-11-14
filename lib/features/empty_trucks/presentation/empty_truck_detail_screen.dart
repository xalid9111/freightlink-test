import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../repositories/profile_repository.dart';
import '../../../core/widgets/phone_hidden_note.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/guest_access.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../cargo/domain/truck_types.dart';
import '../../cargo/presentation/widgets/cargo_picture.dart';
import '../../chat/data/group_repository.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/call_options.dart';
import '../../favorites/favorites.dart';
import '../data/empty_truck_repository.dart';
import '../domain/empty_truck.dart';
import 'empty_truck_widgets.dart';

/// One empty truck ad (owner, 13.11.2026): the picture of its type, the
/// route ("Bakı → İstanbul"), where it is now, the truck, when it is free,
/// contact (call / WhatsApp sheet, Mesaj yaz). The owner: Redaktə et,
/// Dayandır / Aktiv et, Maşın doldu.
class EmptyTruckDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const EmptyTruckDetailScreen({super.key, required this.id});

  @override
  ConsumerState<EmptyTruckDetailScreen> createState() => _EmptyTruckDetailScreenState();
}

class _EmptyTruckDetailScreenState extends ConsumerState<EmptyTruckDetailScreen> {
  bool _busy = false;

  Future<void> _status(String status, AppStrings s) async {
    if (status == 'filled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(s.t('et_filled')),
          content: Text(s.t('et_filled_body')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common_cancel'))),
            FilledButton(key: const ValueKey('et-filled-confirm'), onPressed: () => Navigator.pop(c, true), child: Text(s.t('et_filled'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(emptyTruckRepositoryProvider).setStatus(widget.id, status);
      ref.invalidate(emptyTruckProvider(widget.id));
      ref.invalidate(emptyTrucksProvider);
      ref.invalidate(myEmptyTrucksProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('et_err_save'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _message(EmptyTruck t, AppStrings s) async {
    if (askSignIn(context)) return;
    setState(() => _busy = true);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(t.ownerId);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('chat_open_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final async = ref.watch(emptyTruckProvider(widget.id));
    final me = ref.watch(currentUserIdProvider);
    final owner = async.valueOrNull?.ownerId;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('et_detail_title')), actions: [
        // Bəyən: the carrier goes to Bəyəndiklərim → Profillər.
        if (owner != null && owner != me) LikeHeart(kind: FavKind.user, id: owner),
      ]),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(s.t(e is EmptyTruckNotReady ? 'et_not_ready' : 'home_error_loading'))),
        data: (t) {
          if (t == null) return Center(child: Text(s.t('et_gone')));
          final own = me != null && me == t.ownerId;
          final phone = (t.phone ?? '').trim();
          final wa = (t.whatsapp ?? '').trim();
          Widget row(IconData icon, String label, String value, {Key? key}) => Padding(
                key: key,
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: AppColors.textSoft),
                  const SizedBox(width: 10),
                  SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 15, color: AppColors.textSoft))),
                  Expanded(child: Text(value, style: TextStyle(fontSize: 17, color: AppColors.text))),
                ]),
              );
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            AspectRatio(aspectRatio: 16 / 9, child: CargoPicture(truckType: t.truckType, seed: t.id)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (own) ...[EmptyTruckStatusChip(status: t.status, strings: s), const SizedBox(height: 8)],
                Text(
                  t.routeLabel(lang, anyLabel: s.t('et_any_direction_short')),
                  key: const ValueKey('et-detail-route'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
                const SizedBox(height: 10),
                row(Icons.place_outlined, s.t('et_now_at'), t.placeLabel(lang), key: const ValueKey('et-detail-place')),
                row(Icons.flag_outlined, s.t('et_going_to'),
                    t.anyDirection || t.toCity == null ? s.t('et_any_direction') : _toLabel(t, lang)),
                row(Icons.local_shipping_outlined, s.t('et_truck'), truckTypeLabel(s, t.truckType)),
                row(Icons.scale_outlined, s.t('et_capacity'), emptyTruckTonsLabel(s, t.freeTons)),
                if (t.bodyTypes.isNotEmpty)
                  row(Icons.inventory_2_outlined, s.t('et_bodies_short'), [for (final b in t.bodyTypes) s.t('et_body_$b')].join(', ')),
                row(Icons.schedule, s.t('et_free'), emptyTruckFreeLabel(s, t, lang)),
                if ((t.note ?? '').isNotEmpty) row(Icons.notes, s.t('et_note'), t.note!),
                const SizedBox(height: 16),
                if (!own) ...[
                  if (isSignedOut())
                    FilledButton.icon(
                      key: const ValueKey('et-sign-in'),
                      onPressed: () => askSignIn(context),
                      icon: const Icon(Icons.login),
                      label: Text(s.t('guest_contact_sign_in')),
                    )
                  else ...[
                    if (phone.isNotEmpty || wa.isNotEmpty)
                      FilledButton.icon(
                        key: const ValueKey('et-call'),
                        onPressed: () => showCallOptions(context, s, phone.isNotEmpty ? phone : wa),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.accentFill),
                        icon: const Icon(Icons.phone),
                        label: Text(s.t('et_contact')),
                      )
                    // The owner hid his phone (0122).
                    else if (ref.watch(phoneHiddenProvider(t.ownerId)).valueOrNull ?? false)
                      PhoneHiddenNote(strings: s),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('et-message'),
                      onPressed: _busy ? null : () => _message(t, s),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(s.t('et_message')),
                    ),
                  ],
                ] else ...[
                  // The owner's controls.
                  OutlinedButton.icon(
                    key: const ValueKey('et-edit'),
                    onPressed: _busy ? null : () => context.pushOnce('/trucks/${t.id}/edit'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(s.t('et_edit')),
                  ),
                  const SizedBox(height: 8),
                  if (t.status != 'filled')
                    OutlinedButton.icon(
                      key: const ValueKey('et-pause'),
                      onPressed: _busy ? null : () => _status(t.isActive ? 'paused' : 'active', s),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      icon: Icon(t.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline),
                      label: Text(s.t(t.isActive ? 'et_pause' : 'et_activate')),
                    ),
                  if (t.status != 'filled') ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const ValueKey('et-filled'),
                      onPressed: _busy ? null : () => _status('filled', s),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: AppColors.accentFill),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(s.t('et_filled')),
                    ),
                  ] else
                    OutlinedButton.icon(
                      key: const ValueKey('et-reopen'),
                      onPressed: _busy ? null : () => _status('active', s),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      icon: const Icon(Icons.replay),
                      label: Text(s.t('et_activate')),
                    ),
                ],
              ]),
            ),
          ]);
        },
      ),
    );
  }

  static String _toLabel(EmptyTruck t, String lang) {
    final probe = EmptyTruck(
        id: t.id, ownerId: t.ownerId, fromCity: t.toCity!, fromCountry: t.toCountry ?? '', fromCode: t.toIso, truckType: '', freeTons: 0, createdAt: t.createdAt);
    return probe.placeLabel(lang);
  }
}

/// The owner's empty truck ads (all states), from Daşıyıcılar.
class MyEmptyTrucksScreen extends ConsumerWidget {
  const MyEmptyTrucksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final async = ref.watch(myEmptyTrucksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('et_mine_title'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('et-mine-add'),
        onPressed: () => context.pushOnce('/trucks/new'),
        icon: const Icon(Icons.add),
        label: Text(s.t('et_add_button')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(s.t('home_error_loading'))),
        data: (list) => list.isEmpty
            ? Center(child: Text(s.t('et_mine_empty')))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = list[i];
                  return Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      key: ValueKey('et-mine-${t.id}'),
                      onTap: () => context.pushOnce('/trucks/${t.id}'),
                      title: Text(t.routeLabel(lang, anyLabel: s.t('et_any_direction_short')), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${t.placeLabel(lang)} · ${emptyTruckTonsLabel(s, t.freeTons)}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        EmptyTruckStatusChip(status: t.status, strings: s),
                        // Redaktə et · Dayandır / Aktiv et · Maşın doldu right
                        // from the list (owner, 13.11.2026).
                        PopupMenuButton<String>(
                          key: ValueKey('et-mine-menu-${t.id}'),
                          onSelected: (v) => v == 'edit'
                              ? context.pushOnce('/trucks/${t.id}/edit')
                              : _setStatusFromList(context, ref, s, t.id, v),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'edit', child: Text(s.t('et_edit'))),
                            if (t.status == 'active') PopupMenuItem(value: 'paused', child: Text(s.t('et_pause'))),
                            if (t.status != 'active') PopupMenuItem(value: 'active', child: Text(s.t('et_activate'))),
                            if (t.status != 'filled') PopupMenuItem(value: 'filled', child: Text(s.t('et_filled'))),
                          ],
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// Dayandır / Aktiv et / Maşın doldu from "Mənim elanlarım" ("Maşın doldu"
/// asked first, as on the ad page).
Future<void> _setStatusFromList(BuildContext context, WidgetRef ref, AppStrings s, String id, String status) async {
  if (status == 'filled') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.t('et_filled')),
        content: Text(s.t('et_filled_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(s.t('et_filled'))),
        ],
      ),
    );
    if (ok != true) return;
  }
  try {
    await ref.read(emptyTruckRepositoryProvider).setStatus(id, status);
    ref.invalidate(emptyTruckProvider(id));
    ref.invalidate(emptyTrucksProvider);
    ref.invalidate(myEmptyTrucksProvider);
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('et_err_save'))));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../repositories/profile_repository.dart';
import '../../../../services/share_link.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../chat/data/group_repository.dart';
import '../../../chat/presentation/providers/chat_providers.dart';
import '../../../fleet/presentation/fleet_providers.dart';

// "Paylaş" on a load card (owner's picture, 21.11.2026): "Sürücü seç" — the
// owner's own drivers from Maşınlarım (linked accounts only), one is picked
// and "Sürücüyə göndər" sends the load to him in Mesajlar (its link opens the
// load right in the app). No drivers → the link is shared at once (the
// phone's share sheet / copied). WhatsApp on the sheet too.

/// One driver of the owner's trucks: his account, name and plate(s).
class ShareDriver {
  final String userId, name;
  final List<String> plates;
  const ShareDriver({required this.userId, required this.name, this.plates = const []});
}

/// The owner's drivers that can get a message: linked accounts only, once
/// each (several trucks = several plates), by name.
List<ShareDriver> shareDriversOf(FleetData data, String? me) {
  final by = <String, ShareDriver>{};
  for (final t in data.owned(me)) {
    final id = t.driverId;
    if (id == null || id == me) continue;
    final old = by[id];
    final plate = (t.plate ?? '').trim();
    by[id] = ShareDriver(
      userId: id,
      name: old?.name ?? ((t.driverName ?? '').trim().isEmpty ? '' : t.driverName!.trim()),
      plates: [...?old?.plates, if (plate.isNotEmpty) plate],
    );
  }
  final out = by.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// What goes to the driver / WhatsApp: the load in one line + its link.
String cargoShareText({required String route, required String details, required String price}) =>
    [route, details, price].where((v) => v.trim().isNotEmpty).join(' · ');

/// "Paylaş": the driver sheet when the owner has drivers, else the link.
Future<void> shareCargo(
  BuildContext context,
  WidgetRef ref, {
  required String cargoId,
  required String text,
  required AppStrings strings,
}) async {
  final url = appPageLink('/cargo/$cargoId');
  final me = ref.read(currentUserIdProvider);
  var drivers = const <ShareDriver>[];
  if (me != null) {
    try {
      drivers = shareDriversOf(await ref.read(fleetProvider.future), me);
    } catch (_) {}
  }
  if (!context.mounted) return;
  if (drivers.isEmpty) {
    final copied = await shareOrCopy(title: 'TırLink', text: text, url: url);
    if (copied && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.t('row_link_copied'))));
    }
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => CargoShareSheet(drivers: drivers, text: text, url: url, strings: strings),
  );
}

class CargoShareSheet extends ConsumerStatefulWidget {
  final List<ShareDriver> drivers;
  final String text, url;
  final AppStrings strings;
  const CargoShareSheet({super.key, required this.drivers, required this.text, required this.url, required this.strings});

  @override
  ConsumerState<CargoShareSheet> createState() => _CargoShareSheetState();
}

class _CargoShareSheetState extends ConsumerState<CargoShareSheet> {
  String _q = '';
  String? _picked;
  bool _busy = false;

  AppStrings get s => widget.strings;

  String _nameOf(ShareDriver d) {
    final p = ref.watch(publicProfileProvider(d.userId)).valueOrNull;
    final n = (p?.fullName ?? '').trim();
    return n.isNotEmpty ? n : (d.name.isNotEmpty ? d.name : '—');
  }

  Future<void> _send() async {
    final id = _picked;
    if (id == null || _busy) return;
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(id);
      await ref.read(messageRepositoryProvider).send(
            conversationId: conv.id,
            senderId: me,
            receiverId: id,
            message: '${widget.text}\n${widget.url}',
          );
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(s.t('share_sent'))));
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text(s.t('share_failed'))));
      }
    }
  }

  Future<void> _whatsApp() async {
    final link = Uri.parse('https://wa.me/?text=${Uri.encodeComponent('${widget.text}\n${widget.url}')}');
    await launchUrl(link, mode: LaunchMode.externalApplication);
  }

  Future<void> _other() async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = await shareOrCopy(title: 'TırLink', text: widget.text, url: widget.url);
    if (copied) messenger.showSnackBar(SnackBar(content: Text(s.t('row_link_copied'))));
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [
      for (final d in widget.drivers)
        if (q.isEmpty || _nameOf(d).toLowerCase().contains(q) || d.plates.any((p) => p.toLowerCase().contains(q))) d
    ];
    final picked = widget.drivers.where((d) => d.userId == _picked).firstOrNull;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.textSoft, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
            child: Row(children: [
              Expanded(child: Text(s.t('share_pick_title'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text))),
              IconButton(icon: Icon(Icons.close, color: AppColors.textSoft), onPressed: () => Navigator.of(context).pop()),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(children: [
              Expanded(child: Text(s.t('share_pick_hint'), style: TextStyle(fontSize: 13.5, color: AppColors.textSoft))),
              const SizedBox(width: 8),
              Container(
                key: const ValueKey('share-count'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(16)),
                child: Text(s.t('share_n_drivers', {'n': '${widget.drivers.length}'}), style: TextStyle(fontSize: 12.5, color: AppColors.text)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('share-search'),
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(hintText: s.t('share_search'), prefixIcon: Icon(Icons.search, color: AppColors.textSoft)),
            ),
          ),
          Flexible(
            child: LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 32 - 8) / 2;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in list) SizedBox(width: w, child: _tile(d)),
                ]),
              );
            }),
          ),
          // WhatsApp and the other ways (owner, 21.11.2026).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('share-whatsapp'),
                  onPressed: _whatsApp,
                  icon: const Icon(Icons.chat, color: AppColors.whatsapp, size: 20),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('share-other'),
                  onPressed: _other,
                  icon: Icon(Icons.ios_share, color: AppColors.text, size: 19),
                  label: Text(s.t('share_other'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ),
          Divider(height: 16, color: AppColors.line),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${s.t('share_picked')}: ', style: TextStyle(color: AppColors.text)),
                    TextSpan(
                        text: picked == null ? '—' : _nameOf(picked),
                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                  ]),
                  key: const ValueKey('share-picked'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                key: const ValueKey('share-send'),
                onPressed: picked == null || _busy ? null : _send,
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s.t('share_send'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tile(ShareDriver d) {
    final on = d.userId == _picked;
    final p = ref.watch(publicProfileProvider(d.userId)).valueOrNull;
    final name = _nameOf(d);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => String.fromCharCode(w.runes.first).toUpperCase())
        .join();
    return Material(
      color: on ? AppColors.accent.withValues(alpha: 0.12) : AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('share-driver-${d.userId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _picked = on ? null : d.userId),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? AppColors.accent : AppColors.line, width: on ? 1.5 : 1),
          ),
          child: Row(children: [
            UserAvatar(imageUrl: p?.avatarUrl, initials: initials.isEmpty ? '?' : initials, radius: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (d.plates.isNotEmpty)
                  Row(children: [
                    Icon(Icons.local_shipping_outlined, size: 14, color: AppColors.textSoft),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(d.plates.join(', '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                    ),
                  ]),
              ]),
            ),
            const SizedBox(width: 4),
            Icon(on ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: on ? AppColors.accent : AppColors.textSoft),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/desktop_layout.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/presence/online_users.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../repositories/profile_repository.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../chat/data/group_repository.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/call_options.dart';
import '../../chat/presentation/widgets/location_message.dart';
import '../data/market_repository.dart';
import '../domain/market_models.dart';
import 'market_card.dart';
import 'market_vip_sheet.dart';
import 'market_providers.dart';

/// Elanın ətraflı səhifəsi (Şəkil 4) + bənzər elanlar (Şəkil 5).
class MarketDetailScreen extends ConsumerStatefulWidget {
  final String listingId;
  const MarketDetailScreen({super.key, required this.listingId});

  @override
  ConsumerState<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends ConsumerState<MarketDetailScreen> {
  int _page = 0;
  bool _descOpen = false;
  bool _busy = false;
  int? _views;
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    // Real view (one per person per day, never the owner's own).
    ref.read(marketRepositoryProvider).recordView(widget.listingId).then((v) {
      if (mounted && v != null) setState(() => _views = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<String?> _openChat(AppStrings s, MarketListing l) async {
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(l.ownerId);
      return conv.id;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('chat_open_failed'))));
      return null;
    }
  }

  Future<void> _message(AppStrings s, MarketListing l) async {
    setState(() => _busy = true);
    final id = await _openChat(s, l);
    if (mounted) setState(() => _busy = false);
    // Root-level chat page: this screen is above the tab shell, a tab route
    // ('/messages/..') would open UNDER it (black screen, no input).
    if (id != null && mounted) context.pushOnce('/chat/$id');
  }

  /// "Təklif et": price offer as a chat message to the seller.
  Future<void> _offer(AppStrings s, MarketListing l) async {
    final amount = TextEditingController(text: l.price?.round().toString() ?? '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('mk_offer_title')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: s.t('mk_offer_amount'), suffixText: l.currency),
          ),
          const SizedBox(height: 8),
          TextField(
              controller: note, maxLines: 3, minLines: 1, decoration: InputDecoration(hintText: s.t('mk_offer_note'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('mk_offer_send'))),
        ],
      ),
    );
    final value = double.tryParse(amount.text.replaceAll(RegExp(r'[\s,]'), ''));
    final text = note.text;
    amount.dispose();
    note.dispose();
    if (ok != true || value == null || value <= 0 || !mounted) return;
    setState(() => _busy = true);
    try {
      final convId = await _openChat(s, l);
      final me = ref.read(currentUserIdProvider) ?? ref.read(marketRepositoryProvider).myId;
      if (convId == null || me == null) return;
      await ref.read(messageRepositoryProvider).send(
            conversationId: convId,
            senderId: me,
            receiverId: l.ownerId,
            message: marketOfferMessage(
              label: s.t('mk_offer_label'),
              title: l.title,
              listingNo: l.listingNo,
              amount: marketPrice(value, l.currency),
              note: text,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('mk_offer_sent'))));
      context.pushOnce('/chat/$convId');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('chat_send_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _report(AppStrings s, MarketListing l) async {
    const reasons = ['fake', 'spam', 'fraud', 'other'];
    var reason = 'fake';
    final details = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.t('report_title')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final r in reasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(r == reason ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: r == reason ? AppColors.accent : AppColors.textSoft),
                  title: Text(s.t('report_reason_$r')),
                  onTap: () => setD(() => reason = r),
                ),
              TextField(
                  controller: details,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(hintText: s.t('report_details_hint'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('report_send'))),
          ],
        ),
      ),
    );
    final text = details.text;
    details.dispose();
    if (send != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(marketRepositoryProvider).report(l.id, s.t('report_reason_$reason'), text);
      messenger.showSnackBar(SnackBar(content: Text(s.t('report_sent'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('report_failed'))));
    }
  }

  Future<void> _share(AppStrings s, MarketListing l) async {
    final base = Uri.base;
    final link = '${base.origin}${base.path}#/market/l/${l.id}';
    await Clipboard.setData(ClipboardData(text: '${l.title} — ${marketPrice(l.price, l.currency)}\n$link'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('mk_link_copied'))));
  }

  Future<void> _markSold(AppStrings s, MarketListing l) async {
    final ok = await _confirm(s, s.t('mk_mark_sold_q'));
    if (!ok) return;
    await ref.read(marketRepositoryProvider).markSold(l.id);
    ref.invalidate(marketListingProvider(l.id));
    ref.invalidate(myMarketListingsProvider);
    ref.invalidate(marketFeedProvider);
  }

  Future<void> _delete(AppStrings s, MarketListing l) async {
    final ok = await _confirm(s, s.t('mk_delete_q'));
    if (!ok) return;
    await ref.read(marketRepositoryProvider).delete(l);
    ref.invalidate(myMarketListingsProvider);
    ref.invalidate(marketFeedProvider);
    if (mounted) context.pop();
  }

  Future<bool> _confirm(AppStrings s, String q) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(q),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('common_confirm'))),
          ],
        ),
      ) ==
      true;

  void _fullscreen(MarketListing l) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewer(photos: l.photos, initial: _page),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    // Owner check from the session too: the profile row may still be
    // loading, and the owner must always get Redaktə et / Sil.
    final me = ref.watch(currentUserIdProvider) ?? ref.read(marketRepositoryProvider).myId;
    final async = ref.watch(marketListingProvider(widget.listingId));
    final l = async.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('nav_market')),
        actions: [
          if (l != null) FavoriteHeartPlain(id: l.id),
          if (l != null)
            IconButton(tooltip: s.t('mk_share'), icon: const Icon(Icons.ios_share), onPressed: () => _share(s, l)),
        ],
      ),
      body: async.isLoading && l == null
          ? const Center(child: CircularProgressIndicator())
          : l == null
              ? Center(child: Text(s.t('mk_not_found'), style: TextStyle(color: AppColors.textSoft)))
              : _body(context, s, lang, l, me),
      // Computer: the buttons are in the right column instead.
      bottomNavigationBar: l == null || isDesktopLayout(context) ? null : _actions(s, l, me),
    );
  }

  Widget _body(BuildContext context, AppStrings s, String lang, MarketListing l, String? me) {
    final isOwner = l.ownerId == me;
    final place = l.city == null ? null : PickedPlace.fromStored(l.city!, l.country ?? '');
    final placeText = place == null
        ? '—'
        : [place.cityLabel(lang), if ((l.country ?? '').isNotEmpty) place.countryLabel(lang)].join(', ');
    final (agoKey, agoN) = marketAgo(l.publishedAt ?? l.createdAt);
    final head = _head(context, s, l, isOwner, placeText, agoKey, agoN);
    final rest = _rest(context, s, l, isOwner, placeText);
    if (isDesktopLayout(context)) return _desktopBody(s, l, me, head, rest);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // ---- gallery ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: _gallery(l),
        ),
        if (l.photos.length > 1) _thumbs(l),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...head,
            const SizedBox(height: 14),
            _Specs(s: s, l: l),
            const SizedBox(height: 12),
            _SellerCard(ownerId: l.ownerId, s: s),
            ...rest,
          ]),
        ),
        _Similar(l: l, s: s),
      ],
    );
  }

  /// Computer (wide window): photo, specs and text on the left, title,
  /// price, buttons and seller on the right — no screen-wide photo.
  Widget _desktopBody(AppStrings s, MarketListing l, String? me, List<Widget> head, List<Widget> rest) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _gallery(l, ratio: 16 / 9),
              if (l.photos.length > 1) _thumbs(l, padding: const EdgeInsets.only(top: 8)),
              const SizedBox(height: 16),
              _Specs(s: s, l: l, columns: 6),
              ...rest,
            ]),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 360,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ...head,
                  const SizedBox(height: 16),
                  _actions(s, l, me, desk: true),
                ]),
              ),
              const SizedBox(height: 12),
              _SellerCard(ownerId: l.ownerId, s: s),
            ]),
          ),
        ]),
        _Similar(l: l, s: s),
      ],
    );
  }

  Widget _gallery(MarketListing l, {double ratio = 1.7}) => ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: ratio,
              child: Stack(fit: StackFit.expand, children: [
                l.photos.isEmpty
                    ? const MarketPhoto(url: null)
                    : PageView.builder(
                        controller: _pager,
                        itemCount: l.photos.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) =>
                            GestureDetector(onTap: () => _fullscreen(l), child: MarketPhoto(url: l.photos[i])),
                      ),
                if (l.vipActive()) const Positioned(left: 12, top: 12, child: VipBadge(big: true)),
                if (l.photos.isNotEmpty)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _Pill(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_outlined, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('${_page + 1} / ${l.photos.length}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                if (l.photos.length > 1) ...[
                  Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _Round(icon: Icons.chevron_left, onTap: () => _go(-1, l)))),
                  Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(child: _Round(icon: Icons.chevron_right, onTap: () => _go(1, l)))),
                ],
                if (l.photos.isNotEmpty)
                  Positioned(right: 12, bottom: 12, child: _Round(icon: Icons.fullscreen, onTap: () => _fullscreen(l))),
              ]),
            ),
          );

  Widget _thumbs(MarketListing l, {EdgeInsets padding = const EdgeInsets.fromLTRB(12, 8, 12, 0)}) => SizedBox(
            height: 74,
            child: MouseDragScroll(child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: padding,
              itemCount: l.photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () =>
                    _pager.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Container(
                  width: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: i == _page ? AppColors.accent : Colors.transparent, width: 2),
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: MarketPhoto(url: l.photos[i])),
                ),
              ),
            )),
          );

  /// Status, title, price, listing number and meta.
  List<Widget> _head(BuildContext context, AppStrings s, MarketListing l, bool isOwner, String placeText,
          String agoKey, int agoN) =>
      [
            if (isOwner && l.status != MarketStatus.active) _StatusBanner(s: s, l: l),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(l.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
              if (l.vipActive()) const VipBadge(),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(marketPrice(l.price, l.currency),
                    style: TextStyle(color: AppColors.accent, fontSize: 28, fontWeight: FontWeight.w900)),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: '#${l.listingNo}'));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('mk_no_copied'))));
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${s.t('mk_ad_no')}: #${l.listingNo}',
                      style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                  const SizedBox(width: 4),
                  Icon(Icons.copy, size: 16, color: AppColors.textSoft),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Meta(icon: Icons.visibility_outlined, text: s.t('mk_views', {'n': '${_views ?? l.views}'})),
              _Meta(icon: Icons.calendar_today_outlined, text: s.t(agoKey, {'n': '$agoN'})),
              _Meta(icon: Icons.location_on_outlined, text: placeText),
            ]),
      ];

  /// Description, location and report.
  List<Widget> _rest(BuildContext context, AppStrings s, MarketListing l, bool isOwner, String placeText) => [
            if ((l.description ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: Text(s.t('mk_s_description'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                IconButton(
                  icon: Icon(_descOpen ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _descOpen = !_descOpen),
                ),
              ]),
              Text(l.description!.trim(),
                  maxLines: _descOpen ? null : 3,
                  overflow: _descOpen ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSoft, fontSize: 15, height: 1.4)),
            ],
            const SizedBox(height: 16),
            Text(s.t('mk_location'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Icon(Icons.location_on, color: AppColors.danger, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(placeText, style: const TextStyle(fontWeight: FontWeight.w700)),
                    // Honest: the pin is the city, not an exact address.
                    Text(s.t('mk_location_city_only'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                  ]),
                ),
                if (l.lat != null && l.lng != null)
                  FilledButton.icon(
                    onPressed: () => showNavigationPicker(
                      context,
                      s,
                      ChatLocation(url: 'https://maps.google.com/?q=${l.lat},${l.lng}', lat: l.lat, lng: l.lng),
                    ),
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(s.t('mk_show_on_map')),
                  ),
              ]),
            ),
            if (!isOwner) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _report(s, l),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSoft),
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(s.t('report_button')),
                ),
              ),
            ],
      ];

  /// Computer: the same buttons one under another (the delete icon gets
  /// its label).
  Widget _deskButtons(List<Widget> children, Widget? below) {
    final items = <Widget>[
      for (final c in children)
        if (c is Expanded)
          c.child
        else if (c is IconButton)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: c.onPressed,
            icon: c.icon,
            label: Text(c.tooltip ?? ''),
          )
        else if (c is! SizedBox)
          c,
      if (below != null) below,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 10), items[i]],
    ]);
  }

  void _go(int d, MarketListing l) {
    final next = (_page + d).clamp(0, l.photos.length - 1);
    _pager.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// "VIP et" (0044) on its own row under the owner's buttons, so they keep
  /// their width.
  Widget _vipButton(AppStrings s, MarketListing l) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const ValueKey('mk-vip-make'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kVipGold,
            side: BorderSide(color: kVipGold.withValues(alpha: 0.7)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () => showMarketVipSheet(context, s, l),
          icon: const Icon(Icons.workspace_premium),
          label: Text(s.t(l.vipActive() ? 'mk_vip_extend' : 'mk_vip_title')),
        ),
      );

  Widget _actions(AppStrings s, MarketListing l, String? me, {bool desk = false}) {
    final isOwner = l.ownerId == me;
    Widget bar(List<Widget> children, {Widget? below}) => desk
        ? _deskButtons(children, below)
        : SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration:
                BoxDecoration(color: AppColors.hero, border: Border(top: BorderSide(color: AppColors.line))),
            child: below == null
                ? Row(children: children)
                : Column(mainAxisSize: MainAxisSize.min, children: [Row(children: children), const SizedBox(height: 8), below]),
          ),
        );

    if (isOwner) {
      // Seller on his own ad: manage instead of contact.
      return bar([
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => context.pushOnce('/market/edit/${l.id}'),
            icon: const Icon(Icons.edit_outlined),
            label: Text(s.t('mk_edit')),
          ),
        ),
        const SizedBox(width: 8),
        if (l.status == MarketStatus.active) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _markSold(s, l),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(s.t('mk_mark_sold')),
            ),
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          tooltip: s.t('mk_delete'),
          onPressed: () => _delete(s, l),
          icon: Icon(Icons.delete_outline, color: AppColors.danger),
        ),
      ], below: l.status == MarketStatus.active ? _vipButton(s, l) : null);
    }
    if (l.status == MarketStatus.sold) {
      return bar([
        Expanded(
            child:
                Text(s.t('mk_sold'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)))
      ]);
    }
    final phone = (l.phone ?? '').trim();
    return bar([
      Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: BorderSide(color: AppColors.accentFill),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: phone.isEmpty ? null : () => showCallOptions(context, s, phone),
          icon: const Icon(Icons.call),
          label: Text(s.t('svc_call')),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _busy ? null : () => _message(s, l),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(s.t('svc_message')),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FilledButton.icon(
          key: const ValueKey('mk-offer'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _busy ? null : () => _offer(s, l),
          icon: const Icon(Icons.local_offer_outlined),
          label: Text(s.t('mk_offer')),
        ),
      ),
    ]);
  }
}

/// Heart in the app bar (no dark circle).
class FavoriteHeartPlain extends ConsumerWidget {
  final String id;
  const FavoriteHeartPlain({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(marketFavoriteIdsProvider).contains(id);
    return IconButton(
      icon: Icon(on ? Icons.favorite : Icons.favorite_border, color: on ? AppColors.accent : null),
      onPressed: () => ref.read(marketFavoriteIdsProvider.notifier).toggle(id).catchError((_) {}),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final AppStrings s;
  final MarketListing l;
  const _StatusBanner({required this.s, required this.l});

  @override
  Widget build(BuildContext context) {
    final note = (l.adminNote ?? '').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Text(
        '${s.t('mk_status_${l.status.name}')}${note.isEmpty ? '' : '\n${s.t('mk_rejected_note')}: $note'}',
        style: const TextStyle(fontSize: 13.5, height: 1.35),
      ),
    );
  }
}

class _Specs extends StatelessWidget {
  final AppStrings s;
  final MarketListing l;
  final int columns;
  const _Specs({required this.s, required this.l, this.columns = 3});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.add_road, s.t('mk_mileage_short'), marketKm(l.mileageKm)),
      (Icons.settings_suggest_outlined, s.t('mk_engine_short'), l.engineL == null ? '—' : '${l.engineL} L'),
      (Icons.bolt, s.t('mk_power_short'), l.powerHp == null ? '—' : '${l.powerHp} ${s.t('mk_hp')}'),
      (Icons.settings_outlined, s.t('mk_gearbox_short'), l.gearbox == null ? '—' : s.t('mk_gear_${l.gearbox}')),
      (Icons.local_gas_station_outlined, s.t('mk_fuel_short'), l.fuel == null ? '—' : s.t('mk_fuel_${l.fuel}')),
      (Icons.calendar_month_outlined, s.t('mk_year'), l.year?.toString() ?? '—'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Cells grow taller with the chosen text size (1.35 at normal).
        childAspectRatio: 1.35 / MediaQuery.textScalerOf(context).scale(1),
        children: [
          for (final (icon, label, value) in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: AppColors.accent, size: 22),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                const SizedBox(height: 2),
                // Long values (e.g. "1 250 000 km") shrink instead of being cut.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Seller: real profile data only (name, photo, online, verified).
class _SellerCard extends ConsumerWidget {
  final String ownerId;
  final AppStrings s;
  const _SellerCard({required this.ownerId, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(publicProfileProvider(ownerId)).valueOrNull;
    final online = ref.watch(isUserOnlineProvider(ownerId));
    final name = (p?.fullName ?? '').trim();
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushOnce('/user/$ownerId'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Row(children: [
            UserAvatar(imageUrl: p?.avatarUrl, initials: name.isEmpty ? '?' : name[0].toUpperCase(), online: online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? '—' : name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 2),
                Wrap(spacing: 10, children: [
                  if (online)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.circle, size: 9, color: AppColors.online),
                      const SizedBox(width: 4),
                      Text(s.t('mk_online'), style: TextStyle(color: AppColors.online, fontSize: 12.5)),
                    ]),
                  if (p?.isVerified == true)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.verified, size: 15, color: AppColors.online),
                      const SizedBox(width: 4),
                      Text(s.t('mk_verified'), style: const TextStyle(fontSize: 12.5)),
                    ]),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}

/// "Bu elana bənzər elanlar" (Şəkil 5).
class _Similar extends ConsumerWidget {
  final MarketListing l;
  final AppStrings s;
  const _Similar({required this.l, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(marketSimilarProvider(l.id)).valueOrNull ?? const <MarketListing>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(s.t('mk_similar'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            TextButton(
              onPressed: () {
                ref.read(marketFilterProvider.notifier).state = MarketFilter(category: l.category, brand: l.brand);
                context.go('/market');
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(s.t('mk_see_all'), style: TextStyle(color: AppColors.accent)),
                Icon(Icons.arrow_forward, size: 18, color: AppColors.accent),
              ]),
            ),
          ]),
        ),
        SizedBox(
          height: 250,
          child: MouseDragScroll(child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(width: 180, child: MarketCard(l: items[i], compact: true)),
          )),
        ),
      ]),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initial;
  const _PhotoViewer({required this.photos, required this.initial});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _c = PageController(initialPage: widget.initial);
  late int _i = widget.initial;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text('${_i + 1} / ${widget.photos.length}')),
      body: PageView.builder(
        controller: _c,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _i = i),
        // Pinch to zoom.
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: Image.network(widget.photos[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget child;
  const _Pill({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
        child: child,
      );
}

class _Round extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Round({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: Colors.white))),
      );
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: AppColors.textSoft),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
      ]);
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/service_models.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/services_repository.dart';
import 'service_widgets.dart';
import 'services_providers.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/widgets/map_tiles.dart';

/// Public page of one mechanic / service centre / tow truck: photos,
/// trust badge, categories, hours, location, contact buttons and
/// reviews. The owner gets "Edit" and the availability switch; an
/// unowned (admin-added) listing offers "This is my business".
class ServiceDetailScreen extends ConsumerWidget {
  final String id;
  const ServiceDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final me = ref.watch(currentUserIdProvider);
    final async = ref.watch(serviceByIdProvider(id));
    final cats = ref.watch(serviceCategoriesProvider).valueOrNull ?? const <ServiceCategory>[];

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/services')),
        title: Text(s.t('svc_profile_title')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.t('svc_load_failed')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => ref.invalidate(serviceByIdProvider(id)), child: Text(s.t('common_try_again'))),
            ],
          ),
        ),
        data: (p) {
          if (p == null) return Center(child: Text(s.t('svc_not_found')));
          final isOwner = me != null && p.ownerId == me;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(serviceByIdProvider(id));
              ref.invalidate(serviceReviewsProvider(id));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                if (p.photos.isNotEmpty) ...[
                  _Photos(urls: p.photos),
                  const SizedBox(height: 14),
                ],
                if (p.isPro) ...[
                  _ProBanner(s: s),
                  const SizedBox(height: 10),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 44, height: 44, child: ServicePin(type: p.markerType, active: p.isActive, selected: true, pro: p.isPro)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: AppFonts.display(size: 24, color: AppColors.text)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ServiceTrustBadge(p: p, s: s),
                              if (p.isPro) const ServiceProBadge(),
                              Text(s.t(p.isCenter ? 'svc_kind_center' : 'svc_kind_individual'),
                                  style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
                              if (p.isMobile)
                                Text('· ${s.t('svc_mobile_service')}', style: const TextStyle(color: AppColors.accent, fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // The owner's FreightLink page (catalog of work, about…).
                if (p.ownerId != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => context.pushOnce('/user/${p.ownerId}'),
                      icon: const Icon(Icons.storefront_outlined),
                      label: Text(s.t('svc_open_profile')),
                    ),
                  ),
                ],
                if (isOwner && p.status != 'approved') ...[
                  const SizedBox(height: 12),
                  _StatusNote(p: p, s: s),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    RatingStars(value: p.ratingAvg, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      p.ratingCount == 0 ? s.t('svc_no_reviews') : '${p.ratingAvg.toStringAsFixed(1)} · ${s.t('svc_reviews_n', {'n': '${p.ratingCount}'})}',
                      style: const TextStyle(color: AppColors.textSoft, fontSize: 13),
                    ),
                    const Spacer(),
                    Icon(Icons.circle, size: 9, color: p.isActive ? AppColors.online : AppColors.textSoft),
                    const SizedBox(width: 4),
                    Text(s.t(p.isActive ? 'svc_active' : 'svc_inactive'), style: const TextStyle(fontSize: 13, color: AppColors.textSoft)),
                  ],
                ),
                const SizedBox(height: 14),
                ServiceContactBar(p: p, s: s),
                if (isOwner) ...[
                  const SizedBox(height: 12),
                  _OwnerTools(p: p, s: s),
                  const SizedBox(height: 10),
                  _AdvertiseCard(s: s, serviceId: p.id),
                ],
                const SizedBox(height: 18),
                if (p.categories.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in p.categories)
                        for (final c in cats.where((c) => c.id == id))
                          Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(serviceCategoryIcon(c.icon), size: 16, color: AppColors.accent),
                            label: Text(c.name(lang), style: const TextStyle(fontSize: 12.5)),
                          ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if ((p.specialty ?? '').isNotEmpty) _InfoRow(icon: Icons.workspace_premium_outlined, label: s.t('svc_specialty'), value: p.specialty!),
                if ((p.description ?? '').isNotEmpty) _InfoRow(icon: Icons.notes, label: s.t('svc_description'), value: p.description!),
                _InfoRow(
                  icon: Icons.schedule,
                  label: s.t('svc_hours'),
                  value: p.is24h ? s.t('svc_24h') : ((p.workingHours ?? '').isEmpty ? '—' : p.workingHours!),
                ),
                if (p.isMobile && p.serviceRadiusKm != null)
                  _InfoRow(icon: Icons.radar, label: s.t('svc_radius'), value: '${p.serviceRadiusKm} km'),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: s.t('svc_location'),
                  value: [p.address, p.city, p.country].where((e) => (e ?? '').trim().isNotEmpty).join(', ').ifEmpty('—'),
                ),
                if ((p.phone ?? '').isNotEmpty) _InfoRow(icon: Icons.phone_outlined, label: s.t('svc_phone'), value: p.phone!),
                if ((p.whatsapp ?? '').isNotEmpty)
                  _InfoRow(
                    icon: Icons.chat,
                    label: 'WhatsApp',
                    value: p.whatsapp!,
                    onTap: () => launchUrl(Uri.parse('https://wa.me/${p.whatsapp!.replaceAll(RegExp(r'[^0-9]'), '')}'),
                        mode: LaunchMode.externalApplication),
                  ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    height: 170,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(p.lat, p.lng),
                        initialZoom: 14,
                        backgroundColor: AppColors.hero,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        const AppTileLayer(),
                        MarkerLayer(markers: [
                          Marker(point: LatLng(p.lat, p.lng), width: 44, height: 44, child: ServicePin(type: p.markerType, selected: true, pro: p.isPro)),
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _Reviews(p: p, s: s, isOwner: isOwner),
                const SizedBox(height: 16),
                if (!isOwner && p.isUnclaimed) _ClaimButton(p: p, s: s),
                if (!isOwner)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _report(context, ref, p, s),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textSoft),
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: Text(s.t('report_button')),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _report(BuildContext context, WidgetRef ref, ServiceProvider p, AppStrings s) async {
    const reasons = ['fake', 'spam', 'fraud', 'other'];
    var reason = 'fake';
    final details = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.t('svc_report_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in reasons)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(r == reason ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: r == reason ? AppColors.accent : AppColors.textSoft),
                    title: Text(s.t('report_reason_$r')),
                    onTap: () => setState(() => reason = r),
                  ),
                TextField(
                  controller: details,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(hintText: s.t('report_details_hint')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('report_send'))),
          ],
        ),
      ),
    );
    final text = details.text.trim();
    Future.delayed(const Duration(seconds: 1), details.dispose);
    if (send != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(servicesRepositoryProvider).report(p.id, s.t('report_reason_$reason'), text);
      messenger.showSnackBar(SnackBar(content: Text(s.t('report_sent'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('report_failed'))));
    }
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _StatusNote extends StatelessWidget {
  final ServiceProvider p;
  final AppStrings s;
  const _StatusNote({required this.p, required this.s});

  @override
  Widget build(BuildContext context) {
    final bad = p.status == 'rejected' || p.status == 'suspended';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bad ? AppColors.urgentBg : AppColors.cardAlt, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bad ? Icons.block : Icons.hourglass_top, size: 18, color: bad ? AppColors.urgentFg : AppColors.textSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [s.t('svc_status_${p.status}'), if ((p.adminNote ?? '').isNotEmpty) p.adminNote!].join('\n'),
              style: TextStyle(fontSize: 13, color: bad ? AppColors.urgentFg : AppColors.textSoft, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _InfoRow({required this.icon, required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Photos extends StatelessWidget {
  final List<String> urls;
  const _Photos({required this.urls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => launchUrl(Uri.parse(urls[i]), mode: LaunchMode.externalApplication),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              urls[i],
              width: urls.length == 1 ? MediaQuery.sizeOf(context).width - 32 : 260,
              height: 190,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(width: 260, color: AppColors.card, child: const Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}

class _OwnerTools extends ConsumerStatefulWidget {
  final ServiceProvider p;
  final AppStrings s;
  const _OwnerTools({required this.p, required this.s});

  @override
  ConsumerState<_OwnerTools> createState() => _OwnerToolsState();
}

class _OwnerToolsState extends ConsumerState<_OwnerTools> {
  bool _busy = false;

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    try {
      await ref.read(servicesRepositoryProvider).update(widget.p.id, {'is_active': v});
      ref.invalidate(serviceByIdProvider(widget.p.id));
      ref.invalidate(myServiceProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.s.t('svc_save_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(s.t('svc_available_now'), style: const TextStyle(fontSize: 13.5)),
              value: widget.p.isActive,
              onChanged: _busy ? null : _toggle,
            ),
          ),
          const SizedBox(width: 6),
          FilledButton.tonalIcon(
            onPressed: () => context.pushOnce('/service-edit/${widget.p.id}'),
            icon: const Icon(Icons.edit, size: 16),
            label: Text(s.t('svc_edit')),
          ),
        ],
      ),
    );
  }
}

/// Owner: advertise the service in the loads feed (the normal "Reklam ver"
/// flow — same prices, receipt and admin check as every other ad).
class _AdvertiseCard extends StatelessWidget {
  final AppStrings s;
  final String serviceId;
  const _AdvertiseCard({required this.s, required this.serviceId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // Service ad editor: service templates, countries only.
      onTap: () => context.pushOnce('/ad-create?service=$serviceId'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.campaign, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t('svc_advertise_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(s.t('svc_advertise_hint'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSoft),
          ],
        ),
      ),
    );
  }
}

/// Gold strip on top of a PRO service profile.
class _ProBanner extends StatelessWidget {
  final AppStrings s;
  const _ProBanner({required this.s});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [Color(0x40FFC83D), Color(0x14FFC83D)]),
        border: Border.all(color: kProGold.withValues(alpha: 0.8), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x33FFC83D), blurRadius: 12)],
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: kProGold, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.t('svc_pro_banner'),
                style: const TextStyle(color: kProGold, fontWeight: FontWeight.w800, fontSize: 13.5, letterSpacing: 0.3)),
          ),
        ],
      ),
    );
  }
}

class _Reviews extends ConsumerWidget {
  final ServiceProvider p;
  final AppStrings s;
  final bool isOwner;
  const _Reviews({required this.p, required this.s, required this.isOwner});

  Future<void> _write(BuildContext context, WidgetRef ref, ServiceReview? existing) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    var rating = existing?.rating ?? 5;
    final ctrl = TextEditingController(text: existing?.comment ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.t('svc_write_review')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => rating = i),
                      icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFFACC15), size: 32),
                    ),
                ],
              ),
              TextField(
                controller: ctrl,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(hintText: s.t('svc_review_hint')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('report_send'))),
          ],
        ),
      ),
    );
    final text = ctrl.text;
    Future.delayed(const Duration(seconds: 1), ctrl.dispose);
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(servicesRepositoryProvider).saveReview(providerId: p.id, uid: uid, rating: rating, comment: text);
      ref.invalidate(serviceReviewsProvider(p.id));
      ref.invalidate(serviceByIdProvider(p.id));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('svc_review_saved'))));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('svc_review_failed'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    final async = ref.watch(serviceReviewsProvider(p.id));
    final list = async.valueOrNull ?? const <ServiceReview>[];
    ServiceReview? mine;
    for (final r in list) {
      if (r.userId == uid) mine = r;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(s.t('svc_reviews').toUpperCase(),
                  style: const TextStyle(color: AppColors.textSoft, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
            ),
            if (!isOwner)
              TextButton.icon(
                onPressed: () => _write(context, ref, mine),
                icon: Icon(mine == null ? Icons.rate_review_outlined : Icons.edit, size: 18),
                label: Text(s.t(mine == null ? 'svc_write_review' : 'svc_edit_review')),
              ),
          ],
        ),
        if (async.isLoading && list.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(s.t('svc_no_reviews_yet'), style: const TextStyle(color: AppColors.textSoft)),
          )
        else
          for (final r in list)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      RatingStars(value: r.rating.toDouble()),
                      const SizedBox(width: 8),
                      Text(
                        '${r.createdAt.toLocal().day.toString().padLeft(2, '0')}.${r.createdAt.toLocal().month.toString().padLeft(2, '0')}.${r.createdAt.toLocal().year}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textSoft),
                      ),
                      if (r.userId == uid) ...[
                        const Spacer(),
                        Text(s.t('svc_your_review'), style: const TextStyle(fontSize: 11.5, color: AppColors.accent)),
                      ],
                    ],
                  ),
                  if ((r.comment ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(r.comment!, style: const TextStyle(height: 1.35)),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

class _ClaimButton extends ConsumerStatefulWidget {
  final ServiceProvider p;
  final AppStrings s;
  const _ClaimButton({required this.p, required this.s});

  @override
  ConsumerState<_ClaimButton> createState() => _ClaimButtonState();
}

class _ClaimButtonState extends ConsumerState<_ClaimButton> {
  bool _sent = false;

  Future<void> _claim() async {
    final s = widget.s;
    final msg = TextEditingController();
    final phone = TextEditingController(text: ref.read(currentUserProvider)?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('svc_claim_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.t('svc_claim_body'), style: const TextStyle(fontSize: 13, color: AppColors.textSoft)),
              const SizedBox(height: 10),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.t('svc_phone'))),
              const SizedBox(height: 8),
              TextField(controller: msg, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: s.t('svc_claim_message'))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('report_send'))),
        ],
      ),
    );
    final m = msg.text;
    final ph = phone.text;
    Future.delayed(const Duration(seconds: 1), () {
      msg.dispose();
      phone.dispose();
    });
    if (ok != true || !mounted) return;
    try {
      await ref.read(servicesRepositoryProvider).claim(widget.p.id, message: m, phone: ph);
      if (mounted) {
        setState(() => _sent = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('svc_claim_sent'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('svc_claim_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: OutlinedButton.icon(
        onPressed: _sent ? null : _claim,
        icon: const Icon(Icons.how_to_reg_outlined),
        label: Text(widget.s.t(_sent ? 'svc_claim_sent_short' : 'svc_claim_button')),
      ),
    );
  }
}

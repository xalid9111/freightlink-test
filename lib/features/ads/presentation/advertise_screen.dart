import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../services/presentation/services_providers.dart' show myServiceProvider;
import 'ad_creative_view.dart';
import 'ad_kind_logic.dart';
import 'ads_providers.dart';
import '../../../core/router/safe_navigation.dart';

/// "Reklam ver": a short intro, the big "Reklam yarat" button and
/// "Sifarişlərim" — every order with its number, amount, date and status.
class AdvertiseScreen extends ConsumerStatefulWidget {
  const AdvertiseScreen({super.key});

  @override
  ConsumerState<AdvertiseScreen> createState() => _AdvertiseScreenState();
}

class _AdvertiseScreenState extends ConsumerState<AdvertiseScreen> {
  bool _autoOpened = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final orders = ref.watch(myAdOrdersProvider);
    // The template window opens by itself once, when the page is entered.
    final templates = ref.watch(adTemplatesProvider);
    final hasService = ref.watch(myServiceProvider).valueOrNull != null;
    final serviceTemplates = hasService ? ref.watch(serviceAdTemplatesProvider).valueOrNull : null;
    // Admin switch "Reklam ver" (default OFF): no new orders, but customers
    // still see and pay their existing ones.
    final orderingOn = ref.watch(adsOrderingEnabledProvider).valueOrNull ?? false;
    if (orderingOn && !_autoOpened && ((templates.valueOrNull?.isNotEmpty ?? false) || (serviceTemplates?.isNotEmpty ?? false))) {
      _autoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showAdTemplatePicker(context, ref);
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('ad_title')),
        actions: [
          IconButton(
            tooltip: s.t('home_retry'),
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(myAdOrdersProvider);
              ref.invalidate(myAdStatsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (orderingOn) ...[
            Text(s.t('adv_intro'), style: const TextStyle(color: AppColors.textSoft, height: 1.4)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => showAdTemplatePicker(context, ref),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(s.t('adv_create'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            _HowItWorks(s: s),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12)),
              child: Text(s.t('adv_ordering_closed'), style: const TextStyle(color: AppColors.textSoft, height: 1.4)),
            ),
          const SizedBox(height: 22),
          Text(s.t('ad_my_orders').toUpperCase(), style: adSectionHeader),
          const SizedBox(height: 8),
          orders.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (_, __) => Text(s.t('home_error_loading'), style: const TextStyle(color: AppColors.textSoft)),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(s.t('ad_no_orders'), style: const TextStyle(color: AppColors.textSoft)),
                  )
                : Column(children: [for (final o in list) AdOrderTile(order: o, s: s)]),
          ),
        ],
      ),
    );
  }
}

/// "Şablon seçin" window: the admin's active templates; tapping one opens
/// the editor (texts, logo, colour, dates) with that template. A user with
/// a service profile also sees the service templates ("Servis reklamı",
/// selected first) — that ad leads to his own service page.
Future<void> showAdTemplatePicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TemplatePicker(open: (route) => context.pushOnce(route)),
  );
}

class _TemplatePicker extends ConsumerStatefulWidget {
  final void Function(String route) open;
  const _TemplatePicker({required this.open});

  @override
  ConsumerState<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends ConsumerState<_TemplatePicker> {
  AdKind? _kind;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final myService = ref.watch(myServiceProvider).valueOrNull;
    final kinds = adKindsFor(hasService: myService != null);
    final kind = kinds.contains(_kind) ? _kind! : kinds.first;
    final async = ref.watch(kind == AdKind.service ? serviceAdTemplatesProvider : adTemplatesProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text(s.t('adv_pick_template_title'), style: Theme.of(ctx).textTheme.titleMedium)),
                IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          if (kinds.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<AdKind>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: AdKind.service, icon: const Icon(Icons.storefront, size: 18), label: Text(s.t('adv_kind_service'))),
                  ButtonSegment(value: AdKind.cargo, icon: const Icon(Icons.local_shipping, size: 18), label: Text(s.t('adv_kind_cargo'))),
                ],
                selected: {kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(s.t(kind == AdKind.service ? 'adv_pick_template_sub_service' : 'adv_pick_template_sub'),
                style: const TextStyle(color: AppColors.textSoft, fontSize: 13)),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text(s.t('home_error_loading'))),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(s.t('adv_no_templates'), textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSoft)),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final t = list[i];
                        return Material(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              widget.open(adCreateRoute(kind, t.id, serviceId: myService?.id));
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AdCreativeView(creative: t.sample()),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                      if (t.logo != null)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Icon(Icons.image_outlined, size: 16, color: AppColors.textSoft),
                                        ),
                                      Text(s.t('adv_pick_this'),
                                          style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

const adSectionHeader = TextStyle(color: AppColors.textSoft, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700);

String adMoney(double v, String c) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)} $c';

String adStageKey(AdStage st) => switch (st) {
      AdStage.awaitingPayment => 'adv_stage_payment',
      AdStage.reviewing => 'adv_stage_reviewing',
      AdStage.approved => 'adv_stage_approved',
      AdStage.rejected => 'adv_stage_rejected',
      AdStage.scheduled => 'adv_stage_scheduled',
      AdStage.live => 'adv_stage_live',
      AdStage.ended => 'adv_stage_ended',
      AdStage.cancelled => 'adv_stage_cancelled',
    };

Color adStageColor(AdStage st) => switch (st) {
      AdStage.awaitingPayment => AppColors.accent,
      AdStage.reviewing => AppColors.blue,
      AdStage.approved || AdStage.scheduled => AppColors.route,
      AdStage.live => AppColors.online,
      AdStage.rejected || AdStage.cancelled => AppColors.danger,
      AdStage.ended => AppColors.textSoft,
    };

class AdStageChip extends StatelessWidget {
  final AdStage stage;
  final AppStrings s;
  const AdStageChip({super.key, required this.stage, required this.s});

  @override
  Widget build(BuildContext context) {
    final c = adStageColor(stage);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(s.t(adStageKey(stage)), style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// One order in "Sifarişlərim".
class AdOrderTile extends ConsumerWidget {
  final AdOrder order;
  final AppStrings s;
  const AdOrderTile({super.key, required this.order, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final date = DateFormat('d MMM yyyy', lang).format(o.createdAt.toLocal());
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushOnce('/ad-order/${o.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (o.creative != null)
                AdCreativeView(creative: o.creative!)
              else if ((o.imageUrl ?? '').isNotEmpty)
                AspectRatio(
                  aspectRatio: AdBannerSpec.ratio,
                  child: Image.network(o.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${s.t('adv_order')} ${o.number}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${adMoney(o.price, o.currency)} · ${s.t('ad_days', {'n': '${o.days}'})} · $date',
                              style: const TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    AdStageChip(stage: o.stage, s: s),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: AppColors.textSoft),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  final AppStrings s;
  const _HowItWorks({required this.s});

  @override
  Widget build(BuildContext context) {
    final steps = ['adv_how_1', 'adv_how_2', 'adv_how_3', 'adv_how_4'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.t(steps[i]), style: const TextStyle(fontSize: 13, height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

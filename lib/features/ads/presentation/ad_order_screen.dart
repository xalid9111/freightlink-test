import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/ads_repository.dart';
import 'ad_creative_view.dart';
import 'ads_providers.dart';
import 'advertise_screen.dart' show AdStageChip, adMoney, adSectionHeader;
import '../../../core/router/safe_navigation.dart';

/// One ad order: status timeline, banner, amount, bank / card details and
/// the receipt upload. Uploading a receipt only sends the order for
/// checking — the admin confirms the payment.
class AdOrderScreen extends ConsumerStatefulWidget {
  final String id;
  const AdOrderScreen({super.key, required this.id});

  @override
  ConsumerState<AdOrderScreen> createState() => _AdOrderScreenState();
}

class _AdOrderScreenState extends ConsumerState<AdOrderScreen> {
  bool _busy = false;

  Future<void> _uploadReceipt(AppStrings s, AdOrder o) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
              title: Text(s.t('chat_attach_photo')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.accent),
              title: Text(s.t('chat_attach_camera')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      _toast(s.t('chat_file_too_big'));
      return;
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || !mounted) return;
    final name = file.name.toLowerCase();
    final ext = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : (name.endsWith('.heic') ? 'heic' : 'jpg'));
    setState(() => _busy = true);
    try {
      await ref.read(adsRepositoryProvider).uploadReceipt(userId: uid, orderId: o.id, bytes: bytes, ext: ext);
      ref.invalidate(myAdOrdersProvider);
      _toast(s.t('adv_receipt_sent'));
    } catch (_) {
      _toast(s.t('adv_receipt_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(AppStrings s, AdOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('ad_cancel_order')),
        content: Text(s.t('adv_cancel_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('ad_cancel_order'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adsRepositoryProvider).cancelOrder(o.id);
      ref.invalidate(myAdOrdersProvider);
    } catch (_) {
      _toast(s.t('ad_action_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final async = ref.watch(myAdOrderProvider(widget.id));
    final fmt = DateFormat('d MMM yyyy', lang);
    final fmtTime = DateFormat('d MMM yyyy, HH:mm', lang);

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop() ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/ads')),
        title: Text(s.t('adv_order_title')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(s.t('home_error_loading'))),
        data: (o) {
          if (o == null) return Center(child: Text(s.t('adv_order_missing')));
          final stage = o.stage;
          final stats = ref.watch(myAdStatsProvider).valueOrNull?[o.id];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${s.t('adv_order')} ${o.number}',
                        style: AppFonts.display(size: 24, color: AppColors.text)),
                  ),
                  AdStageChip(stage: stage, s: s),
                ],
              ),
              const SizedBox(height: 12),
              _Timeline(stage: stage, s: s),
              const SizedBox(height: 14),
              if (o.creative != null)
                AdCreativeView(creative: o.creative!, radius: BorderRadius.circular(14))
              else if ((o.imageUrl ?? '').isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(aspectRatio: AdBannerSpec.ratio, child: Image.network(o.imageUrl!, fit: BoxFit.cover)),
                ),
              if ((stage == AdStage.awaitingPayment || stage == AdStage.reviewing) && (o.creative?.isStandard ?? false))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.pushOnce('/ad-create?order=${o.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(s.t('adv_edit')),
                  ),
                ),
              const SizedBox(height: 14),
              _Line(label: s.t('adv_amount'), value: adMoney(o.price, o.currency), strong: true),
              _Line(label: s.t('adv_duration'), value: s.t('ad_days', {'n': '${o.days}'})),
              // No date was chosen (new flow) → starts on approval; an older
              // order may still carry a future start date.
              if (o.adStartsAt == null)
                _Line(
                  label: s.t('adv_start_date'),
                  value: (o.startsOn != null && DateUtils.dateOnly(o.startsOn!).isAfter(DateUtils.dateOnly(o.createdAt.toLocal())))
                      ? fmt.format(o.startsOn!)
                      : s.t('adv_start_on_approval_value'),
                ),
              if (o.adStartsAt != null && o.adEndsAt != null)
                _Line(label: s.t('adv_runs'), value: '${fmtTime.format(o.adStartsAt!)} → ${fmtTime.format(o.adEndsAt!)}'),
              _Line(label: s.t('adv_created'), value: fmtTime.format(o.createdAt.toLocal())),
              _Line(
                label: s.t('ad_destination'),
                value: o.destinationType == 'external' ? (o.destinationUrl ?? '—') : s.t('ad_destination_profile'),
              ),
              if (o.targetCountries.isNotEmpty) _Line(label: s.t('ad_targeting'), value: o.targetCountries.join(', ')),
              if ((o.routeFrom ?? '').isNotEmpty || (o.routeTo ?? '').isNotEmpty)
                _Line(label: s.t('adv_route'), value: '${o.routeFrom ?? '—'} → ${o.routeTo ?? '—'}'),
              if (stats != null)
                _Line(label: s.t('ad_stats'), value: '${stats.impressions} ${s.t('ad_views')} · ${stats.clicks} ${s.t('ad_clicks')}'),
              if (stage == AdStage.rejected && (o.adminNote ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                _Notice(color: AppColors.danger, icon: Icons.block, text: '${s.t('adv_reject_reason')}: ${o.adminNote}'),
              ],
              if (stage == AdStage.awaitingPayment) ...[
                const SizedBox(height: 18),
                Text(s.t('adv_pay_title').toUpperCase(), style: adSectionHeader),
                const SizedBox(height: 8),
                _PaymentCard(order: o, s: s),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _uploadReceipt(s, o),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.receipt_long),
                  label: Text(s.t('adv_upload_receipt')),
                ),
                const SizedBox(height: 6),
                Text(s.t('adv_receipt_note'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
              ],
              if (stage == AdStage.reviewing) ...[
                const SizedBox(height: 14),
                _Notice(color: AppColors.blue, icon: Icons.hourglass_top, text: s.t('adv_reviewing_note')),
              ],
              if (o.receiptPath != null) ...[
                const SizedBox(height: 14),
                Text(s.t('adv_receipt').toUpperCase(), style: adSectionHeader),
                const SizedBox(height: 8),
                _ReceiptPreview(path: o.receiptPath!),
                if (stage == AdStage.reviewing)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _uploadReceipt(s, o),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(s.t('adv_replace_receipt')),
                  ),
              ],
              if ((stage == AdStage.awaitingPayment || stage == AdStage.reviewing) && o.paymentStatus != 'paid') ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : () => _cancel(s, o),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: Text(s.t('ad_cancel_order')),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  const _Line({required this.label, required this.value, this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: AppColors.textSoft, fontSize: 13))),
          Expanded(
            child: Text(value,
                style: TextStyle(fontSize: strong ? 17 : 13.5, fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Notice({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, height: 1.35))),
        ],
      ),
    );
  }
}

/// Amount, order number (to write in the transfer) and the admin's bank /
/// card details, with copy buttons.
class _PaymentCard extends ConsumerWidget {
  final AdOrder order;
  final AppStrings s;
  const _PaymentCard({required this.order, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(adPaymentInfoProvider);
    void copy(String text) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('adv_copied'))));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('adv_amount'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                    Text(adMoney(order.price, order.currency), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(s.t('adv_pay_reference'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  InkWell(
                    onTap: () => copy(order.number),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(order.number, style: AppFonts.mono(size: 16, color: AppColors.accent)),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy, size: 14, color: AppColors.textSoft),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 22, color: AppColors.line),
          info.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text(s.t('ad_payment_info_missing')),
            data: (text) => text == null
                ? Text(s.t('ad_payment_info_missing'), style: const TextStyle(color: AppColors.textSoft))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(text, style: const TextStyle(height: 1.45)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => copy(text),
                          icon: const Icon(Icons.copy, size: 16),
                          label: Text(s.t('adv_copy')),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptPreview extends ConsumerWidget {
  final String path;
  const _ReceiptPreview({required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(adReceiptUrlProvider(path));
    return url.when(
      loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Icon(Icons.receipt_long, size: 40, color: AppColors.textSoft),
      data: (u) => GestureDetector(
        onTap: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            u,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long, size: 40, color: AppColors.textSoft),
          ),
        ),
      ),
    );
  }
}

/// Ödəniş gözlənilir → Yoxlanılır → Təsdiqləndi / Rədd edildi →
/// Planlaşdırılıb → Aktivdir → Bitib.
class _Timeline extends StatelessWidget {
  final AdStage stage;
  final AppStrings s;
  const _Timeline({required this.stage, required this.s});

  @override
  Widget build(BuildContext context) {
    final rejected = stage == AdStage.rejected;
    final steps = <(String, int)>[
      ('adv_stage_payment', 0),
      ('adv_stage_reviewing', 1),
      (rejected ? 'adv_stage_rejected' : 'adv_stage_approved', 2),
      ('adv_stage_scheduled', 3),
      ('adv_stage_live', 4),
      ('adv_stage_ended', 5),
    ];
    final current = switch (stage) {
      AdStage.awaitingPayment => 0,
      AdStage.reviewing => 1,
      AdStage.approved || AdStage.rejected => 2,
      AdStage.scheduled => 3,
      AdStage.live => 4,
      AdStage.ended => 5,
      AdStage.cancelled => -1,
    };
    if (stage == AdStage.cancelled) {
      return _Notice(color: AppColors.danger, icon: Icons.cancel_outlined, text: s.t('adv_stage_cancelled'));
    }
    return Column(
      children: [
        for (final (key, i) in steps)
          if (!(rejected && i > 2))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    i < current
                        ? Icons.check_circle
                        : (i == current ? (rejected ? Icons.cancel : Icons.radio_button_checked) : Icons.radio_button_unchecked),
                    size: 20,
                    color: i < current
                        ? AppColors.route
                        : (i == current ? (rejected ? AppColors.danger : AppColors.accent) : AppColors.line),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    s.t(key),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: i == current ? FontWeight.w800 : FontWeight.w500,
                      color: i <= current ? AppColors.text : AppColors.textSoft,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

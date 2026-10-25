import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/countries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../ads/data/ads_repository.dart';
import '../../ads/presentation/ads_providers.dart';
import '../data/admin_repository.dart';
import 'admin_providers.dart';
import 'admin_ad_templates.dart';
import '../../ads/presentation/ad_create_screen.dart';
import '../../ads/presentation/ad_creative_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'admin_widgets.dart';

const _orderStatusLabels = {
  'pending_payment': 'Ödəniş gözlənilir',
  'awaiting_approval': 'Qəbz göndərilib — yoxlayın',
  'approved': 'Təsdiqləndi — reklam yaradılmayıb',
  'rejected': 'Rədd edildi',
  'active': 'Reklam yaradılıb',
  'expired': 'Bitib',
  'cancelled': 'Ləğv edilib',
};
const _payLabels = {
  'unpaid': 'Ödənilməyib',
  'submitted': 'Müştəri "ödədim" bildirib',
  'paid': 'Ödəniş təsdiqlənib',
  'refunded': 'Geri qaytarılıb',
};

Color _orderColor(String s) => switch (s) {
      'awaiting_approval' => AppColors.blue,
      'approved' => AppColors.accent,
      'active' => AppColors.online,
      'rejected' || 'cancelled' => AppColors.danger,
      _ => AppColors.textSoft,
    };

String _money(double v, String c) => '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)} $c';

/// Admin: full editor for an order / its published ad (banner, link,
/// countries, route, dates) — the same editor the customer uses.
Future<void> openAdminAdEditor(BuildContext context, String orderId) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => AdCreateScreen(adminOrderId: orderId)),
  );
}

AdsRepository _repo(BuildContext context) => ProviderScope.containerOf(context, listen: false).read(adsRepositoryProvider);

String _name(Map<String, JsonRow> users, String id) {
  final u = users[id];
  final n = (u?['full_name'] as String?)?.trim() ?? '';
  return n.isEmpty ? (u?['email'] as String? ?? shortId(id)) : n;
}

/// Admin → Reklamlar: orders (approve / reject / publish), ads (image,
/// dates, on/off) and packages + payment instructions.
class AdminAdsPage extends ConsumerStatefulWidget {
  const AdminAdsPage({super.key});
  @override
  ConsumerState<AdminAdsPage> createState() => _AdminAdsPageState();
}

class _AdminAdsPageState extends ConsumerState<AdminAdsPage> {
  String _tab = 'orders';
  String _filter = 'waiting';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text('Reklamlar', style: AppFonts.display(size: 26, color: AppColors.text)),
        const SizedBox(height: 4),
        Text('Banner ölçüsü: ${AdBannerSpec.width}×${AdBannerSpec.height} px (3:1). Yük siyahısındakı yeri və müddəti: "Reklamın yeri və müddəti" → Tənzimlə.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
        const SizedBox(height: 12),
        const HomeAdsSwitchCard(),
        const SizedBox(height: 12),
        FilterBar(
          options: const {'orders': 'Sifarişlər', 'ads': 'Reklamlar', 'templates': 'Şablonlar', 'settings': 'Qiymətlər və ödəniş'},
          selected: _tab,
          onSelected: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 12),
        if (_tab == 'orders') ..._orders(context),
        if (_tab == 'ads') ..._ads(context),
        if (_tab == 'templates') const AdminTemplatesPanel(),
        if (_tab == 'settings') const _SettingsPanel(),
      ],
    );
  }

  List<Widget> _orders(BuildContext context) {
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    final q = ref.watch(adminSearchProvider);
    final async = ref.watch(adminAdOrdersProvider);
    final all = async.valueOrNull ?? const <AdOrder>[];
    final list = all.where((o) {
      final ok = switch (_filter) {
        'waiting' => o.status == 'awaiting_approval' || o.status == 'approved',
        'all' => true,
        _ => o.status == _filter,
      };
      return ok && adminMatches(q, [o.id, o.packageName, _name(users, o.advertiserId), o.paymentReference, o.customerNote]);
    }).toList();
    return [
      FilterBar(
        options: {'waiting': 'Diqqət tələb edir', 'all': 'Hamısı', for (final e in _orderStatusLabels.entries) e.key: e.value},
        selected: _filter,
        onSelected: (v) => setState(() => _filter = v),
      ),
      const SizedBox(height: 10),
      if (async.isLoading && all.isEmpty) const Center(child: CircularProgressIndicator()),
      if (async.hasError) EmptyNote('Yüklənmədi — 0015 SQL işə salınıb? (${async.error})'),
      if (!async.isLoading && list.isEmpty && !async.hasError) const EmptyNote('Sifariş yoxdur'),
      for (final o in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: AdminRow(
            leading: Icon(Icons.campaign_outlined, color: AppColors.accent),
            title: '${o.number} · ${_name(users, o.advertiserId)} · ${o.packageName} · ${_money(o.price, o.currency)}',
            subtitle: '${fmtDateTime(o.createdAt.toIso8601String())} · ${_payLabels[o.paymentStatus] ?? o.paymentStatus}'
                '${(o.paymentReference ?? '').isEmpty ? '' : ' · Ref: ${o.paymentReference}'}',
            chips: [AdminChip(_orderStatusLabels[o.status] ?? o.status, color: _orderColor(o.status))],
            onTap: () => _showOrder(context, o.id),
          ),
        ),
    ];
  }

  List<Widget> _ads(BuildContext context) {
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    final async = ref.watch(adminAdsProvider);
    final raw = async.valueOrNull ?? const <Ad>[];
    // Active standard ads first, in the order they appear in the loads list
    // (admin priority, 0026); the rest after them.
    final ordered = [for (final a in raw) if (a.isActive && (a.creative?.isStandard ?? false)) a]
      ..sort((a, b) => a.priority != b.priority ? a.priority.compareTo(b.priority) : a.startsAt.compareTo(b.startsAt));
    final all = [...ordered, ...raw.where((a) => !ordered.contains(a))];
    final stats = ref.watch(myAdStatsProvider).valueOrNull ?? const {};
    return [
      if (ordered.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Sıra: 1-ci reklam yük siyahısındakı 1-ci reklam yerində çıxır, 2-ci — 2-ci yerdə və s. '
              '↑ ↓ ilə dəyişin. Sıra dəyişmə vaxtı: "Reklamın yeri və müddəti" → Tənzimlə.',
              style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
        ),
      // Ads come only from approved customer orders (standard 1200×400 banners).
      if (async.hasError) EmptyNote('Yüklənmədi — 0015 SQL işə salınıb? (${async.error})'),
      if (!async.isLoading && all.isEmpty && !async.hasError) const EmptyNote('Hələ reklam yoxdur'),
      for (final a in all)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (a.creative != null)
                  AdCreativeView(creative: a.creative!)
                else
                  AspectRatio(
                    aspectRatio: AdBannerSpec.ratio,
                    child: Image.network(a.imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))),
                  ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${_name(users, a.advertiserId)}${(a.title ?? '').isEmpty ? '' : ' · ${a.title}'}',
                                style: const TextStyle(fontWeight: FontWeight.w400)),
                          ),
                          if (ordered.contains(a)) ...[
                            AdminChip('Sıra ${ordered.indexOf(a) + 1}', color: AppColors.accent),
                            IconButton(
                              tooltip: 'Yuxarı',
                              visualDensity: VisualDensity.compact,
                              onPressed: ordered.indexOf(a) == 0 ? null : () => _moveAd(context, ordered, ordered.indexOf(a), -1),
                              icon: const Icon(Icons.arrow_upward, size: 18),
                            ),
                            IconButton(
                              tooltip: 'Aşağı',
                              visualDensity: VisualDensity.compact,
                              onPressed: ordered.indexOf(a) == ordered.length - 1 ? null : () => _moveAd(context, ordered, ordered.indexOf(a), 1),
                              icon: const Icon(Icons.arrow_downward, size: 18),
                            ),
                          ],
                          AdminChip(
                            (a.creative?.isStandard ?? false)
                                ? (a.isLive ? 'Yayımda' : (a.isActive ? 'Aktiv (vaxtı deyil)' : 'Dayandırılıb'))
                                : 'Köhnə format',
                            color: a.isLive && (a.creative?.isStandard ?? false)
                                ? AppColors.online
                                : (a.isActive ? AppColors.blue : AppColors.textSoft),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${fmtDateTime(a.startsAt.toUtc().toIso8601String())} → ${fmtDateTime(a.endsAt.toUtc().toIso8601String())}',
                          style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                      Text(
                        '${a.destinationType == 'external' ? (a.destinationUrl ?? '—') : 'FreightLink profili'}'
                        '${a.orderId != null && stats[a.orderId] != null ? ' · ${stats[a.orderId]!.impressions} baxış · ${stats[a.orderId]!.clicks} klik' : ''}',
                        style: TextStyle(color: AppColors.textSoft, fontSize: 12.5),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if ((a.creative?.isStandard ?? false) && a.orderId != null)
                            FilledButton.icon(
                              onPressed: () => openAdminAdEditor(context, a.orderId!),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Redaktə et'),
                            )
                          else if (a.creative?.isStandard ?? false)
                            OutlinedButton.icon(
                              onPressed: () => _editLinkDates(context, a),
                              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                              label: const Text('Link və tarixlər'),
                            ),
                          if (a.isActive || (a.creative?.isStandard ?? false))
                          OutlinedButton.icon(
                            onPressed: () async {
                              final ok = await confirmAction(context, a.isActive ? 'Dayandır' : 'Yenidən aktiv et',
                                  a.isActive ? 'Reklam ana səhifədən götürüləcək.' : 'Reklam tarixləri daxilində ana səhifədə görünəcək.');
                              if (!ok || !context.mounted) return;
                              await runAdmin(context, () => _repo(context).setAdActive(a.id, !a.isActive));
                            },
                            icon: Icon(a.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                            label: Text(a.isActive ? 'Dayandır' : 'Yenidən aktiv et'),
                          ),
                          _BlueTickButton(userId: a.advertiserId, verified: users[a.advertiserId]?['is_verified'] == true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// Admin: move one ad up / down in the loads-list order.
  Future<void> _moveAd(BuildContext context, List<Ad> ordered, int i, int delta) async {
    final ids = [for (final a in ordered) a.id];
    final j = i + delta;
    if (j < 0 || j >= ids.length) return;
    final t = ids[i];
    ids[i] = ids[j];
    ids[j] = t;
    final ok = await runAdmin(context, () => _repo(context).setAdsOrder(ids), success: 'Sıra dəyişdi');
    if (ok && mounted) ref.invalidate(liveAdsProvider);
  }

  /// Admin: change where the ad leads and when it runs.
  Future<void> _editLinkDates(BuildContext context, Ad a) async {
    var type = a.destinationType;
    final url = TextEditingController(text: a.destinationUrl ?? '');
    var start = a.startsAt;
    var end = a.endsAt;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> pick(bool isStart) async {
            final cur = isStart ? start : end;
            final d = await showDatePicker(
              context: ctx,
              initialDate: cur,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 400)),
            );
            if (d == null) return;
            setState(() {
              final v = DateTime(d.year, d.month, d.day, cur.hour, cur.minute);
              if (isStart) {
                start = v;
              } else {
                end = v;
              }
            });
          }

          return AlertDialog(
            title: const Text('Link və tarixlər'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'profile', label: Text('Profil')),
                      ButtonSegment(value: 'external', label: Text('Xarici link')),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) => setState(() => type = v.first),
                  ),
                  if (type == 'external')
                    TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'https://…')),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () => pick(true), child: Text('Başlama: ${fmtDate(start.toUtc().toIso8601String())}')),
                  OutlinedButton(onPressed: () => pick(false), child: Text('Bitmə: ${fmtDate(end.toUtc().toIso8601String())}')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yadda saxla')),
            ],
          );
        },
      ),
    );
    final link = url.text.trim();
    Future.delayed(const Duration(seconds: 1), url.dispose);
    if (save != true || !context.mounted) return;
    await runAdmin(
      context,
      () => _repo(context).updateAdLinkDates(a.id,
          destinationType: type, destinationUrl: type == 'external' ? link : null, startsAt: start, endsAt: end),
    );
  }

  Future<void> _showOrder(BuildContext context, String id) {
    return showDetail(context, title: 'Reklam sifarişi', body: (ctx) {
      return Consumer(builder: (ctx, ref, _) {
        AdOrder? found;
        for (final x in ref.watch(adminAdOrdersProvider).valueOrNull ?? const <AdOrder>[]) {
          if (x.id == id) found = x;
        }
        if (found == null) return const EmptyNote('Sifariş tapılmadı');
        final o = found;
        final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
        final u = users[o.advertiserId];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              AdminChip(_orderStatusLabels[o.status] ?? o.status, color: _orderColor(o.status)),
              if (o.editedAfterReceiptAt != null)
                AdminChip('Qəbzdən sonra dəyişdirilib (${fmtDateTime(o.editedAfterReceiptAt!.toUtc().toIso8601String())})', color: AppColors.accent),
              if (o.creative != null && !o.creative!.isStandard) const AdminChip('Köhnə format — yayımlanmır'),
            ]),
            const SizedBox(height: 8),
            KV('Sifariş №', o.number),
            KV('Reklam verən', _name(users, o.advertiserId)),
            KV('Telefon', u?['phone']),
            KV('E-poçt', u?['email']),
            KV('Paket', '${o.packageName} (${o.days} gün)'),
            KV('Başlıq', o.title),
            KV('Keçid', switch (o.destinationType) {
              'external' => o.destinationUrl,
              'service' => 'Servis profili (servis reklamı)',
              _ => 'FreightLink profili',
            }),
            KV('Hədəf ölkələr', o.targetCountries.isEmpty ? 'Hamısı' : o.targetCountries.join(', ')),
            if (((o.routeFrom ?? '').isNotEmpty && Countries.find(o.routeFrom) == null) ||
                ((o.routeTo ?? '').isNotEmpty && Countries.find(o.routeTo) == null))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('⚠ Marşrut tanınmır — reklam heç bir yükdə görünməyəcək. "Redaktə et" ilə düzəldin.',
                    style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w400)),
              ),
            if ((o.routeFrom ?? '').isNotEmpty || (o.routeTo ?? '').isNotEmpty)
              KV('Hədəf marşrut', '${o.routeFrom ?? '—'} → ${o.routeTo ?? '—'}'),
            if (o.startsOn != null) KV('Başlama tarixi', fmtDate(o.startsOn!.toIso8601String())),
            if (o.adStartsAt != null && o.adEndsAt != null)
              KV('Yayım', '${fmtDateTime(o.adStartsAt!.toUtc().toIso8601String())} → ${fmtDateTime(o.adEndsAt!.toUtc().toIso8601String())}'),
            if (o.creative != null) ...[
              const SizedBox(height: 10),
              AdCreativeView(creative: o.creative!, radius: BorderRadius.circular(10)),
            ] else if (o.imageUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(aspectRatio: AdBannerSpec.ratio, child: Image.network(o.imageUrl!, fit: BoxFit.cover)),
              ),
            ],
            KV('Məbləğ', _money(o.price, o.currency)),
            if (o.receiptPath != null) ...[
              const SizedBox(height: 8),
              Text('Qəbz (müştəri yükləyib — pulu bankda yoxlayın):', style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
              const SizedBox(height: 6),
              Consumer(builder: (ctx, ref, _) {
                final url = ref.watch(adReceiptUrlProvider(o.receiptPath!));
                return url.when(
                  loading: () => const SizedBox(height: 60, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('Qəbz açılmadı: $e', style: TextStyle(color: AppColors.danger)),
                  data: (u) => GestureDetector(
                    onTap: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(u, height: 220, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => TextButton(
                              onPressed: () => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication),
                              child: const Text('Qəbzi aç'))),
                    ),
                  ),
                );
              }),
              if (o.receiptUploadedAt != null) KV('Qəbz yüklənib', fmtDateTime(o.receiptUploadedAt!.toUtc().toIso8601String())),
            ],
            KV('Ödəniş', _payLabels[o.paymentStatus] ?? o.paymentStatus),
            KV('Ödəniş referansı', o.paymentReference),
            KV('Müştərinin qeydi', o.customerNote),
            KV('Admin qeydi', o.adminNote),
            KV('Yaradılıb', fmtDateTime(o.createdAt.toIso8601String())),
            KV('ID', o.id),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (o.creative != null && o.status == 'awaiting_approval' && o.receiptPath != null)
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await confirmAction(ctx, 'Ödəniş təsdiqi',
                            'Məbləğ (${_money(o.price, o.currency)}) bank hesabınıza daxil olub? Təsdiqdən sonra reklam dərhal başlayacaq və ${o.days} gün göstəriləcək (köhnə sifarişdə gələcək tarix seçilibsə — həmin tarixdə).');
                        if (!ok || !ctx.mounted) return;
                        await runAdmin(ctx, () => _repo(ctx).reviewOrder(o.id, approve: true), success: 'Təsdiqləndi — reklam planlaşdırıldı');
                      },
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('Ödəniş yoxlanıldı — təsdiqlə'),
                    ),
                  if (o.creative != null && o.status != 'rejected' && o.status != 'active' && o.status != 'cancelled')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        final note = await askText(ctx, 'Rədd etmə səbəbi (müştəri görəcək)', required: true);
                        if (note == null || !ctx.mounted) return;
                        await runAdmin(ctx, () => _repo(ctx).reviewOrder(o.id, approve: false, note: note), success: 'Rədd edildi');
                      },
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Rədd et'),
                    ),
                  if (o.creative == null && o.paymentStatus != 'paid' && o.status != 'rejected' && o.status != 'cancelled')
                    FilledButton.icon(
                      onPressed: () async {
                        final ok = await confirmAction(ctx, 'Ödəniş və təsdiq',
                            'Ödənişin hesabınıza daxil olduğunu yoxladınız? Sifariş "təsdiqləndi" olacaq. Reklam yalnız siz banneri əlavə edib aktiv etdikdən sonra görünəcək.');
                        if (!ok || !ctx.mounted) return;
                        await runAdmin(ctx, () => _repo(ctx).updateOrder(o.id, status: 'approved', paymentStatus: 'paid'));
                      },
                      icon: const Icon(Icons.verified_outlined, size: 18),
                      label: const Text('Ödəniş alındı + təsdiqlə'),
                    ),
                  if (o.paymentStatus == 'paid' && o.status == 'approved')
                    FilledButton.icon(
                      onPressed: () => _editAd(ctx, order: o, advertiserId: o.advertiserId),
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('Banner əlavə et və yayımla'),
                    ),
                  if (o.creative == null && o.status != 'rejected' && o.status != 'active' && o.status != 'cancelled')
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        final note = await askText(ctx, 'Rədd etmə səbəbi (müştəri görəcək)', required: true);
                        if (note == null || !ctx.mounted) return;
                        await runAdmin(ctx, () => _repo(ctx).updateOrder(o.id, status: 'rejected', note: note));
                      },
                      icon: const Icon(Icons.block, size: 18),
                      label: const Text('Rədd et'),
                    ),
                  if ((o.creative?.isStandard ?? false) && o.status != 'rejected' && o.status != 'cancelled')
                    OutlinedButton.icon(
                      onPressed: () => openAdminAdEditor(ctx, o.id),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(o.status == 'active' ? 'Reklamı redaktə et' : 'Sifarişi redaktə et'),
                    ),
                  _BlueTickButton(userId: o.advertiserId, verified: u?['is_verified'] == true),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final note = await askText(ctx, 'Admin qeydi (müştəri görəcək)', initial: o.adminNote ?? '');
                      if (note == null || !ctx.mounted) return;
                      await runAdmin(ctx, () => _repo(ctx).updateOrder(o.id, note: note));
                    },
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: const Text('Qeyd'),
                  ),
                  if (o.paymentStatus == 'paid')
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await confirmAction(ctx, 'Geri qaytarıldı', 'Ödənişi "geri qaytarılıb" kimi işarələmək?');
                        if (!ok || !ctx.mounted) return;
                        await runAdmin(ctx, () => _repo(ctx).updateOrder(o.id, paymentStatus: 'refunded', status: 'cancelled'));
                      },
                      child: const Text('Geri qaytarıldı'),
                    ),
                ],
              ),
            ),
          ],
        );
      });
    });
  }

  Future<void> _editAd(BuildContext context, {Ad? ad, AdOrder? order, required String? advertiserId}) async {
    await showDialog(
      context: context,
      builder: (_) => _AdEditor(ad: ad, order: order, advertiserId: advertiserId),
    );
  }
}

/// Create / edit one banner: image (auto-cropped to the banner format), title,
/// start / end, active.
class _AdEditor extends ConsumerStatefulWidget {
  final Ad? ad;
  final AdOrder? order;
  final String? advertiserId;
  const _AdEditor({this.ad, this.order, this.advertiserId});

  @override
  ConsumerState<_AdEditor> createState() => _AdEditorState();
}

class _AdEditorState extends ConsumerState<_AdEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.ad?.title ?? widget.order?.title ?? '');
  String? _imageUrl;
  String? _advertiserId;
  late DateTime _start;
  late DateTime _end;
  late bool _active;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.ad?.imageUrl ?? widget.order?.imageUrl;
    _advertiserId = widget.advertiserId;
    final now = DateTime.now();
    _start = widget.ad?.startsAt ?? DateTime(now.year, now.month, now.day);
    _end = widget.ad?.endsAt ?? _start.add(Duration(days: widget.order?.days ?? 7));
    _active = widget.ad?.isActive ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _error = null);
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'], withData: true);
    final f = res?.files.single;
    final bytes = f?.bytes;
    if (f == null || bytes == null) return;
    // Any photo works: it is centre-cropped to the banner ratio and
    // resized to exactly the banner size, so no editor is needed.
    Uint8List upload = bytes;
    var ext = f.extension ?? 'jpg';
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final w = img.width, h = img.height;
      if (w < 600 || h < 130) {
        setState(() => _error = 'Şəkil çox kiçikdir: $w×$h px. Ən az 600×130 px olmalıdır.');
        return;
      }
      final exact = w == AdBannerSpec.width && h == AdBannerSpec.height;
      if (!exact) {
        upload = await _cropToBanner(img);
        ext = 'png';
      }
    } catch (_) {
      setState(() => _error = 'Şəkil oxunmadı.');
      return;
    }
    if (upload.length > 5 * 1024 * 1024) {
      setState(() => _error = 'Şəkil 5 MB-dan böyükdür. Daha kiçik şəkil seçin.');
      return;
    }
    setState(() => _busy = true);
    try {
      final url = await ref.read(adsRepositoryProvider).uploadBanner(upload, ext);
      setState(() => _imageUrl = url);
    } catch (e) {
      setState(() => _error = 'Yükləmə alınmadı: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Centre-crops [img] to the banner ratio and draws it at banner size (PNG bytes).
  Future<Uint8List> _cropToBanner(ui.Image img) async {
    final w = img.width.toDouble(), h = img.height.toDouble();
    const target = AdBannerSpec.ratio;
    late Rect src;
    if (w / h > target) {
      final cw = h * target; // too wide → cut the sides
      src = Rect.fromLTWH((w - cw) / 2, 0, cw, h);
    } else {
      final ch = w / target; // too tall → cut top and bottom
      src = Rect.fromLTWH(0, (h - ch) / 2, w, ch);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dst = Rect.fromLTWH(0, 0, AdBannerSpec.width.toDouble(), AdBannerSpec.height.toDouble());
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.high);
    final out = await recorder.endRecording().toImage(AdBannerSpec.width, AdBannerSpec.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _pickDate(bool start) async {
    final cur = start ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
      } else {
        _end = d;
      }
    });
  }

  Future<void> _save() async {
    if (_imageUrl == null) {
      setState(() => _error = 'Əvvəlcə banner şəklini yükləyin.');
      return;
    }
    if (_advertiserId == null) {
      setState(() => _error = 'Reklam verəni seçin.');
      return;
    }
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'Bitmə tarixi başlanğıcdan sonra olmalıdır.');
      return;
    }
    final ok = await runAdmin(
      context,
      () => ref.read(adsRepositoryProvider).saveAd(
            adId: widget.ad?.id,
            orderId: widget.ad == null ? widget.order?.id : null,
            advertiserId: _advertiserId!,
            title: _title.text.trim(),
            imageUrl: _imageUrl!,
            startsAt: _start,
            endsAt: _end,
            active: _active,
          ),
      success: 'Reklam yadda saxlanıldı',
    );
    if (ok && mounted) {
      ref.invalidate(liveAdsProvider);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider).valueOrNull ?? const <JsonRow>[];
    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return AlertDialog(
      title: Text(widget.ad == null ? 'Yeni reklam' : 'Reklamı redaktə et'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: AdBannerSpec.ratio,
                  child: _imageUrl == null
                      ? Container(
                          color: AppColors.cardAlt,
                          alignment: Alignment.center,
                          child: Text('${AdBannerSpec.width} × ${AdBannerSpec.height}',
                              style: TextStyle(color: AppColors.textSoft)),
                        )
                      : Image.network(_imageUrl!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_outlined),
                label: Text(_imageUrl == null ? 'Banner şəklini yüklə' : 'Şəkli dəyiş'),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('İstənilən şəkil olar — avtomatik ortadan kəsilib 1350×300 edilir. Vacib yazını ortaya qoyun; sol yuxarı küncdə "SPONSORLU", sağ yuxarıda mavi tık olur.',
                    style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              if (widget.order == null && widget.ad == null)
                DropdownButtonFormField<String>(
                  value: _advertiserId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reklam verən (profil)'),
                  items: [
                    for (final u in users)
                      DropdownMenuItem(
                        value: u['id'] as String,
                        child: Text('${u['full_name'] ?? ''} · ${u['email'] ?? ''}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _advertiserId = v),
                ),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Qısa başlıq (istəyə bağlı)')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => _pickDate(true), child: Text('Başlanğıc: ${fmt(_start)}')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(onPressed: () => _pickDate(false), child: Text('Bitmə: ${fmt(_end)}')),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktiv'),
                subtitle: const Text('Söndürülü olsa, reklam görünməyəcək'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ləğv et')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Yadda saxla')),
      ],
    );
  }
}

/// Package prices / durations / on-off and the payment instructions
/// customers see after ordering.
class _SettingsPanel extends ConsumerStatefulWidget {
  const _SettingsPanel();
  @override
  ConsumerState<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<_SettingsPanel> {
  final _payCtrl = TextEditingController();
  bool _payLoaded = false;

  @override
  void dispose() {
    _payCtrl.dispose();
    super.dispose();
  }

  Future<void> _editPackage(AdPackage p) async {
    final name = TextEditingController(text: p.name);
    final days = TextEditingController(text: '${p.days}');
    final price = TextEditingController(text: p.price == 0 ? '' : '${p.price}');
    var active = p.isActive;
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Paket: ${p.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad')),
              TextField(controller: days, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Gün sayı')),
              TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Qiymət (${p.currency})')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Müştərilərə göstər'),
                value: active,
                onChanged: (v) => setState(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yadda saxla')),
          ],
        ),
      ),
    );
    if (save == true && mounted) {
      final d = int.tryParse(days.text.trim());
      final pr = double.tryParse(price.text.trim().replaceAll(',', '.'));
      if (d == null || d <= 0 || pr == null || pr < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gün və qiymət düzgün deyil')));
      } else {
        final ok = await runAdmin(
          context,
          () => ref.read(adsRepositoryProvider).savePackage(AdPackage(
                id: p.id,
                name: name.text.trim().isEmpty ? p.name : name.text.trim(),
                days: d,
                price: pr,
                currency: p.currency,
                isActive: active,
                sort: p.sort,
              )),
        );
        if (ok) ref.invalidate(adminAdPackagesProvider);
      }
    }
    name.dispose();
    days.dispose();
    price.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pk = ref.watch(adminAdPackagesProvider);
    if (!_payLoaded) {
      _payLoaded = true;
      ref.read(adsRepositoryProvider).paymentInfo().then((v) {
        if (mounted && v != null) _payCtrl.text = v;
      }).catchError((_) {});
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Qiymətlər (5 / 15 / 30 gün)'),
        Text('"Reklam yarat"-da müştəri yalnız 5, 15 və 30 günlük paketləri görür. Qiyməti yazın və "Müştərilərə göstər"-i açın — qiyməti 0 olan paket göstərilmir.',
            style: TextStyle(color: AppColors.textSoft, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 8),
        pk.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyNote('Yüklənmədi — 0015 SQL işə salınıb? ($e)'),
          data: (list) => Column(
            children: [
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AdminRow(
                    title: '${p.name} · ${p.days} gün',
                    subtitle: p.price == 0 ? 'Qiymət təyin edilməyib' : _money(p.price, p.currency),
                    chips: [AdminChip(p.isActive ? 'Müştərilərə görünür' : 'Gizli', color: p.isActive ? AppColors.online : AppColors.textSoft)],
                    onTap: () => _editPackage(p),
                  ),
                ),
            ],
          ),
        ),
        const SectionTitle('Ödəniş məlumatı (müştəri sifarişdən sonra görür)'),
        TextField(
          controller: _payCtrl,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Məs.: Kart nömrəsi, bank hesabı, alıcının adı, təyinat…'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => runAdmin(context, () => ref.read(adsRepositoryProvider).setPaymentInfo(_payCtrl.text.trim())),
            child: const Text('Yadda saxla'),
          ),
        ),
      ],
    );
  }
}

/// Gives / removes the blue "verified" tick of a user (admin_update_user,
/// server-checked and audit-logged). Shown on ads and orders.
class _BlueTickButton extends StatelessWidget {
  final String userId;
  final bool verified;
  const _BlueTickButton({required this.userId, required this.verified});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1D9BF0);
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: verified ? AppColors.textSoft : blue, side: BorderSide(color: verified ? AppColors.line : blue)),
      onPressed: () async {
        final ok = await confirmAction(
          context,
          verified ? 'Mavi tıkı götür' : 'Mavi tık ver',
          verified
              ? 'Bu istifadəçinin mavi tıkı götürüləcək (profildə, mesajlarda və reklamda görünməyəcək).'
              : 'Bu istifadəçi "təsdiqlənmiş" olacaq: mavi tık profildə, mesajlarda və reklamın sağ üst küncündə görünəcək.',
        );
        if (!ok || !context.mounted) return;
        await runAdmin(
          context,
          () => ProviderScope.containerOf(context, listen: false)
              .read(adminRepositoryProvider)
              .updateUser(userId, {'is_verified': !verified}),
          success: verified ? 'Mavi tık götürüldü' : 'Mavi tık verildi',
        );
      },
      icon: Icon(Icons.verified, size: 18, color: verified ? AppColors.textSoft : blue),
      label: Text(verified ? 'Mavi tıkı götür' : 'Mavi tık ver'),
    );
  }
}

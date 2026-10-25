import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/admin_repository.dart';
import 'admin_providers.dart';
import 'admin_widgets.dart';
import '../../cargo/domain/cargo_vip.dart';
import '../../cargo/presentation/providers/cargo_media_providers.dart';

// =====================================================================
// Shared helpers
// =====================================================================

AdminRepository _repo(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false).read(adminRepositoryProvider);

Widget _async<T>(AsyncValue<T> v, Widget Function(T data) builder) => v.when(
      data: builder,
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => EmptyNote(adminErrorText(e)),
    );

/// Standard page frame: title + optional header + list of rows.
class _Page extends StatelessWidget {
  final String title;
  final List<Widget> header;
  final List<Widget> children;
  const _Page({required this.title, this.header = const [], required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(title, style: AppFonts.display(size: 26, color: AppColors.text)),
        const SizedBox(height: 10),
        ...header,
        const SizedBox(height: 8),
        for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 6), child: c),
      ],
    );
  }
}

String _userName(Map<String, JsonRow> users, Object? id) {
  if (id == null) return '—';
  final u = users['$id'];
  if (u == null) return 'İstifadəçi ${shortId(id)}';
  final n = (u['full_name'] as String?)?.trim() ?? '';
  return n.isEmpty ? (u['email'] as String? ?? shortId(id)) : n;
}

String _route(JsonRow? c) {
  if (c == null) return 'Yük (silinib)';
  return '${txt(c['pickup_city'])}, ${txt(c['pickup_country'])} → ${txt(c['destination_city'])}, ${txt(c['destination_country'])}';
}

String _money(Object? amount, Object? currency) {
  if (amount == null) return '—';
  final n = amount is num ? amount : num.tryParse('$amount');
  return '${n == null ? amount : (n % 1 == 0 ? n.toInt() : n)} ${currency ?? 'USD'}';
}

String _tons(Object? kg) {
  final n = kg is num ? kg : num.tryParse('$kg');
  if (n == null) return '—';
  final t = n / 1000;
  return '${t % 1 == 0 ? t.toInt() : t.toStringAsFixed(1)} t';
}

Widget _actions(List<Widget> buttons) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
    );

ButtonStyle get _dangerStyle => OutlinedButton.styleFrom(
      foregroundColor: AppColors.danger,
      side: BorderSide(color: AppColors.danger),
    );

// =====================================================================
// Dashboard
// =====================================================================

class AdminDashboardPage extends ConsumerWidget {
  final ValueChanged<String> onOpenSection;
  const AdminDashboardPage({super.key, required this.onOpenSection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final s = stats.valueOrNull ?? const <String, dynamic>{};
    final query = ref.watch(adminSearchProvider);
    final users = ref.watch(adminUsersProvider).valueOrNull ?? const <JsonRow>[];
    final cargo = ref.watch(adminCargoProvider).valueOrNull ?? const <JsonRow>[];
    final usersById = indexById(users);

    Widget card(String label, String key, IconData icon, {Color? color, String? section}) => StatCard(
          label: label,
          value: stats.hasValue ? (s[key] ?? 0) : null,
          icon: icon,
          color: color,
          onTap: section == null ? null : () => onOpenSection(section),
        );

    return _Page(
      title: 'İdarə paneli',
      header: [
        if (stats.hasError)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: AppColors.urgentBg, borderRadius: BorderRadius.circular(10)),
            child: Text(adminErrorText(stats.error!), style: TextStyle(color: AppColors.urgentFg)),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            card('Ümumi istifadəçi', 'users_total', Icons.people_alt_outlined, section: 'users'),
            card('Yük sahibləri', 'owners', Icons.inventory_2_outlined, section: 'users'),
            card('Daşıyıcılar', 'carriers', Icons.local_shipping_outlined, section: 'carriers'),
            card('Sürücülər', 'drivers', Icons.badge_outlined, section: 'drivers'),
            card('Aktiv yüklər', 'cargo_active', Icons.flag_outlined, color: AppColors.blue, section: 'cargo'),
            card('Prosesdə olan yüklər', 'cargo_in_progress', Icons.sync, section: 'cargo'),
            card('Tamamlanan yüklər', 'cargo_completed', Icons.check_circle_outline, color: AppColors.online, section: 'cargo'),
            card('Ləğv edilən yüklər', 'cargo_cancelled', Icons.cancel_outlined, color: AppColors.danger, section: 'cargo'),
            card('Gizlədilmiş yüklər', 'cargo_hidden', Icons.visibility_off_outlined, color: AppColors.textSoft, section: 'cargo'),
            card('Aktiv daşımalar', 'shipments_active', Icons.route_outlined, color: AppColors.route, section: 'shipments'),
            card('Bütün təkliflər', 'offers_total', Icons.request_quote_outlined, section: 'offers'),
            card('Gözləyən təkliflər', 'offers_pending', Icons.hourglass_empty, color: AppColors.blue, section: 'offers'),
            card('Açıq şikayətlər', 'reports_open', Icons.report_outlined, color: AppColors.danger, section: 'reports'),
            card('Son 24 saat aktiv', 'active_24h', Icons.bolt_outlined, color: AppColors.online, section: 'users'),
            card('Bloklu / deaktiv', 'blocked', Icons.block, color: AppColors.danger, section: 'users'),
            card('Mesaj (7 gün)', 'messages_7d', Icons.chat_bubble_outline, color: AppColors.blue),
          ],
        ),
        const SectionTitle('Dövr üzrə'),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2)},
            children: [
              _tableRow(['', '1 gün', '7 gün', '30 gün'], header: true),
              _tableRow(['Yeni istifadəçi', '${s['users_new_1d'] ?? '…'}', '${s['users_new_7d'] ?? '…'}', '${s['users_new_30d'] ?? '…'}']),
              _tableRow(['Yeni yük', '${s['cargo_new_1d'] ?? '…'}', '${s['cargo_new_7d'] ?? '…'}', '${s['cargo_new_30d'] ?? '…'}']),
            ],
          ),
        ),
        if (query.trim().isNotEmpty) ...[
          SectionTitle('Axtarış: "$query"'),
          ..._searchResults(context, ref, query),
        ],
        const SectionTitle('Son yüklər'),
      ],
      children: [
        for (final c in cargo.take(6)) _cargoRow(context, c, usersById),
        const SectionTitle('Son qeydiyyatlar'),
        for (final u in users.take(6)) _userRow(context, u),
      ],
    );
  }

  TableRow _tableRow(List<String> cells, {bool header = false}) => TableRow(
        children: [
          for (final c in cells)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(c,
                  style: TextStyle(
                    color: header ? AppColors.textSoft : AppColors.text,
                    fontWeight: header ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  )),
            ),
        ],
      );

  List<Widget> _searchResults(BuildContext context, WidgetRef ref, String q) {
    final users = ref.watch(adminUsersProvider).valueOrNull ?? const <JsonRow>[];
    final cargo = ref.watch(adminCargoProvider).valueOrNull ?? const <JsonRow>[];
    final shipments = ref.watch(adminShipmentsProvider).valueOrNull ?? const <JsonRow>[];
    final usersById = indexById(users);
    final cargoById = indexById(cargo);
    final u = users.where((r) => _userMatches(q, r)).take(8).toList();
    final c = cargo.where((r) => _cargoMatches(q, r, usersById)).take(8).toList();
    final sh = shipments.where((r) => adminMatches(q, [r['id'], r['cargo_id'], ...[_route(cargoById['${r['cargo_id']}'])]])).take(5).toList();
    if (u.isEmpty && c.isEmpty && sh.isEmpty) return const [EmptyNote('Heç nə tapılmadı')];
    return [
      for (final r in u) Padding(padding: const EdgeInsets.only(bottom: 6), child: _userRow(context, r)),
      for (final r in c) Padding(padding: const EdgeInsets.only(bottom: 6), child: _cargoRow(context, r, usersById)),
      for (final r in sh)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: AdminRow(
            leading: Icon(Icons.route_outlined, color: AppColors.route),
            title: 'Daşıma · ${_route(cargoById['${r['cargo_id']}'])}',
            subtitle: 'ID ${shortId(r['id'])}',
            chips: [AdminChip.status(r['status'])],
            onTap: () => showShipmentDetail(context, r['id'] as String),
          ),
        ),
    ];
  }
}

bool _userMatches(String q, JsonRow r) =>
    adminMatches(q, [r['id'], r['full_name'], r['email'], r['phone'], roleLabel(r['role'])]);

bool _cargoMatches(String q, JsonRow r, Map<String, JsonRow> users) => adminMatches(q, [
      r['id'],
      r['pickup_city'],
      r['pickup_country'],
      r['destination_city'],
      r['destination_country'],
      r['cargo_type'],
      r['truck_type'],
      r['description'],
      statusLabel(r['status']),
      _userName(users, r['owner_id']),
      users['${r['owner_id']}']?['phone'],
      users['${r['owner_id']}']?['email'],
    ]);

Widget _cargoRow(BuildContext context, JsonRow c, Map<String, JsonRow> users) => AdminRow(
      leading: Icon(Icons.inventory_2_outlined, color: AppColors.accent),
      title: _route(c),
      subtitle: '${_userName(users, c['owner_id'])} · ${_tons(c['weight_kg'])} · ${_money(c['offered_price'], c['currency'])} · '
          'Yükləmə ${fmtDate(c['pickup_date'])} · Yerləşdirilib ${fmtDateTime(c['created_at'])}',
      chips: [
        AdminChip.status(c['status']),
        if (c['is_hidden'] == true) AdminChip('Gizli', color: AppColors.danger),
        if (_vipActive(c)) const AdminChip('VIP', color: AppColors.vipGold),
        if (c['is_demo'] == true) const AdminChip('Demo'),
      ],
      dimmed: c['is_hidden'] == true,
      onTap: () => showCargoDetail(context, c['id'] as String),
    );

Widget _userRow(BuildContext context, JsonRow u) => AdminRow(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.cardAlt,
        backgroundImage: (u['avatar_url'] as String?)?.isNotEmpty == true ? NetworkImage(u['avatar_url'] as String) : null,
        child: (u['avatar_url'] as String?)?.isNotEmpty == true
            ? null
            : Icon(Icons.person_outline, size: 18, color: AppColors.textSoft),
      ),
      title: txt(u['full_name']),
      subtitle: '${txt(u['email'])} · ${txt(u['phone'])} · Qeydiyyat ${fmtDate(u['created_at'])}',
      chips: [
        AdminChip(roleLabel(u['role']), color: u['role'] == 'admin' ? AppColors.accent : AppColors.blue),
        if (u['is_verified'] == true) AdminChip('Təsdiqli ✓', color: AppColors.online),
        if (u['is_blocked'] == true) AdminChip('Bloklu', color: AppColors.danger),
        if (u['is_active'] == false) AdminChip('Deaktiv', color: AppColors.danger),
      ],
      dimmed: u['is_active'] == false,
      onTap: () => showUserDetail(context, u['id'] as String),
    );

// =====================================================================
// Cargo
// =====================================================================

class AdminCargoPage extends ConsumerStatefulWidget {
  const AdminCargoPage({super.key});
  @override
  ConsumerState<AdminCargoPage> createState() => _AdminCargoPageState();
}

class _AdminCargoPageState extends ConsumerState<AdminCargoPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminSearchProvider);
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    final async = ref.watch(adminCargoProvider);
    return _async(async, (rows) {
      final list = rows.where((c) {
        if (_filter == 'hidden') {
          if (c['is_hidden'] != true) return false;
        } else if (_filter == 'vip') {
          if (!_vipActive(c)) return false;
        } else if (_filter != 'all' && c['status'] != _filter) {
          return false;
        }
        return _cargoMatches(q, c, users);
      }).toList();
      return _Page(
        title: 'Yüklər (${list.length})',
        header: [
          // Prices users pay for "VIP et" on their loads (owner, 24.10.2026, 0062).
          const CargoVipPricesCard(),
          const SizedBox(height: 8),
          FilterBar(
            options: {'all': 'Hamısı', for (final s in cargoStatuses) s: statusLabel(s), 'hidden': 'Gizli', 'vip': 'VIP'},
            selected: _filter,
            onSelected: (v) => setState(() => _filter = v),
          ),
        ],
        children: list.isEmpty ? [const EmptyNote('Yük tapılmadı')] : [for (final c in list) _cargoRow(context, c, users)],
      );
    });
  }
}

Future<void> showCargoDetail(BuildContext context, String id) {
  return showDetail(context, title: 'Yük ${shortId(id)}', body: (ctx) {
    return Consumer(builder: (ctx, ref, _) {
      final cargo = indexById(ref.watch(adminCargoProvider).valueOrNull)[id];
      final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
      final offers = (ref.watch(adminOffersProvider).valueOrNull ?? const <JsonRow>[]).where((o) => o['cargo_id'] == id).toList();
      final shipments = (ref.watch(adminShipmentsProvider).valueOrNull ?? const <JsonRow>[]).where((s) => s['cargo_id'] == id).toList();
      final carrierUsers = ref.watch(adminCarrierUserIdsProvider).valueOrNull ?? const <String, String>{};
      if (cargo == null) return const EmptyNote('Bu yük artıq mövcud deyil.');
      final hidden = cargo['is_hidden'] == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, children: [
            AdminChip.status(cargo['status']),
            if (hidden) AdminChip('Gizli', color: AppColors.danger),
            if (_vipActive(cargo))
              AdminChip(cargo['featured_until'] == null ? 'VIP' : 'VIP · ${fmtDate(cargo['featured_until'])}-dək',
                  color: AppColors.vipGold),
          ]),
          const SizedBox(height: 8),
          KV('Marşrut', _route(cargo)),
          KV('Yük sahibi', _userName(users, cargo['owner_id'])),
          KV('Telefon', users['${cargo['owner_id']}']?['phone']),
          KV('E-poçt', users['${cargo['owner_id']}']?['email']),
          KV('Çəki', '${_tons(cargo['weight_kg'])} (${txt(cargo['weight_kg'])} kq)'),
          KV('Həcm', cargo['volume_m3'] == null ? null : '${cargo['volume_m3']} m³'),
          KV('Palet sayı', cargo['pallet_count']),
          KV('Yük növü', cargo['cargo_type']),
          KV('Maşın tipi', cargo['truck_type']),
          const KV('Lazım olan maşın sayı', 'Bazada belə sahə yoxdur'),
          KV('Qiymət', _money(cargo['offered_price'], cargo['currency'])),
          KV('Yükləmə tarixi', fmtDate(cargo['pickup_date'])),
          KV('Çatdırılma son tarixi', fmtDate(cargo['delivery_deadline'])),
          KV('Məsafə', cargo['distance_km'] == null ? null : '${cargo['distance_km']} km'),
          KV('Təsvir', cargo['description']),
          KV('Yerləşdirilib', fmtDateTime(cargo['created_at'])),
          KV('Yenilənib', fmtDateTime(cargo['updated_at'])),
          KV('ID', cargo['id']),
          _actions([
            FilledButton.icon(
              onPressed: () => _editCargo(ctx, cargo),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Redaktə et'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final s = await pickOne(ctx, 'Status', {for (final s in cargoStatuses) s: statusLabel(s)}, current: cargo['status'] as String?);
                if (s == null || s == cargo['status'] || !ctx.mounted) return;
                if (!await confirmAction(ctx, 'Statusu dəyiş', '"${statusLabel(cargo['status'])}" → "${statusLabel(s)}"?')) return;
                if (!ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).updateCargo(id, {'status': s}));
              },
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Statusu dəyiş'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirmAction(
                  ctx,
                  hidden ? 'Yükü aktivləşdir' : 'Yükü gizlət',
                  hidden ? 'Yük yenidən platformada görünəcək.' : 'Yük platformada görünməyəcək (silinmir, istənilən vaxt geri qaytarmaq olar).',
                );
                if (!ok || !ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).setCargoHidden(id, !hidden));
              },
              icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              label: Text(hidden ? 'Aktivləşdir' : 'Gizlət'),
            ),
            // VIP (0059): a gold card in the VIP rows of the Loads page.
            OutlinedButton.icon(
              key: const ValueKey('admin-cargo-vip'),
              onPressed: () async {
                if (_vipActive(cargo)) {
                  if (!await confirmAction(ctx, 'VIP-i götür', 'Bu yük adi yük kimi göstəriləcək.')) return;
                  if (!ctx.mounted) return;
                  await runAdmin(ctx, () => _repo(ctx).setCargoVip(id, false));
                  return;
                }
                final d = await pickOne(ctx, 'VIP müddəti', {'7': '7 gün', '14': '14 gün', '30': '30 gün', '0': 'Müddətsiz'});
                if (d == null || !ctx.mounted) return;
                final days = int.parse(d);
                await runAdmin(ctx, () => _repo(ctx).setCargoVip(id, true,
                    until: days == 0 ? null : DateTime.now().add(Duration(days: days))));
              },
              icon: const Icon(Icons.workspace_premium, size: 18, color: AppColors.vipGold),
              label: Text(_vipActive(cargo) ? 'VIP-i götür' : 'VIP et'),
            ),
            OutlinedButton.icon(
              style: _dangerStyle,
              onPressed: () async {
                final ok = await confirmAction(
                  ctx,
                  'Yükü sil',
                  'Bu yükü silmək istədiyinizə əminsiniz?\n\nBu yükə bağlı ${offers.length} təklif, ${shipments.length} daşıma, '
                      'söhbətlər və mesajlar da silinəcək. Bu əməliyyat geri qaytarıla bilməz. '
                      'Silinmiş yükün tam surəti Audit Log-da saxlanılır.',
                  ok: 'Sil',
                  danger: true,
                );
                if (!ok || !ctx.mounted) return;
                final reason = await askText(ctx, 'Silinmə səbəbi (istəyə bağlı)');
                if (reason == null || !ctx.mounted) return;
                final done = await runAdmin(ctx, () => _repo(ctx).deleteCargo(id, reason.isEmpty ? null : reason), success: 'Yük silindi');
                if (done && ctx.mounted) Navigator.of(ctx).pop();
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Sil'),
            ),
          ]),
          SectionTitle('Təkliflər (${offers.length})'),
          if (offers.isEmpty) Text('Təklif yoxdur', style: TextStyle(color: AppColors.textSoft)),
          for (final o in offers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AdminRow(
                title: '${_userName(users, carrierUsers['${o['carrier_id']}'])} · ${_money(o['offered_price'], o['currency'])}',
                subtitle: '${txt(o['message'])} · ${fmtDateTime(o['created_at'])}',
                chips: [AdminChip.status(o['status'])],
                onTap: () => showOfferDetail(ctx, o['id'] as String),
              ),
            ),
          if (shipments.isNotEmpty) ...[
            const SectionTitle('Daşıma'),
            for (final s in shipments)
              AdminRow(
                title: '${_userName(users, carrierUsers['${s['carrier_id']}'])} · ${_money(s['agreed_price'], s['currency'])}',
                subtitle: 'Yaradılıb ${fmtDateTime(s['created_at'])}',
                chips: [AdminChip.status(s['status'])],
                onTap: () => showShipmentDetail(ctx, s['id'] as String),
              ),
          ],
        ],
      );
    });
  });
}

Future<void> _editCargo(BuildContext context, JsonRow c) async {
  final fields = <String, TextEditingController>{
    'pickup_country': TextEditingController(text: '${c['pickup_country'] ?? ''}'),
    'pickup_city': TextEditingController(text: '${c['pickup_city'] ?? ''}'),
    'destination_country': TextEditingController(text: '${c['destination_country'] ?? ''}'),
    'destination_city': TextEditingController(text: '${c['destination_city'] ?? ''}'),
    'weight_kg': TextEditingController(text: '${c['weight_kg'] ?? ''}'),
    'offered_price': TextEditingController(text: '${c['offered_price'] ?? ''}'),
    'currency': TextEditingController(text: '${c['currency'] ?? 'USD'}'),
    'pickup_date': TextEditingController(text: '${c['pickup_date'] ?? ''}'),
    'cargo_type': TextEditingController(text: '${c['cargo_type'] ?? ''}'),
    'truck_type': TextEditingController(text: '${c['truck_type'] ?? ''}'),
    'description': TextEditingController(text: '${c['description'] ?? ''}'),
  };
  const labels = {
    'pickup_country': 'Yükləmə ölkəsi',
    'pickup_city': 'Yükləmə şəhəri',
    'destination_country': 'Boşaltma ölkəsi',
    'destination_city': 'Boşaltma şəhəri',
    'weight_kg': 'Çəki (kq)',
    'offered_price': 'Qiymət',
    'currency': 'Valyuta',
    'pickup_date': 'Yükləmə tarixi (YYYY-MM-DD)',
    'cargo_type': 'Yük növü',
    'truck_type': 'Maşın tipi',
    'description': 'Təsvir',
  };
  String? error;
  final save = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Yükü redaktə et'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in fields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: e.value,
                      maxLines: e.key == 'description' ? 3 : 1,
                      keyboardType: (e.key == 'weight_kg' || e.key == 'offered_price')
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(labelText: labels[e.key]),
                    ),
                  ),
                if (error != null) Text(error!, style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
          FilledButton(
            onPressed: () {
              final w = num.tryParse(fields['weight_kg']!.text.replaceAll(',', '.'));
              final p = num.tryParse(fields['offered_price']!.text.replaceAll(',', '.'));
              final d = DateTime.tryParse(fields['pickup_date']!.text.trim());
              String? problem;
              if (w == null || w <= 0) {
                problem = 'Çəki düzgün deyil';
              } else if (p == null || p < 0) {
                problem = 'Qiymət düzgün deyil';
              } else if (d == null) {
                problem = 'Tarix YYYY-MM-DD formatında olmalıdır';
              }
              if (problem != null) {
                setState(() => error = problem);
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Yadda saxla'),
          ),
        ],
      ),
    ),
  );
  if (save == true && context.mounted) {
    final patch = <String, dynamic>{
      for (final e in fields.entries) e.key: e.value.text.trim(),
    };
    patch['weight_kg'] = num.parse(fields['weight_kg']!.text.replaceAll(',', '.'));
    patch['offered_price'] = num.parse(fields['offered_price']!.text.replaceAll(',', '.'));
    await runAdmin(context, () => _repo(context).updateCargo(c['id'] as String, patch));
  }
  for (final ctrl in fields.values) {
    ctrl.dispose();
  }
}

// =====================================================================
// Users (also used for Carriers / Drivers with a preset role)
// =====================================================================

class AdminUsersPage extends ConsumerStatefulWidget {
  final String? presetRole;
  const AdminUsersPage({super.key, this.presetRole});
  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminSearchProvider);
    final preset = widget.presetRole;
    return _async(ref.watch(adminUsersProvider), (rows) {
      final list = rows.where((u) {
        if (preset != null && u['role'] != preset) return false;
        switch (_filter) {
          case 'all':
            break;
          case 'blocked':
            if (u['is_blocked'] != true) return false;
            break;
          case 'inactive':
            if (u['is_active'] != false) return false;
            break;
          case 'verified':
            if (u['is_verified'] != true) return false;
            break;
          default:
            if (u['role'] != _filter) return false;
        }
        return _userMatches(q, u);
      }).toList();
      final title = preset == 'carrier' ? 'Daşıyıcılar' : (preset == 'driver' ? 'Sürücülər' : 'İstifadəçilər');
      return _Page(
        title: '$title (${list.length})',
        header: [
          FilterBar(
            options: {
              'all': 'Hamısı',
              if (preset == null) ...{for (final r in roleLabels.entries) r.key: r.value},
              'verified': 'Təsdiqli',
              'blocked': 'Bloklu',
              'inactive': 'Deaktiv',
            },
            selected: _filter,
            onSelected: (v) => setState(() => _filter = v),
          ),
        ],
        children: list.isEmpty ? [const EmptyNote('İstifadəçi tapılmadı')] : [for (final u in list) _userRow(context, u)],
      );
    });
  }
}

Future<void> showUserDetail(BuildContext context, String id) {
  return showDetail(context, title: 'İstifadəçi', body: (ctx) {
    return Consumer(builder: (ctx, ref, _) {
      final u = indexById(ref.watch(adminUsersProvider).valueOrNull)[id];
      if (u == null) return const EmptyNote('İstifadəçi tapılmadı.');
      final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
      final carrierUsers = ref.watch(adminCarrierUserIdsProvider).valueOrNull ?? const <String, String>{};
      final myCarrierIds = carrierUsers.entries.where((e) => e.value == id).map((e) => e.key).toSet();
      final cargo = ref.watch(adminCargoProvider).valueOrNull ?? const <JsonRow>[];
      final cargoById = indexById(cargo);
      final myCargo = cargo.where((c) => c['owner_id'] == id).toList();
      final myCargoIds = myCargo.map((c) => c['id']).toSet();
      final offers = (ref.watch(adminOffersProvider).valueOrNull ?? const <JsonRow>[])
          .where((o) => myCarrierIds.contains(o['carrier_id']))
          .toList();
      final shipments = (ref.watch(adminShipmentsProvider).valueOrNull ?? const <JsonRow>[])
          .where((s) => myCarrierIds.contains(s['carrier_id']) || myCargoIds.contains(s['cargo_id']))
          .toList();
      final blocked = u['is_blocked'] == true;
      final active = u['is_active'] != false;
      final founder = (ref.watch(adminFounderIdsProvider).valueOrNull ?? const <String>{}).contains(id);
      // The founder's account is changed only by the founder (checked on the
      // server too, 0045); other admins see it locked.
      final locked = founder && ref.watch(currentUserIdProvider) != id;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(txt(u['full_name']), style: AppFonts.display(size: 24, color: AppColors.text)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            AdminChip(roleLabel(u['role']), color: AppColors.blue),
            if (founder) AdminChip('Founder 🔒', color: AppColors.accent),
            if (u['is_verified'] == true) AdminChip('Təsdiqli ✓', color: AppColors.online),
            if (blocked) AdminChip('Bloklu', color: AppColors.danger),
            if (!active) AdminChip('Deaktiv', color: AppColors.danger),
          ]),
          const SizedBox(height: 8),
          KV('E-poçt', u['email']),
          KV('Telefon', u['phone']),
          KV('Dil', u['preferred_lang']),
          KV('Qeydiyyat', fmtDateTime(u['created_at'])),
          KV('Son aktivlik', fmtDateTime(u['last_seen_at'])),
          if (blocked) ...[
            KV('Blok müddəti', u['blocked_until'] == null ? 'Müddətsiz' : 'Bitir: ${fmtDateTime(u['blocked_until'])}'),
            KV('Blok səbəbi', u['block_reason']),
          ],
          KV('ID', u['id']),
          if (locked)
            Padding(
              key: const ValueKey('founder-locked'),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('🔒 Founder hesabı: rütbə, mavi tık, blok, deaktiv və silmə yalnız hesabın sahibi tərəfindən dəyişdirilə bilər.',
                  style: TextStyle(color: AppColors.textSoft)),
            )
          else
          _actions([
            FilledButton.icon(
              onPressed: () => _editUser(ctx, u),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Redaktə et'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1D9BF0)),
              onPressed: () async {
                final v = u['is_verified'] == true;
                final ok = await confirmAction(ctx, v ? 'Mavi tıkı götür' : 'Mavi tık ver',
                    v ? 'Mavi tık götürülsün?' : 'Mavi tık profildə, mesajlarda və reklamlarda görünəcək.');
                if (!ok || !ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).updateUser(id, {'is_verified': !v}),
                    success: v ? 'Mavi tık götürüldü' : 'Mavi tık verildi');
              },
              icon: const Icon(Icons.verified, size: 18),
              label: Text(u['is_verified'] == true ? 'Mavi tıkı götür' : 'Mavi tık ver'),
            ),
            if (!blocked)
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await pickOne(ctx, 'Blok müddəti', const {'1': '1 gün', '7': '7 gün', '30': '30 gün', '0': 'Müddətsiz'});
                  if (d == null || !ctx.mounted) return;
                  final reason = await askText(ctx, 'Blok səbəbi', hint: 'Məs.: saxta elan', required: true);
                  if (reason == null || !ctx.mounted) return;
                  final days = int.parse(d);
                  await runAdmin(
                    ctx,
                    () => _repo(ctx).setUserBlock(id, true,
                        until: days == 0 ? null : DateTime.now().add(Duration(days: days)), reason: reason),
                    success: 'İstifadəçi bloklandı',
                  );
                },
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Blokla'),
              )
            else
              OutlinedButton.icon(
                onPressed: () async {
                  if (!await confirmAction(ctx, 'Blokdan çıxar', 'İstifadəçi yenidən yük, təklif və mesaj göndərə biləcək.')) return;
                  if (!ctx.mounted) return;
                  await runAdmin(ctx, () => _repo(ctx).setUserBlock(id, false), success: 'Blok götürüldü');
                },
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Blokdan çıxar'),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirmAction(
                  ctx,
                  active ? 'Hesabı deaktiv et' : 'Hesabı aktiv et',
                  active ? 'Hesab deaktiv olacaq: istifadəçi yeni yük, təklif və mesaj göndərə bilməyəcək.' : 'Hesab yenidən aktiv olacaq.',
                );
                if (!ok || !ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).setUserActive(id, !active));
              },
              icon: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
              label: Text(active ? 'Deaktiv et' : 'Aktiv et'),
            ),
            OutlinedButton.icon(
              style: _dangerStyle,
              onPressed: () async {
                final ok = await confirmAction(
                  ctx,
                  'İstifadəçini sil',
                  'Bu istifadəçini silmək istədiyinizə əminsiniz?\n\nAd, telefon və şəkil silinəcək, hesab bağlanacaq, açıq yükləri gizlədiləcək. '
                      'Keçmiş daşımalar, mesajlar və ödəniş tarixçəsi qorunur (digər istifadəçilərin məlumatı pozulmasın deyə). '
                      'Giriş hesabını (e-poçt) tam silmək yalnız Supabase → Authentication bölməsindən mümkündür.',
                  ok: 'Sil',
                  danger: true,
                );
                if (!ok || !ctx.mounted) return;
                final reason = await askText(ctx, 'Silinmə səbəbi (istəyə bağlı)');
                if (reason == null || !ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).deleteUser(id, reason.isEmpty ? null : reason), success: 'İstifadəçi silindi');
              },
              icon: const Icon(Icons.person_remove_outlined, size: 18),
              label: const Text('Sil'),
            ),
          ]),
          SectionTitle('Yükləri (${myCargo.length})'),
          if (myCargo.isEmpty) Text('Yük yoxdur', style: TextStyle(color: AppColors.textSoft)),
          for (final c in myCargo.take(30)) Padding(padding: const EdgeInsets.only(bottom: 6), child: _cargoRow(ctx, c, users)),
          SectionTitle('Təklifləri (${offers.length})'),
          if (offers.isEmpty) Text('Təklif yoxdur', style: TextStyle(color: AppColors.textSoft)),
          for (final o in offers.take(30))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AdminRow(
                title: _route(cargoById['${o['cargo_id']}']),
                subtitle: '${_money(o['offered_price'], o['currency'])} · ${fmtDateTime(o['created_at'])}',
                chips: [AdminChip.status(o['status'])],
                onTap: () => showOfferDetail(ctx, o['id'] as String),
              ),
            ),
          SectionTitle('Daşımaları (${shipments.length})'),
          if (shipments.isEmpty) Text('Daşıma yoxdur', style: TextStyle(color: AppColors.textSoft)),
          for (final s in shipments.take(30))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AdminRow(
                title: _route(cargoById['${s['cargo_id']}']),
                subtitle: '${_money(s['agreed_price'], s['currency'])} · ${fmtDateTime(s['created_at'])}',
                chips: [AdminChip.status(s['status'])],
                onTap: () => showShipmentDetail(ctx, s['id'] as String),
              ),
            ),
        ],
      );
    });
  });
}

Future<void> _editUser(BuildContext context, JsonRow u) async {
  final name = TextEditingController(text: '${u['full_name'] ?? ''}');
  final phone = TextEditingController(text: '${u['phone'] ?? ''}');
  var role = '${u['role']}';
  var verified = u['is_verified'] == true;
  final save = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('İstifadəçini redaktə et'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad / şirkət adı')),
              const SizedBox(height: 8),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon (+994…)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: roleLabels.containsKey(role) ? role : null,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: [for (final r in roleLabels.entries) DropdownMenuItem(value: r.key, child: Text(r.value))],
                onChanged: (v) => setState(() => role = v ?? role),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Təsdiqlənmiş hesab ✓'),
                value: verified,
                onChanged: (v) => setState(() => verified = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yadda saxla')),
        ],
      ),
    ),
  );
  if (save == true && context.mounted) {
    if (role != u['role'] &&
        !await confirmAction(context, 'Rolu dəyiş', '"${roleLabel(u['role'])}" → "${roleLabel(role)}". Davam edilsin?')) {
      name.dispose();
      phone.dispose();
      return;
    }
    if (context.mounted) {
      await runAdmin(
        context,
        () => _repo(context).updateUser(u['id'] as String, {
          'full_name': name.text.trim(),
          'phone': phone.text.trim(),
          'role': role,
          'is_verified': verified,
        }),
      );
    }
  }
  name.dispose();
  phone.dispose();
}

// =====================================================================
// Shipments
// =====================================================================

class AdminShipmentsPage extends ConsumerStatefulWidget {
  const AdminShipmentsPage({super.key});
  @override
  ConsumerState<AdminShipmentsPage> createState() => _AdminShipmentsPageState();
}

class _AdminShipmentsPageState extends ConsumerState<AdminShipmentsPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminSearchProvider);
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    final cargo = indexById(ref.watch(adminCargoProvider).valueOrNull);
    final carrierUsers = ref.watch(adminCarrierUserIdsProvider).valueOrNull ?? const <String, String>{};
    return _async(ref.watch(adminShipmentsProvider), (rows) {
      final list = rows.where((s) {
        if (_filter != 'all' && s['status'] != _filter) return false;
        final c = cargo['${s['cargo_id']}'];
        return adminMatches(q, [
          s['id'],
          _route(c),
          _userName(users, c?['owner_id']),
          _userName(users, carrierUsers['${s['carrier_id']}']),
          statusLabel(s['status']),
        ]);
      }).toList();
      return _Page(
        title: 'Daşımalar (${list.length})',
        header: [
          FilterBar(
            options: {'all': 'Hamısı', for (final s in cargoStatuses) s: statusLabel(s)},
            selected: _filter,
            onSelected: (v) => setState(() => _filter = v),
          ),
        ],
        children: list.isEmpty
            ? [const EmptyNote('Daşıma tapılmadı')]
            : [
                for (final s in list)
                  AdminRow(
                    leading: Icon(Icons.route_outlined, color: AppColors.route),
                    title: _route(cargo['${s['cargo_id']}']),
                    subtitle: '${_userName(users, cargo['${s['cargo_id']}']?['owner_id'])} → '
                        '${_userName(users, carrierUsers['${s['carrier_id']}'])} · ${_money(s['agreed_price'], s['currency'])} · '
                        '${fmtDateTime(s['created_at'])}',
                    chips: [AdminChip.status(s['status'])],
                    onTap: () => showShipmentDetail(context, s['id'] as String),
                  ),
              ],
      );
    });
  }
}

Future<void> showShipmentDetail(BuildContext context, String id) {
  return showDetail(context, title: 'Daşıma ${shortId(id)}', body: (ctx) {
    return Consumer(builder: (ctx, ref, _) {
      final s = indexById(ref.watch(adminShipmentsProvider).valueOrNull)[id];
      if (s == null) return const EmptyNote('Daşıma tapılmadı.');
      final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
      final c = indexById(ref.watch(adminCargoProvider).valueOrNull)['${s['cargo_id']}'];
      final carrierUsers = ref.watch(adminCarrierUserIdsProvider).valueOrNull ?? const <String, String>{};
      final drivers = ref.watch(adminDriversProvider).valueOrNull ?? const <String, String>{};
      final trucks = ref.watch(adminTrucksProvider).valueOrNull ?? const <String, String>{};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminChip.status(s['status']),
          const SizedBox(height: 8),
          KV('Marşrut', _route(c)),
          KV('Yük sahibi', _userName(users, c?['owner_id'])),
          KV('Daşıyıcı', _userName(users, carrierUsers['${s['carrier_id']}'])),
          KV('Sürücü', s['driver_id'] == null ? 'Təyin edilməyib' : (drivers['${s['driver_id']}'] ?? shortId(s['driver_id']))),
          KV('Maşın', s['truck_id'] == null ? 'Təyin edilməyib' : (trucks['${s['truck_id']}'] ?? shortId(s['truck_id']))),
          KV('Razılaşılan qiymət', _money(s['agreed_price'], s['currency'])),
          KV('Yükləmə vaxtı', fmtDateTime(s['pickup_time'])),
          KV('Son tarix', fmtDateTime(s['delivery_deadline'])),
          KV('Çatdırıldı', fmtDateTime(s['delivered_at'])),
          KV('Yaradılıb', fmtDateTime(s['created_at'])),
          KV('Yenilənib', fmtDateTime(s['updated_at'])),
          KV('ID', s['id']),
          _actions([
            FilledButton.icon(
              onPressed: () async {
                final st = await pickOne(ctx, 'Daşıma statusu', {for (final x in cargoStatuses) x: statusLabel(x)}, current: s['status'] as String?);
                if (st == null || st == s['status'] || !ctx.mounted) return;
                if (!await confirmAction(ctx, 'Statusu dəyiş', '"${statusLabel(s['status'])}" → "${statusLabel(st)}"?')) return;
                if (!ctx.mounted) return;
                final note = await askText(ctx, 'Qeyd (istəyə bağlı)');
                if (note == null || !ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).setShipmentStatus(id, st, note: note.isEmpty ? null : note));
              },
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Statusu dəyiş'),
            ),
            if (c != null)
              OutlinedButton.icon(
                onPressed: () => showCargoDetail(ctx, c['id'] as String),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Yükə bax'),
              ),
          ]),
        ],
      );
    });
  });
}

// =====================================================================
// Offers
// =====================================================================

class AdminOffersPage extends ConsumerStatefulWidget {
  const AdminOffersPage({super.key});
  @override
  ConsumerState<AdminOffersPage> createState() => _AdminOffersPageState();
}

class _AdminOffersPageState extends ConsumerState<AdminOffersPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminSearchProvider);
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    final cargo = indexById(ref.watch(adminCargoProvider).valueOrNull);
    final carrierUsers = ref.watch(adminCarrierUserIdsProvider).valueOrNull ?? const <String, String>{};
    return _async(ref.watch(adminOffersProvider), (rows) {
      final list = rows.where((o) {
        if (_filter != 'all' && o['status'] != _filter) return false;
        return adminMatches(q, [
          o['id'],
          o['message'],
          _route(cargo['${o['cargo_id']}']),
          _userName(users, carrierUsers['${o['carrier_id']}']),
          statusLabel(o['status']),
        ]);
      }).toList();
      return _Page(
        title: 'Təkliflər (${list.length})',
        header: [
          FilterBar(
            options: {'all': 'Hamısı', for (final s in offerStatuses) s: statusLabel(s)},
            selected: _filter,
            onSelected: (v) => setState(() => _filter = v),
          ),
        ],
        children: list.isEmpty
            ? [const EmptyNote('Təklif tapılmadı')]
            : [
                for (final o in list)
                  AdminRow(
                    leading: Icon(Icons.request_quote_outlined, color: AppColors.accent),
                    title: _route(cargo['${o['cargo_id']}']),
                    subtitle: '${_userName(users, carrierUsers['${o['carrier_id']}'])} · ${_money(o['offered_price'], o['currency'])} · '
                        '${fmtDateTime(o['created_at'])}',
                    chips: [AdminChip.status(o['status'])],
                    onTap: () => showOfferDetail(context, o['id'] as String),
                  ),
              ],
      );
    });
  }
}

Future<void> showOfferDetail(BuildContext context, String id) {
  return showDetail(context, title: 'Təklif ${shortId(id)}', body: (ctx) {
    return Consumer(builder: (ctx, ref, _) {
      final o = indexById(ref.watch(adminOffersProvider).valueOrNull)[id];
      if (o == null) return const EmptyNote('Təklif tapılmadı.');
      final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
      final c = indexById(ref.watch(adminCargoProvider).valueOrNull)['${o['cargo_id']}'];
      final carrierUsers = ref.watch(adminCarrierUserIdsProvider).valueOrNull ?? const <String, String>{};
      final trucks = ref.watch(adminTrucksProvider).valueOrNull ?? const <String, String>{};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminChip.status(o['status']),
          const SizedBox(height: 8),
          KV('Yük', _route(c)),
          KV('Yük sahibi', _userName(users, c?['owner_id'])),
          KV('Daşıyıcı', _userName(users, carrierUsers['${o['carrier_id']}'])),
          KV('Təklif qiyməti', _money(o['offered_price'], o['currency'])),
          KV('Yükün qiyməti', c == null ? null : _money(c['offered_price'], c['currency'])),
          KV('Maşın', o['truck_id'] == null ? null : (trucks['${o['truck_id']}'] ?? shortId(o['truck_id']))),
          KV('Mesaj', o['message']),
          KV('Göndərilib', fmtDateTime(o['created_at'])),
          KV('ID', o['id']),
          _actions([
            FilledButton.icon(
              onPressed: () async {
                final st = await pickOne(ctx, 'Təklif statusu', {for (final x in offerStatuses) x: statusLabel(x)}, current: o['status'] as String?);
                if (st == null || st == o['status'] || !ctx.mounted) return;
                if (!await confirmAction(ctx, 'Statusu dəyiş', '"${statusLabel(o['status'])}" → "${statusLabel(st)}"?')) return;
                if (!ctx.mounted) return;
                await runAdmin(ctx, () => _repo(ctx).setOfferStatus(id, st));
              },
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Statusu dəyiş'),
            ),
            if (c != null)
              OutlinedButton.icon(
                onPressed: () => showCargoDetail(ctx, c['id'] as String),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Yükə bax'),
              ),
          ]),
        ],
      );
    });
  });
}

// =====================================================================
// Reports
// =====================================================================

const _targetLabels = {
  'cargo': 'Yük',
  'user': 'İstifadəçi',
  'message': 'Mesaj',
  'offer': 'Təklif',
  'shipment': 'Daşıma',
  'other': 'Digər',
};

class AdminReportsPage extends ConsumerStatefulWidget {
  const AdminReportsPage({super.key});
  @override
  ConsumerState<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends ConsumerState<AdminReportsPage> {
  String _filter = 'open';

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminSearchProvider);
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    return _async(ref.watch(adminReportsProvider), (rows) {
      final list = rows.where((r) {
        if (_filter == 'open' && !(r['status'] == 'new' || r['status'] == 'reviewing')) return false;
        if (_filter != 'open' && _filter != 'all' && r['status'] != _filter) return false;
        return adminMatches(q, [r['id'], r['reason'], r['details'], r['target_id'], _userName(users, r['reporter_id'])]);
      }).toList();
      return _Page(
        title: 'Şikayətlər (${list.length})',
        header: [
          FilterBar(
            options: {'open': 'Açıq', 'all': 'Hamısı', for (final s in reportStatuses) s: statusLabel(s)},
            selected: _filter,
            onSelected: (v) => setState(() => _filter = v),
          ),
        ],
        children: list.isEmpty
            ? [const EmptyNote('Şikayət yoxdur')]
            : [
                for (final r in list)
                  AdminRow(
                    leading: Icon(Icons.report_outlined, color: AppColors.danger),
                    title: txt(r['reason']),
                    subtitle: '${_targetLabels[r['target_type']] ?? txt(r['target_type'])} ${shortId(r['target_id'])} · '
                        '${_userName(users, r['reporter_id'])} · ${fmtDateTime(r['created_at'])}',
                    chips: [AdminChip.status(r['status'])],
                    onTap: () => showReportDetail(context, r['id'] as String),
                  ),
              ],
      );
    });
  }
}

Future<void> showReportDetail(BuildContext context, String id) {
  return showDetail(context, title: 'Şikayət', body: (ctx) {
    return Consumer(builder: (ctx, ref, _) {
      final r = indexById(ref.watch(adminReportsProvider).valueOrNull)[id];
      if (r == null) return const EmptyNote('Şikayət tapılmadı.');
      final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
      final target = '${r['target_id'] ?? ''}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminChip.status(r['status']),
          const SizedBox(height: 8),
          KV('Səbəb', r['reason']),
          KV('Ətraflı', r['details']),
          KV('Obyekt', '${_targetLabels[r['target_type']] ?? txt(r['target_type'])} · ${txt(r['target_id'])}'),
          KV('Şikayətçi', _userName(users, r['reporter_id'])),
          KV('Admin qeydi', r['admin_note']),
          KV('Göndərilib', fmtDateTime(r['created_at'])),
          KV('Yenilənib', fmtDateTime(r['updated_at'])),
          _actions([
            for (final st in reportStatuses)
              if (st != r['status'])
                OutlinedButton(
                  onPressed: () async {
                    final note = await askText(ctx, '"${statusLabel(st)}" — admin qeydi', initial: '${r['admin_note'] ?? ''}');
                    if (note == null || !ctx.mounted) return;
                    await runAdmin(ctx, () => _repo(ctx).setReportStatus(id, st, note: note.isEmpty ? null : note));
                  },
                  child: Text(statusLabel(st)),
                ),
            if (r['target_type'] == 'cargo' && target.isNotEmpty)
              FilledButton.icon(
                onPressed: () => showCargoDetail(ctx, target),
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Yükə bax'),
              ),
            if (r['target_type'] == 'user' && target.isNotEmpty)
              FilledButton.icon(
                onPressed: () => showUserDetail(ctx, target),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('İstifadəçiyə bax'),
              ),
            if (r['reporter_id'] != null)
              OutlinedButton.icon(
                onPressed: () => showUserDetail(ctx, r['reporter_id'] as String),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('Şikayətçi'),
              ),
          ]),
        ],
      );
    });
  });
}

// =====================================================================
// Audit log
// =====================================================================

const _actionLabels = {
  'cargo.update': 'Yük redaktə edildi',
  'cargo.hide': 'Yük gizlədildi',
  'cargo.unhide': 'Yük aktivləşdirildi',
  'cargo.delete': 'Yük silindi',
  'user.update': 'İstifadəçi redaktə edildi',
  'user.block': 'İstifadəçi bloklandı',
  'user.unblock': 'Blok götürüldü',
  'user.activate': 'Hesab aktiv edildi',
  'user.deactivate': 'Hesab deaktiv edildi',
  'user.delete': 'İstifadəçi silindi',
  'shipment.status': 'Daşıma statusu dəyişdi',
  'offer.status': 'Təklif statusu dəyişdi',
  'report.status': 'Şikayət statusu dəyişdi',
  'ad_order.update': 'Reklam sifarişi dəyişdi',
  'ad.create': 'Reklam yaradıldı',
  'ad.update': 'Reklam redaktə edildi',
  'ad.activate': 'Reklam aktiv edildi',
  'ad.deactivate': 'Reklam passiv edildi',
  'ad_package.save': 'Reklam paketi dəyişdi',
  'ad_payment_info.save': 'Ödəniş məlumatı dəyişdi',
};

class AdminAuditPage extends ConsumerWidget {
  const AdminAuditPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(adminSearchProvider);
    final users = indexById(ref.watch(adminUsersProvider).valueOrNull);
    return _async(ref.watch(adminAuditProvider), (rows) {
      final list = rows
          .where((a) => adminMatches(q, [a['action'], _actionLabels[a['action']], a['entity_type'], a['entity_id'], a['note'], _userName(users, a['admin_id'])]))
          .toList();
      return _Page(
        title: 'Audit Log (${list.length})',
        header: [
          Text('Admin tərəfindən edilən bütün dəyişikliklər. Yazılar yalnız serverdə yaradılır və dəyişdirilə bilməz.',
              style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
        ],
        children: list.isEmpty
            ? [const EmptyNote('Hələ heç bir admin əməliyyatı yoxdur')]
            : [
                for (final a in list)
                  AdminRow(
                    leading: Icon(Icons.history, color: AppColors.textSoft),
                    title: _actionLabels[a['action']] ?? txt(a['action']),
                    subtitle: '${_userName(users, a['admin_id'])} · ${txt(a['entity_type'])} ${shortId(a['entity_id'])} · ${fmtDateTime(a['created_at'])}',
                    chips: [if (a['note'] != null) AdminChip('Qeyd: ${a['note']}')],
                    onTap: () => showDetail(context,
                        title: _actionLabels[a['action']] ?? txt(a['action']),
                        body: (ctx) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KV('Admin', _userName(users, a['admin_id'])),
                                KV('Əməliyyat', a['action']),
                                KV('Obyekt', '${txt(a['entity_type'])} · ${txt(a['entity_id'])}'),
                                KV('Vaxt', fmtDateTime(a['created_at'])),
                                KV('Qeyd', a['note']),
                                const SectionTitle('Köhnə dəyər'),
                                _jsonBox(a['old_value']),
                                const SectionTitle('Yeni dəyər'),
                                _jsonBox(a['new_value']),
                              ],
                            )),
                  ),
              ],
      );
    });
  }
}

Widget _jsonBox(Object? v) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
      child: SelectableText(prettyJson(v), style: TextStyle(fontFamily: 'Arial', fontSize: 12, color: AppColors.text)),
    );

// =====================================================================
// System
// =====================================================================

class AdminSystemPage extends ConsumerStatefulWidget {
  const AdminSystemPage({super.key});
  @override
  ConsumerState<AdminSystemPage> createState() => _AdminSystemPageState();
}

class _AdminSystemPageState extends ConsumerState<AdminSystemPage> {
  Duration? _latency;
  String? _pingError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    setState(() => _busy = true);
    try {
      final d = await ref.read(adminRepositoryProvider).ping();
      if (!mounted) return;
      setState(() {
        _latency = d;
        _pingError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pingError = adminErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _status(bool? ok, String okText, String badText) {
    if (ok == null) return const AdminChip('Yoxlanılır…');
    return AdminChip(ok ? okText : badText, color: ok ? AppColors.online : AppColors.danger);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(adminStatsProvider);
    final live = ref.watch(adminCargoProvider);
    String host;
    try {
      host = Uri.parse(Env.supabaseUrl).host;
    } catch (_) {
      host = '—';
    }
    const buildLabel = String.fromEnvironment('BUILD_LABEL', defaultValue: 'web (GitHub Actions)');
    return _Page(
      title: 'Sistem',
      header: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KV('Verilənlər bazası', _status(_busy ? null : _pingError == null, 'İşləyir', 'Əlaqə yoxdur')),
              KV('Cavab müddəti', _latency == null ? (_pingError ?? '…') : '${_latency!.inMilliseconds} ms'),
              KV('Admin funksiyaları (0012)', _status(stats.isLoading ? null : stats.hasValue, 'Quraşdırılıb', 'Tapılmadı — 0012 SQL işə salınmayıb')),
              KV('Realtime', _status(live.isLoading ? null : live.hasValue, 'Qoşulub', 'Qoşulmayıb')),
              KV('Supabase layihəsi', host),
              KV('APP_ENV', Env.appEnv),
              const KV('Build', buildLabel),
              const KV('Xəta jurnalı', 'Hələ qoşulmayıb (Sentry və s. sonrakı mərhələdə)'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () {
                  ref.invalidate(adminStatsProvider);
                  _ping();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Yenidən yoxla'),
              ),
            ],
          ),
        ),
        const SectionTitle('Təhlükəsizlik'),
        Text(
          '• Bütün admin əməliyyatları serverdə is_admin() ilə yoxlanılır (SECURITY DEFINER RPC).\n'
          '• Tətbiqdə service-role açarı yoxdur.\n'
          '• Hər dəyişiklik Audit Log-a yazılır.\n'
          '• Admin rolu yalnız Supabase SQL Editor-dan və ya başqa admin tərəfindən verilir.',
          style: TextStyle(color: AppColors.textSoft, fontSize: 13, height: 1.5),
        ),
      ],
      children: const [],
    );
  }
}

/// VIP is on and its end date (if any) has not passed (0059).
bool _vipActive(JsonRow c) {
  if (c['is_featured'] != true) return false;
  final until = DateTime.tryParse('${c['featured_until'] ?? ''}');
  return c['featured_until'] == null || (until != null && until.isAfter(DateTime.now()));
}

/// Load VIP prices users pay for "VIP et" (0062: 7 / 14 / 30 days, the same
/// start prices as TIR Bazarı). Changed only through
/// admin_cargo_set_vip_plan (checked + logged on the server).
class CargoVipPricesCard extends ConsumerStatefulWidget {
  const CargoVipPricesCard({super.key});

  @override
  ConsumerState<CargoVipPricesCard> createState() => _CargoVipPricesCardState();
}

class _CargoVipPricesCardState extends ConsumerState<CargoVipPricesCard> {
  final _price = <int, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _price.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(CargoVipPlan p, {bool? active}) async {
    final v = double.tryParse((_price[p.days]?.text ?? '').replaceAll(',', '.').trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Qiyməti düzgün yazın (0-dan böyük).')));
      return;
    }
    final ok = await runAdmin(
        context, () => ref.read(cargoMediaRepositoryProvider).adminSetVipPlan(p.days, v, active: active ?? p.isActive));
    if (ok) ref.invalidate(cargoVipPlansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cargoVipPlansProvider(false));
    return Card(
      key: const ValueKey('admin-cargo-vip-prices'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.workspace_premium, color: AppColors.vipGold),
            SizedBox(width: 8),
            Expanded(child: Text('Yük VIP qiymətləri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text('İstifadəçi öz yükündə "VIP et" basanda bu qiymətlərlə kartla ödəyir; ödənişdən sonra yük avtomatik VIP olur.',
              style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
          const SizedBox(height: 8),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('Yüklənmədi (0062_cargo_vip_buy.sql işə salınıbmı?)', style: TextStyle(color: AppColors.danger)),
            data: (plans) => Column(children: [
              for (final p in plans)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(width: 62, child: Text('${p.days} gün', style: const TextStyle(fontWeight: FontWeight.w400))),
                    SizedBox(
                      width: 110,
                      child: TextField(
                        key: ValueKey('cargo-vip-price-${p.days}'),
                        controller: _price.putIfAbsent(
                            p.days, () => TextEditingController(text: p.price.toStringAsFixed(p.price % 1 == 0 ? 0 : 2))),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(isDense: true, suffixText: p.currency),
                      ),
                    ),
                    FilledButton(onPressed: () => _save(p), child: const Text('Saxla')),
                    Switch(value: p.isActive, onChanged: (v) => _save(p, active: v)),
                    Text(p.isActive ? 'Aktiv' : 'Bağlı', style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/service_models.dart';
import '../../services/data/services_repository.dart';
import '../../services/presentation/service_widgets.dart';
import '../../services/presentation/services_providers.dart';
import '../data/admin_repository.dart';
import 'admin_widgets.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/widgets/map_tiles.dart';

/// Badge numbers for the side menu: pending profiles + pending ownership
/// claims + open service complaints.
final adminServiceCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  try {
    return await ref.watch(servicesRepositoryProvider).adminCounts();
  } catch (_) {
    return const {};
  }
});

const _statusLabels = {
  'pending': 'Gözləyir',
  'approved': 'Təsdiqlənib',
  'rejected': 'Rədd edilib',
  'suspended': 'Dayandırılıb',
};

Color _statusColor(String s) => switch (s) {
      'approved' => AppColors.online,
      'pending' => AppColors.accent,
      'rejected' => AppColors.danger,
      _ => AppColors.textSoft,
    };

/// Admin → Servislər: approve / edit / deactivate mechanics and service
/// centres, add existing services, resolve ownership claims and
/// complaints, maintain categories. Every action is a server function
/// that checks is_admin() and writes the audit log.
class AdminServicesPage extends ConsumerStatefulWidget {
  const AdminServicesPage({super.key});

  @override
  ConsumerState<AdminServicesPage> createState() => _AdminServicesPageState();
}

class _AdminServicesPageState extends ConsumerState<AdminServicesPage> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(adminServiceCountsProvider).valueOrNull ?? const {};
    String n(String k) => (counts[k] ?? 0) > 0 ? ' (${counts[k]})' : '';
    return Column(
      children: [
        Material(
          color: AppColors.hero,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Servislər${n('pending')}'),
              Tab(text: 'Sahiblik${n('claims')}'),
              Tab(text: 'Şikayətlər${n('reports')}'),
              const Tab(text: 'Kateqoriyalar'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_ProvidersTab(), _ClaimsTab(), _ReportsTab(), _CategoriesTab()],
          ),
        ),
      ],
    );
  }
}

// ---- providers ------------------------------------------------------------

class _ProvidersTab extends ConsumerStatefulWidget {
  const _ProvidersTab();

  @override
  ConsumerState<_ProvidersTab> createState() => _ProvidersTabState();
}

class _ProvidersTabState extends ConsumerState<_ProvidersTab> {
  String _status = 'all';
  String _text = '';
  late Future<List<ServiceProvider>> _future = _load();

  Future<List<ServiceProvider>> _load() =>
      ref.read(servicesRepositoryProvider).adminList(status: _status == 'all' ? null : _status, text: _text);

  void _reload() {
    setState(() => _future = _load());
    ref.invalidate(adminServiceCountsProvider);
    ref.invalidate(serviceNearbyProvider);
  }

  Future<void> _openForm([ServiceProvider? p]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminServiceForm(existing: p)),
    );
    if (saved == true) _reload();
  }

  void _openDetail(ServiceProvider p) {
    final cats = ref.read(allServiceCategoriesProvider).valueOrNull ?? const <ServiceCategory>[];
    showDetail(
      context,
      title: p.name,
      body: (ctx) {
        Future<void> act(Future<void> Function() f, String ok) async {
          final done = await runAdmin(ctx, f, success: ok);
          if (done && ctx.mounted) Navigator.pop(ctx);
          if (done) _reload();
        }

        final repo = ref.read(servicesRepositoryProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              AdminChip(_statusLabels[p.status] ?? p.status, color: _statusColor(p.status)),
              AdminChip(p.isVerified ? 'Təsdiqlənmiş sahib' : 'Təsdiqlənməyib', color: p.isVerified ? AppColors.blue : AppColors.textSoft),
              if (p.isPro) const AdminChip('PRO servis', color: kProGold),
              AdminChip(p.isCenter ? 'Servis mərkəzi' : 'Fərdi usta'),
              if (p.addedByAdmin) const AdminChip('Admin əlavə edib'),
              if (p.isUnclaimed) const AdminChip('Sahibsiz', color: AppColors.accent),
              AdminChip(p.isActive ? 'Aktiv' : 'Qeyri-aktiv', color: p.isActive ? AppColors.online : AppColors.textSoft),
            ]),
            const SizedBox(height: 10),
            KV('Kateqoriyalar', p.categories.map((id) {
              for (final c in cats) {
                if (c.id == id) return c.name('az');
              }
              return id;
            }).join(', ')),
            KV('İxtisas', p.specialty),
            KV('Telefon', p.phone),
            KV('WhatsApp', p.whatsapp),
            KV('Ünvan', [p.address, p.city, p.country].where((e) => (e ?? '').isNotEmpty).join(', ')),
            KV('Koordinat', '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}'),
            KV('Mobil xidmət', p.isMobile ? 'Bəli${p.serviceRadiusKm != null ? ' · ${p.serviceRadiusKm} km' : ''}' : 'Xeyr'),
            KV('İş saatları', p.is24h ? '24/7' : p.workingHours),
            KV('Reytinq', '${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})'),
            KV('Sahib ID', p.ownerId),
            KV('Admin qeydi', p.adminNote),
            KV('Yaradılıb', fmtDateTime(p.createdAt?.toIso8601String())),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p.status != 'approved')
                  FilledButton.icon(
                    onPressed: () => act(() => repo.adminSetStatus(p.id, 'approved'), 'Təsdiqləndi'),
                    icon: const Icon(Icons.check),
                    label: const Text('Təsdiqlə'),
                  ),
                if (p.status != 'rejected')
                  OutlinedButton.icon(
                    onPressed: () async {
                      final note = await askText(ctx, 'Rədd etmə səbəbi', hint: 'İstifadəçi bu qeydi görəcək');
                      if (note == null) return;
                      await act(() => repo.adminSetStatus(p.id, 'rejected', note: note), 'Rədd edildi');
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('Rədd et'),
                  ),
                if (p.status != 'suspended')
                  OutlinedButton.icon(
                    onPressed: () async {
                      final note = await askText(ctx, 'Deaktiv etmə səbəbi');
                      if (note == null) return;
                      await act(() => repo.adminSetStatus(p.id, 'suspended', note: note), 'Deaktiv edildi');
                    },
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Deaktiv et'),
                  ),
                FilledButton.tonalIcon(
                  onPressed: () => act(() => repo.adminSetPro(p.id, !p.isPro), p.isPro ? 'PRO götürüldü' : 'PRO servis edildi'),
                  icon: Icon(p.isPro ? Icons.workspace_premium_outlined : Icons.workspace_premium, color: kProGold),
                  label: Text(p.isPro ? 'PRO-nu götür' : 'PRO servis et'),
                ),
                OutlinedButton.icon(
                  onPressed: () => act(() => repo.adminSetVerified(p.id, !p.isVerified), p.isVerified ? 'Nişan götürüldü' : 'Təsdiq nişanı verildi'),
                  icon: Icon(p.isVerified ? Icons.remove_moderator_outlined : Icons.verified_outlined),
                  label: Text(p.isVerified ? 'Nişanı götür' : 'Təsdiq nişanı ver'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openForm(p);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Redaktə'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.pushOnce('/service/${p.id}');
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Səhifəsi'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () async {
                    if (!await confirmAction(ctx, 'Servisi sil', '"${p.name}" həmişəlik silinsin? Rəylər də silinəcək.', ok: 'Sil', danger: true)) return;
                    await act(() => repo.adminDelete(p.id), 'Silindi');
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Sil'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(isDense: true, hintText: 'Ad, şəhər və ya telefon', prefixIcon: Icon(Icons.search, size: 18)),
                  onSubmitted: (v) {
                    _text = v;
                    _reload();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add), label: const Text('Servis əlavə et')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: FilterBar(
            options: const {'all': 'Hamısı', ..._statusLabels},
            selected: _status,
            onSelected: (v) {
              _status = v;
              _reload();
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ServiceProvider>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return EmptyNote(adminErrorText(snap.error!));
              final list = snap.data ?? const [];
              if (list.isEmpty) return const EmptyNote('Servis yoxdur.');
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 40),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return AdminRow(
                      leading: SizedBox(width: 32, height: 32, child: ServicePin(type: p.markerType, active: p.isActive, pro: p.isPro)),
                      title: p.name,
                      subtitle: [p.city, p.phone].where((e) => (e ?? '').isNotEmpty).join(' · '),
                      dimmed: p.status == 'suspended' || p.status == 'rejected',
                      chips: [
                        AdminChip(_statusLabels[p.status] ?? p.status, color: _statusColor(p.status)),
                        if (p.isVerified) const AdminChip('✓ Sahib təsdiqli', color: AppColors.blue),
                        if (p.isUnclaimed) const AdminChip('Sahibsiz', color: AppColors.accent),
                        if (p.ratingCount > 0) AdminChip('★ ${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})'),
                      ],
                      onTap: () => _openDetail(p),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- claims ---------------------------------------------------------------

class _ClaimsTab extends ConsumerStatefulWidget {
  const _ClaimsTab();

  @override
  ConsumerState<_ClaimsTab> createState() => _ClaimsTabState();
}

class _ClaimsTabState extends ConsumerState<_ClaimsTab> {
  bool _onlyPending = true;
  late Future<(List<ServiceClaim>, Map<String, String>)> _future = _load();

  Future<(List<ServiceClaim>, Map<String, String>)> _load() async {
    final repo = ref.read(servicesRepositoryProvider);
    final claims = await repo.adminClaims(onlyPending: _onlyPending);
    final names = <String, String>{};
    for (final c in claims) {
      if (names.containsKey(c.providerId)) continue;
      final p = await repo.byId(c.providerId);
      names[c.providerId] = p?.name ?? c.providerId;
    }
    return (claims, names);
  }

  void _reload() {
    setState(() => _future = _load());
    ref.invalidate(adminServiceCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(servicesRepositoryProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text('İstifadəçilər admin əlavə etdiyi servislərə "Bu mənim biznesimdir" ilə iddia göndərir. Təsdiqlənəndə servis onun hesabına bağlanır.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
              ),
              FilterChip(
                label: const Text('Yalnız gözləyənlər'),
                selected: _onlyPending,
                onSelected: (v) {
                  _onlyPending = v;
                  _reload();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<(List<ServiceClaim>, Map<String, String>)>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) return EmptyNote(adminErrorText(snap.error!));
              final (list, names) = snap.data!;
              if (list.isEmpty) return const EmptyNote('İddia yoxdur.');
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 40),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final c = list[i];
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.lineSoft)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(names[c.providerId] ?? c.providerId, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        KV('İstifadəçi', c.userId),
                        KV('Telefon', c.phone),
                        KV('Mesaj', c.message),
                        KV('Tarix', fmtDateTime(c.createdAt.toIso8601String())),
                        KV('Status', c.status),
                        if (c.status == 'pending')
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton(
                                onPressed: () async {
                                  if (!await confirmAction(context, 'İddianı təsdiqlə', 'Servis bu istifadəçinin hesabına bağlanacaq.')) return;
                                  if (!context.mounted) return;
                                  if (await runAdmin(context, () => repo.adminResolveClaim(c.id, true), success: 'Təsdiqləndi')) _reload();
                                },
                                child: const Text('Təsdiqlə'),
                              ),
                              OutlinedButton(
                                onPressed: () async {
                                  final note = await askText(context, 'Rədd etmə səbəbi');
                                  if (note == null || !context.mounted) return;
                                  if (await runAdmin(context, () => repo.adminResolveClaim(c.id, false, note: note), success: 'Rədd edildi')) _reload();
                                },
                                child: const Text('Rədd et'),
                              ),
                              TextButton(onPressed: () => context.pushOnce('/service/${c.providerId}'), child: const Text('Servisə bax')),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---- complaints -----------------------------------------------------------

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  late Future<List<Map<String, dynamic>>> _future = ref.read(servicesRepositoryProvider).adminServiceReports();

  void _reload() {
    setState(() => _future = ref.read(servicesRepositoryProvider).adminServiceReports());
    ref.invalidate(adminServiceCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return EmptyNote(adminErrorText(snap.error!));
        final list = snap.data ?? const [];
        if (list.isEmpty) return const EmptyNote('Servislər üzrə şikayət yoxdur.');
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final r = list[i];
            final status = '${r['status']}';
            return AdminRow(
              title: txt(r['reason']),
              subtitle: [txt(r['details']), fmtDateTime(r['created_at'])].join(' · '),
              chips: [AdminChip.status(status)],
              dimmed: status == 'resolved' || status == 'rejected',
              onTap: () async {
                final next = await pickOne(
                  context,
                  'Şikayət statusu',
                  const {'reviewing': 'Baxılır', 'resolved': 'Həll edildi', 'rejected': 'Əsassızdır', '_open': 'Servisə bax'},
                  current: status,
                );
                if (next == null || !context.mounted) return;
                if (next == '_open') {
                  context.pushOnce('/service/${r['target_id']}');
                  return;
                }
                if (await runAdmin(context, () => ref.read(adminRepositoryProvider).setReportStatus('${r['id']}', next))) _reload();
              },
            );
          },
        );
      },
    );
  }
}

// ---- categories -----------------------------------------------------------

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, ServiceCategory? c) async {
    final id = TextEditingController(text: c?.id ?? '');
    final ctrls = {for (final l in ['az', 'tr', 'en', 'ru', 'ka']) l: TextEditingController(text: c?.names[l] ?? '')};
    final sort = TextEditingController(text: '${c?.sortOrder ?? 100}');
    var icon = c?.icon ?? 'build';
    var active = c?.isActive ?? true;
    const icons = ['truck', 'engine', 'electrical', 'tyre', 'battery', 'tow', 'reefer', 'roadside', 'tarp', 'build'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(c == null ? 'Yeni kateqoriya' : 'Kateqoriya: ${c.id}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c == null)
                  TextField(controller: id, decoration: const InputDecoration(labelText: 'Kod (latın, kiçik hərf, _)', hintText: 'məs. hydraulics')),
                for (final e in ctrls.entries)
                  TextField(controller: e.value, decoration: InputDecoration(labelText: 'Ad (${e.key.toUpperCase()})')),
                TextField(controller: sort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sıra')),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final i in icons)
                      ChoiceChip(
                        label: Icon(serviceCategoryIcon(i), size: 18),
                        selected: icon == i,
                        onSelected: (_) => setState(() => icon = i),
                      ),
                  ],
                ),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktiv'), value: active, onChanged: (v) => setState(() => active = v)),
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
    final key = (c?.id ?? id.text.trim().toLowerCase());
    final data = <String, dynamic>{
      for (final e in ctrls.entries) 'name_${e.key}': e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      'icon': icon,
      'sort_order': int.tryParse(sort.text.trim()) ?? 100,
      'is_active': active,
    };
    Future.delayed(const Duration(seconds: 1), () {
      id.dispose();
      sort.dispose();
      for (final t in ctrls.values) {
        t.dispose();
      }
    });
    if (ok != true || !context.mounted) return;
    if (!RegExp(r'^[a-z0-9_]{2,40}$').hasMatch(key) || data['name_az'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kod (latın hərflər) və AZ adı mütləqdir.')));
      return;
    }
    if (await runAdmin(context, () => ref.read(servicesRepositoryProvider).adminSaveCategory(key, data))) {
      ref.invalidate(allServiceCategoriesProvider);
      ref.invalidate(serviceCategoriesProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allServiceCategoriesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyNote(adminErrorText(e)),
      data: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(onPressed: () => _edit(context, ref, null), icon: const Icon(Icons.add), label: const Text('Kateqoriya əlavə et')),
          ),
          const SizedBox(height: 10),
          for (final c in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AdminRow(
                leading: Icon(serviceCategoryIcon(c.icon), color: AppColors.accent),
                title: c.name('az'),
                subtitle: '${c.id} · sıra ${c.sortOrder} · EN: ${c.names['en'] ?? '—'} · KA: ${c.names['ka'] ?? '—'}',
                dimmed: !c.isActive,
                chips: [if (!c.isActive) const AdminChip('Deaktiv')],
                onTap: () => _edit(context, ref, c),
              ),
            ),
        ],
      ),
    );
  }
}

// ---- add / edit form ------------------------------------------------------

/// Admin form for adding an existing service (unowned until a claim is
/// approved) or editing any profile.
class AdminServiceForm extends ConsumerStatefulWidget {
  final ServiceProvider? existing;
  const AdminServiceForm({super.key, this.existing});

  @override
  ConsumerState<AdminServiceForm> createState() => _AdminServiceFormState();
}

class _AdminServiceFormState extends ConsumerState<AdminServiceForm> {
  late final p = widget.existing;
  late final _name = TextEditingController(text: p?.name ?? '');
  late final _specialty = TextEditingController(text: p?.specialty ?? '');
  late final _description = TextEditingController(text: p?.description ?? '');
  late final _phone = TextEditingController(text: p?.phone ?? '');
  late final _whatsapp = TextEditingController(text: p?.whatsapp ?? '');
  late final _country = TextEditingController(text: p?.country ?? 'Azerbaijan');
  late final _city = TextEditingController(text: p?.city ?? '');
  late final _address = TextEditingController(text: p?.address ?? '');
  late final _hours = TextEditingController(text: p?.workingHours ?? '');
  late final _radius = TextEditingController(text: p?.serviceRadiusKm?.toString() ?? '');
  late final _note = TextEditingController(text: p?.adminNote ?? '');
  late String _kind = p?.kind ?? 'center';
  late final Set<String> _cats = {...?p?.categories};
  late LatLng? _point = p == null ? null : LatLng(p!.lat, p!.lng);
  late bool _mobile = p?.isMobile ?? false;
  late bool _is24h = p?.is24h ?? false;
  late bool _active = p?.isActive ?? true;
  late String _status = p?.status ?? 'approved';
  late bool _verified = p?.isVerified ?? false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _specialty, _description, _phone, _whatsapp, _country, _city, _address, _hours, _radius, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2 || _point == null || _cats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ad, ən az bir kateqoriya və xəritədə nöqtə mütləqdir.')));
      return;
    }
    String? n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final data = <String, dynamic>{
      'kind': _kind,
      'name': _name.text.trim(),
      'specialty': n(_specialty),
      'description': n(_description),
      'categories': _cats.toList(),
      'country': n(_country),
      'city': n(_city),
      'address': n(_address),
      'lat': double.parse(_point!.latitude.toStringAsFixed(6)),
      'lng': double.parse(_point!.longitude.toStringAsFixed(6)),
      'is_mobile': _mobile,
      'service_radius_km': _mobile ? (int.tryParse(_radius.text.trim())?.toString() ?? '') : '',
      'phone': n(_phone),
      'whatsapp': n(_whatsapp),
      'working_hours': _is24h ? null : n(_hours),
      'is_24h': _is24h,
      'is_active': _active,
      'status': _status,
      'is_verified': _verified,
      'admin_note': n(_note),
    };
    setState(() => _saving = true);
    final ok = await runAdmin(context, () => ref.read(servicesRepositoryProvider).adminSave(p?.id, data));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(allServiceCategoriesProvider).valueOrNull ?? const <ServiceCategory>[];
    Widget field(TextEditingController c, String label, {TextInputType? type, int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(controller: c, keyboardType: type, minLines: lines, maxLines: lines == 1 ? 1 : lines + 2, decoration: InputDecoration(labelText: label)),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Servis əlavə et' : 'Redaktə: ${p!.name}'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Yadda saxla')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
        children: [
          if (p == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Admin əlavə etdiyi servis "Təsdiqlənməyib" nişanı ilə görünür. Real sahibi tətbiqdə "Bu mənim biznesimdir" ilə iddia göndərir; təsdiqləyəndə servis onun hesabına bağlanır. Kənar mənbələrdən məlumatı yalnız icazə və istifadə şərtlərinə uyğun daxil edin.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSoft, height: 1.35),
              ),
            ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'individual', label: Text('Fərdi usta')),
              ButtonSegment(value: 'center', label: Text('Servis mərkəzi')),
            ],
            selected: {_kind},
            onSelectionChanged: (v) => setState(() => _kind = v.first),
          ),
          const SizedBox(height: 12),
          field(_name, 'Ad *'),
          field(_specialty, 'İxtisas'),
          const SectionTitle('Kateqoriyalar *'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in cats)
                FilterChip(
                  label: Text(c.name('az')),
                  selected: _cats.contains(c.id),
                  onSelected: (v) => setState(() => v ? _cats.add(c.id) : _cats.remove(c.id)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          field(_description, 'Təsvir', lines: 2),
          field(_phone, 'Telefon', type: TextInputType.phone),
          field(_whatsapp, 'WhatsApp', type: TextInputType.phone),
          field(_country, 'Ölkə'),
          field(_city, 'Şəhər'),
          field(_address, 'Ünvan'),
          const SectionTitle('Xəritədə yer * (toxunun)'),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 240,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: _point ?? kDefaultServiceCenter,
                  initialZoom: _point == null ? 10 : 15,
                  backgroundColor: AppColors.hero,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  onTap: (_, pt) => setState(() => _point = pt),
                ),
                children: [
                  const AppTileLayer(),
                  if (_point != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _point!,
                        width: 44,
                        height: 44,
                        child: ServicePin(
                          type: _cats.contains('tow') ? ServiceMarkerType.tow : (_kind == 'center' ? ServiceMarkerType.center : ServiceMarkerType.mobile),
                          selected: true,
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          if (_point != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
            ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Mobil xidmət (yerə gəlir)'), value: _mobile, onChanged: (v) => setState(() => _mobile = v)),
          if (_mobile) field(_radius, 'Xidmət radiusu (km)', type: TextInputType.number),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('24/7 açıq'), value: _is24h, onChanged: (v) => setState(() => _is24h = v)),
          if (!_is24h) field(_hours, 'İş saatları (məs. B.e–Ş 09:00–19:00)'),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktiv (indi xidmət göstərir)'), value: _active, onChanged: (v) => setState(() => _active = v)),
          const SectionTitle('Moderasiya'),
          FilterBar(options: _statusLabels, selected: _status, onSelected: (v) => setState(() => _status = v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sahib təsdiqlənib (mavi nişan)'),
            value: _verified,
            onChanged: (v) => setState(() => _verified = v),
          ),
          field(_note, 'Admin qeydi (sahib görür)', lines: 2),
          const SizedBox(height: 10),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('Yadda saxla')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../ads/presentation/ads_providers.dart';
import 'admin_ads_page.dart';
import 'admin_autofix_page.dart';
import 'admin_services_page.dart';
import 'admin_ad_templates.dart';
import 'admin_wa_verify_poc_page.dart';
import 'admin_pages.dart';
import 'admin_providers.dart';

class AdminSection {
  final String key;
  final String label;
  final IconData icon;
  const AdminSection(this.key, this.label, this.icon);
}

const adminSections = <AdminSection>[
  AdminSection('dashboard', 'Dashboard', Icons.space_dashboard_outlined),
  AdminSection('cargo', 'Yüklər', Icons.inventory_2_outlined),
  AdminSection('users', 'İstifadəçilər', Icons.people_alt_outlined),
  AdminSection('carriers', 'Daşıyıcılar', Icons.local_shipping_outlined),
  AdminSection('drivers', 'Sürücülər', Icons.badge_outlined),
  AdminSection('shipments', 'Daşımalar', Icons.route_outlined),
  AdminSection('offers', 'Təkliflər', Icons.request_quote_outlined),
  AdminSection('reports', 'Şikayətlər', Icons.report_outlined),
  AdminSection('ads', 'Reklamlar', Icons.campaign_outlined),
  AdminSection('ad_templates', 'Reklam şablonları', Icons.dashboard_customize_outlined),
  AdminSection('services', 'Servislər', Icons.home_repair_service_outlined),
  AdminSection('autofix', 'AutoFix (xətalar)', Icons.auto_fix_high),
  AdminSection('audit', 'Audit Log', Icons.history),
  AdminSection('system', 'Sistem', Icons.monitor_heart_outlined),
  // TEST / PoC only — see docs/WHATSAPP_VERIFY_POC.md.
  AdminSection('wa_poc', 'WhatsApp test (PoC)', Icons.science_outlined),
];

/// /admin and /admin/:section. The role check here only decides what
/// to SHOW; the real protection is on the server (is_admin() in RLS and
/// in every admin_* RPC), so a non-admin who forces this screen open
/// still cannot read or change anything.
class AdminShell extends ConsumerWidget {
  final String section;
  const AdminShell({super.key, required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return auth.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _Denied(message: '$e'),
      data: (user) {
        if (user == null) return const _Denied(message: 'Daxil olun.');
        if (user.role != AppConstants.roleAdmin) {
          return const _Denied(message: 'Bu bölmə yalnız administratorlar üçündür.');
        }
        final key = adminSections.any((s) => s.key == section) ? section : 'dashboard';
        return _AdminLayout(section: key, adminName: user.fullName);
      },
    );
  }
}

class _Denied extends StatelessWidget {
  final String message;
  const _Denied({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              Text('Giriş qadağandır', style: AppFonts.display(size: 26, color: AppColors.text)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSoft)),
              const SizedBox(height: 18),
              FilledButton(onPressed: () => context.go('/cargo'), child: const Text('Tətbiqə qayıt')),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminLayout extends ConsumerWidget {
  final String section;
  final String adminName;
  const _AdminLayout({required this.section, required this.adminName});

  void _open(BuildContext context, String key) => context.go('/admin/$key');

  Widget _page(BuildContext context) {
    switch (section) {
      case 'cargo':
        return const AdminCargoPage();
      case 'users':
        return const AdminUsersPage(key: ValueKey('users'));
      case 'carriers':
        return const AdminUsersPage(key: ValueKey('carriers'), presetRole: 'carrier');
      case 'drivers':
        return const AdminUsersPage(key: ValueKey('drivers'), presetRole: 'driver');
      case 'shipments':
        return const AdminShipmentsPage();
      case 'offers':
        return const AdminOffersPage();
      case 'reports':
        return const AdminReportsPage();
      case 'ads':
        return const AdminAdsPage();
      case 'ad_templates':
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: const [AdminTemplatesPanel()]);
      case 'services':
        return const AdminServicesPage();
      case 'autofix':
        return const AdminAutoFixPage();
      case 'audit':
        return const AdminAuditPage();
      case 'system':
        return const AdminSystemPage();
      case 'wa_poc':
        return const AdminWaVerifyPocPage();
      default:
        return AdminDashboardPage(onOpenSection: (k) => _open(context, k));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final openReports = ref.watch(adminStatsProvider).valueOrNull?['reports_open'];
    final reportsCount = openReports is num ? openReports.toInt() : 0;
    final adsWaiting = ref.watch(adminAdWaitingProvider);
    final bellCount = reportsCount + adsWaiting;
    final current = adminSections.firstWhere((s) => s.key == section);

    final nav = _SideNav(
      section: section,
      reportsCount: reportsCount,
      adsWaiting: adsWaiting,
      onSelect: (k) => _open(context, k),
    );

    final search = _SearchField(key: const ValueKey('admin-search'));

    final notifications = IconButton(
      tooltip: 'Şikayətlər və reklam sifarişləri',
      onPressed: () => _open(context, adsWaiting > 0 ? 'ads' : 'reports'),
      icon: Badge(
        isLabelVisible: bellCount > 0,
        label: Text('$bellCount'),
        child: const Icon(Icons.notifications_none),
      ),
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 240, child: nav),
            const VerticalDivider(width: 1, color: AppColors.line),
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      color: AppColors.hero,
                      border: Border(bottom: BorderSide(color: AppColors.line)),
                    ),
                    child: Row(
                      children: [
                        Text(current.label, style: AppFonts.display(size: 22, color: AppColors.text)),
                        const SizedBox(width: 24),
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: search))),
                        notifications,
                        const SizedBox(width: 8),
                        _AdminBadge(name: adminName),
                      ],
                    ),
                  ),
                  Expanded(child: _page(context)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(current.label),
        actions: [notifications],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: search),
        ),
      ),
      drawer: Drawer(backgroundColor: AppColors.hero, child: SafeArea(child: nav)),
      body: _page(context),
    );
  }
}

class _SideNav extends ConsumerWidget {
  final String section;
  final int reportsCount;
  final int adsWaiting;
  final ValueChanged<String> onSelect;
  const _SideNav({required this.section, required this.reportsCount, required this.adsWaiting, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(adminServiceCountsProvider).valueOrNull ?? const {};
    final svcCount = (svc['pending'] ?? 0) + (svc['claims'] ?? 0) + (svc['reports'] ?? 0);
    return Container(
      color: AppColors.hero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
            child: Row(
              children: [
                const Icon(Icons.local_shipping, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('FreightLink', style: AppFonts.display(size: 20, color: AppColors.text)),
                const SizedBox(width: 6),
                Text('ADMIN', style: AppFonts.mono(size: 10, color: AppColors.accent)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final s in adminSections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: ListTile(
                      dense: true,
                      selected: s.key == section,
                      selectedTileColor: AppColors.card,
                      selectedColor: AppColors.accent,
                      iconColor: AppColors.textSoft,
                      textColor: AppColors.text,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      leading: Icon(s.icon, size: 20),
                      title: Text(s.label),
                      trailing: s.key == 'reports' && reportsCount > 0
                          ? Badge(label: Text('$reportsCount'))
                          : (s.key == 'ads' && adsWaiting > 0
                              ? Badge(label: Text('$adsWaiting'))
                              : (s.key == 'services' && svcCount > 0 ? Badge(label: Text('$svcCount')) : null)),
                      onTap: () {
                        Scaffold.maybeOf(context)?.closeDrawer();
                        onSelect(s.key);
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.line),
          ListTile(
            leading: const Icon(Icons.arrow_back, color: AppColors.textSoft),
            title: const Text('Tətbiqə qayıt'),
            onTap: () => context.go('/cargo'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField({super.key});
  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  late final TextEditingController _ctrl = TextEditingController(text: ref.read(adminSearchProvider));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      onChanged: (v) {
        ref.read(adminSearchProvider.notifier).state = v;
        setState(() {});
      },
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: 'Axtar: ID, şəhər, ölkə, ad, telefon, e-poçt…',
        suffixIcon: _ctrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _ctrl.clear();
                  ref.read(adminSearchProvider.notifier).state = '';
                  setState(() {});
                },
              ),
      ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  final String name;
  const _AdminBadge({required this.name});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(radius: 16, backgroundColor: AppColors.accentFill, child: Icon(Icons.shield_outlined, size: 18, color: Colors.white)),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name.isEmpty ? 'Admin' : name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
            const Text('Administrator', style: TextStyle(color: AppColors.textSoft, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

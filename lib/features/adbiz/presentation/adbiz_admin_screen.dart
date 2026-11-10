import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';
import 'adbiz_company_screen.dart';
import 'adbiz_providers.dart';
import 'adbiz_widgets.dart';

/// Baş admin → "Reklam idarəetməsi" (owner, 10.11.2026): every advertising
/// company (UTEP Reklam first), a new company, a tap opens the company with
/// its workers, reports and settings. The server refuses everyone else.
class AdbizAdminScreen extends ConsumerStatefulWidget {
  const AdbizAdminScreen({super.key});

  @override
  ConsumerState<AdbizAdminScreen> createState() => _AdbizAdminScreenState();
}

class _AdbizAdminScreenState extends ConsumerState<AdbizAdminScreen> {
  bool _busy = false;

  Future<void> _create(AppStrings s) async {
    if (_busy) return;
    final r = await showDialog<(String, double, bool)>(context: context, builder: (_) => AdbizCompanyDialog(s: s));
    if (r == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(adbizRepositoryProvider).companySave(name: r.$1, dailyTarget: r.$2, ownerManagesStaff: r.$3);
      ref.invalidate(adbizCompaniesProvider);
      if (mounted) adbizSnack(context, s.t('adb_saved'));
    } catch (e) {
      if (mounted) adbizSnack(context, adbizError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final async = ref.watch(adbizCompaniesProvider);
    final list = async.valueOrNull ?? const <AdbizCompany>[];
    return Scaffold(
      appBar: AppBar(title: UtepTitle(s.t('adb_admin'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('adb-new-company'),
        onPressed: _busy ? null : () => _create(s),
        icon: const Icon(Icons.add_business_outlined),
        label: Text(s.t('adb_new_company')),
      ),
      body: SafeArea(
        top: false,
        child: async.hasError && !async.hasValue
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(adbizError(s, async.error!), textAlign: TextAlign.center)))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(adbizCompaniesProvider),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
                  const Center(child: UtepLogo(height: 56)),
                  const SizedBox(height: 10),
                  Text(s.t('adb_admin_note'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                  const SizedBox(height: 14),
                  if (async.isLoading && !async.hasValue) const Center(child: CircularProgressIndicator()),
                  for (final c in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        key: ValueKey('adb-company-${c.id}'),
                        leading: Icon(Icons.campaign_outlined, color: c.isActive ? AppColors.accent : AppColors.textSoft),
                        title: Text(c.name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                        subtitle: Text('${s.t('adb_company_target')}: ${money(c.dailyTarget)}'
                            '${c.isActive ? '' : ' · ${s.t('adb_company_off')}'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushOnce('/profile/adbiz/company/${c.id}'),
                      ),
                    ),
                ]),
              ),
      ),
    );
  }
}

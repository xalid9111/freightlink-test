import '../../adbiz/presentation/adbiz_providers.dart';
import '../../adbiz/presentation/adbiz_widgets.dart';
import '../../favorites/favorites.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../verified/verified_account.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/phone_countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/after_save.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/age.dart';
import '../../../core/utils/gif.dart';
import '../../../core/widgets/framed_image.dart';
import '../../../core/widgets/image_frame_editor.dart';
import '../../../core/widgets/birth_date_field.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/text_size_picker.dart';
import '../../../repositories/profile_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'providers/auth_providers.dart';
import '../domain/app_user.dart';
import 'widgets/activity_buttons.dart';
import 'widgets/profile_cover.dart';
import '../../ads/presentation/public_profile_screen.dart' show ProfileCoverPlaceholder;
import '../../../repositories/profile_page_repository.dart';
import '../data/activities_repository.dart';
import '../domain/activities.dart';
import '../../services/presentation/services_providers.dart';
import '../../ads/presentation/ads_providers.dart';
import '../../../core/router/safe_navigation.dart';
import '../../tirpark/data/tir_park_repository.dart';
import '../../tirpark/domain/tir_park.dart';
import '../../finance/presentation/finance_providers.dart';
import '../../admin/presentation/head_admin.dart';
import '../../support/support.dart';

/// Profile (owner's design): title + settings gear, a card with photo,
/// name, role · country and badges, a contact card (e-mail / phone), the
/// main links, then Settings and sign out. Language, haptic and password
/// moved to Settings (/settings).
String _roleLabel(AppStrings strings, String role) => switch (role) {
      AppConstants.roleCargoOwner => strings.t('role_label_cargo_owner'),
      AppConstants.roleCarrier => strings.t('role_label_carrier'),
      AppConstants.roleDriver => strings.t('role_label_driver'),
      AppConstants.roleAdmin => strings.t('role_label_admin'),
      _ => role,
    };

/// One account: what the user does, not the old signup role (admins keep
/// their label).
String _roleLine(WidgetRef ref, AppStrings strings, AppUser user) => user.role == AppConstants.roleAdmin
    ? _roleLabel(strings, user.role)
    : activitiesWire(ref.watch(myActivitiesProvider).valueOrNull ?? const <Activity>{}).map((w) => strings.t('act_$w')).join(' · ');

/// Everything waiting in TIR Parkı: receipts (0085) + workers to approve
/// (0088) + requests waiting for a park admin (0089).
int tirParkWaitingCount(WidgetRef ref) {
  final pay = ref.watch(tirParkManagerPendingProvider).valueOrNull ?? 0;
  final wk = ref.watch(tirParkPendingWorkersProvider).valueOrNull ?? 0;
  final adm = [for (final p in ref.watch(myWorkParksProvider).valueOrNull ?? const <TirParkWorkPlace>[]) p.pending].fold<int>(0, (a, b) => a + b);
  return pay + wk + adm;
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authStateProvider);
    final strings = ref.watch(stringsProvider);

    return Scaffold(
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(strings.error(null))),
        data: (user) {
          if (user == null) {
            return Center(child: Text(strings.t('profile_not_logged_in')));
          }
          final isAdmin = user.role == AppConstants.roleAdmin;
          return SafeArea(
            bottom: false,
            child: ListView(
              // Room under the last card so the bottom bar never covers it.
              padding: EdgeInsets.fromLTRB(16, 12, 16, 32 + MediaQuery.paddingOf(context).bottom),
              children: [
                // Title + settings gear
                Row(
                  children: [
                    Expanded(
                      child: Text(strings.t('profile_title'),
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.text)),
                    ),
                    // "Bəyəndiklərim" → Profillər (owner, 07.11.2026).
                    Material(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: AppColors.line),
                      ),
                      child: IconButton(
                        key: const ValueKey('profile-favorites'),
                        tooltip: strings.t('fav_title'),
                        icon: Icon(Icons.favorite_border, color: AppColors.text),
                        onPressed: () => openFavorites(context, FavTab.profiles),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: AppColors.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: AppColors.line),
                      ),
                      child: IconButton(
                        tooltip: strings.t('settings_title'),
                        icon: Icon(Icons.settings_outlined, color: AppColors.text),
                        onPressed: () => context.pushOnce('/settings'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ProfileCard(
                  userId: user.id,
                  fallbackName: user.fullName,
                  fallbackPhone: user.phone,
                  email: user.email,
                  roleLabel: _roleLine(ref, strings, user),
                  strings: strings,
                  details: false,
                ),
                const SizedBox(height: 14),
                // Owner's design (04.11.2026): one entry each; the details open
                // on their own pages (/profile/personal, /profile/activity,
                // /profile/tirpark).
                _MenuCard(children: [
                  _MenuRow(
                    key: const ValueKey('pf-personal'),
                    icon: Icons.person,
                    iconColor: AppColors.accent,
                    title: strings.t('pf_personal'),
                    subtitle: strings.t('pf_personal_sub'),
                    onTap: () => context.pushOnce('/profile/personal'),
                  ),
                ]),
                const SizedBox(height: 12),
                _MenuCard(children: [
                  _MenuRow(
                    key: const ValueKey('pf-activity'),
                    icon: Icons.layers_outlined,
                    iconColor: AppColors.blue,
                    title: strings.t('pf_activity'),
                    subtitle: strings.t('pf_activity_sub'),
                    onTap: () => context.pushOnce('/profile/activity'),
                  ),
                ]),
                const SizedBox(height: 12),
                // TIR Parkı: park management, workers, bookings — one entry with
                // the red count of everything waiting (0085, 0088, 0089).
                Consumer(builder: (context, ref, _) {
                  final n = tirParkWaitingCount(ref);
                  return _MenuCard(children: [
                    _MenuRow(
                      key: const ValueKey('pf-tirpark'),
                      icon: Icons.local_parking,
                      iconColor: AppColors.accent,
                      title: strings.t('pf_tirpark'),
                      subtitle: strings.t('pf_tirpark_sub'),
                      badge: n,
                      onTap: () => context.pushOnce('/profile/tirpark'),
                    ),
                    // Right under "TIR Parkı" (owner, 06.11.2026): one's own
                    // bookings, the same screen as before.
                    _MenuRow(
                      key: const ValueKey('pf-bookings'),
                      icon: Icons.event_available_outlined,
                      iconColor: AppColors.accent,
                      title: strings.t('tpb_my'),
                      subtitle: strings.t('tpb_my_sub'),
                      onTap: () => context.pushOnce('/tirpark/bookings'),
                    ),
                  ]);
                }),
                // UTEP Reklam (owner, 10.11.2026, 0110): only for an account the
                // Baş admin switched on (and for the Baş admin himself).
                const AdbizProfileEntry(),
                // Every platform admin (owner, 04.11.2026 — an admin the owner
                // appoints must get in): Admin Panel; Maliyyə only for the
                // finance owner (server is_finance_admin()).
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _HeadAdminCard(strings: strings),
                  ),
                const SizedBox(height: 14),
                _MenuCard(children: [
                  _GroupTitle(icon: Icons.settings, title: strings.t('pf_account_group')),
                  // Text size 1—5 for everyone (owner, 24.10.2026), right in Profil.
                  Padding(
                    key: const ValueKey('profile-text-size'),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Icon(Icons.format_size, size: 20, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Text(strings.t('text_size_title'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                      ]),
                      const SizedBox(height: 8),
                      const TextSizePicker(),
                    ]),
                  ),
                  // Təklif və iradlar (owner, 13.11.2026, 0120).
                  _MenuRow(
                    key: const ValueKey('pf-feedback'),
                    icon: Icons.lightbulb_outline,
                    iconColor: AppColors.blue,
                    title: strings.t('sup_title'),
                    subtitle: strings.t('sup_row_sub'),
                    onTap: () => openSupportForm(context),
                  ),
                  _MenuRow(
                    icon: Icons.settings,
                    iconColor: AppColors.text,
                    title: strings.t('settings_title'),
                    subtitle: strings.t('settings_subtitle'),
                    onTap: () => context.pushOnce('/settings'),
                  ),
                  _MenuRow(
                    icon: Icons.logout,
                    iconColor: AppColors.danger,
                    title: strings.t('pf_sign_out'),
                    titleColor: AppColors.danger,
                    onTap: () => ref.read(authRepositoryProvider).signOut(),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// UTEP Reklam in Profil (owner, 10.11.2026, 0110): nothing for an account
/// the Baş admin has not switched on. A worker: "Reklam iş dəftəri"; an
/// owner: his business page too; the Baş admin: "Reklam idarəetməsi".
class AdbizProfileEntry extends ConsumerWidget {
  const AdbizProfileEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(adbizMeProvider).valueOrNull;
    if (me == null || (!me.chief && !me.isMember)) return const SizedBox.shrink();
    final strings = ref.watch(stringsProvider);
    return Padding(
      key: const ValueKey('pf-adbiz'),
      padding: const EdgeInsets.only(top: 14),
      child: _MenuCard(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(children: [
            const UtepLogo(height: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(me.companyName ?? strings.t('adb_admin'),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
            ),
          ]),
        ),
        if (me.isMember)
          _MenuRow(
            key: const ValueKey('pf-adbiz-notebook'),
            icon: Icons.edit_note,
            iconColor: AppColors.accent,
            title: strings.t('adb_notebook'),
            subtitle: strings.t('adb_notebook_sub'),
            onTap: () => context.pushOnce('/profile/adbiz'),
          ),
        if (me.isOwner)
          _MenuRow(
            key: const ValueKey('pf-adbiz-business'),
            icon: Icons.insights_outlined,
            iconColor: AppColors.blue,
            title: strings.t('adb_business'),
            subtitle: strings.t('adb_business_sub'),
            onTap: () => context.pushOnce('/profile/adbiz/company/${me.companyId}'),
          ),
        if (me.chief)
          _MenuRow(
            key: const ValueKey('pf-adbiz-admin'),
            icon: Icons.admin_panel_settings_outlined,
            iconColor: AppColors.vipGold,
            title: strings.t('adb_admin'),
            subtitle: strings.t('adb_admin_sub'),
            onTap: () => context.pushOnce('/profile/adbiz/admin'),
          ),
      ]),
    );
  }
}

/// A titled group inside a card ("Hesab və görünüş", "Fəaliyyət rollarım").
class _GroupTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? color;
  final Widget? trailing;
  const _GroupTitle({required this.icon, required this.title, this.color, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Row(children: [
          Icon(icon, size: 24, color: color ?? AppColors.text),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// "Baş admin idarəetməsi" / "Admin idarəetməsi": every platform admin
/// (users.role = admin) gets Admin Panel; Maliyyə only the finance owner.
class _HeadAdminCard extends ConsumerWidget {
  final AppStrings strings;
  const _HeadAdminCard({required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final head = ref.watch(isHeadAdminProvider).valueOrNull == true;
    return Container(
      key: const ValueKey('pf-head-admin'),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _GroupTitle(
          icon: Icons.workspace_premium,
          color: AppColors.vipGold,
          // The Baş admin keeps his title; other admins see "Admin idarəetməsi".
          title: strings.t(head ? 'pf_head_admin' : 'pf_admin_group'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(20)),
            child: Text(strings.t(head ? 'pf_head_admin_only' : 'pf_admin_only'), style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: _MenuCard(children: [
            Consumer(builder: (context, ref, _) {
              if (ref.watch(isFinanceAdminProvider).valueOrNull != true) return const SizedBox.shrink();
              return _MenuRow(
                key: const ValueKey('pf-finance'),
                icon: Icons.account_balance_wallet_outlined,
                iconColor: AppColors.accent,
                title: strings.t('pf_finance'),
                subtitle: strings.t('pf_finance_sub'),
                onTap: () => context.pushOnce('/finance'),
              );
            }),
            // Bildirişlər (0120): suggestions, payment / VIP problems — the
            // red count = the ones nobody looked at yet.
            Consumer(builder: (context, ref, _) {
              final n = ref.watch(adminSupportCountProvider).valueOrNull ?? 0;
              return _MenuRow(
                key: const ValueKey('pf-admin-reports'),
                icon: Icons.notifications_active_outlined,
                iconColor: AppColors.accent,
                title: strings.t('sup_admin_title'),
                subtitle: strings.t('sup_admin_sub'),
                badge: n,
                onTap: () => context.pushOnce('/admin-reports'),
              );
            }),
            _MenuRow(
              key: const ValueKey('pf-admin'),
              icon: Icons.admin_panel_settings_outlined,
              iconColor: AppColors.accent,
              title: strings.t('admin_panel_title'),
              subtitle: strings.t('admin_panel_subtitle'),
              onTap: () => context.go('/admin'),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A page under Profil with a back arrow and a title.
class _ProfileSubPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _ProfileSubPage({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
        ),
      );
}

/// Profil → "Şəxsi məlumatlarım": name, e-mail, phone and birth date edited
/// in one place (the same editors as before).
class ProfilePersonalScreen extends ConsumerWidget {
  const ProfilePersonalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    return _ProfileSubPage(title: strings.t('pf_personal'), children: [
      if (user == null)
        Center(child: Text(strings.t('profile_not_logged_in')))
      else
        _ProfileCard(
          userId: user.id,
          fallbackName: user.fullName,
          fallbackPhone: user.phone,
          email: user.email,
          roleLabel: _roleLine(ref, strings, user),
          strings: strings,
        ),
      // Şifrəni yenilə · Hesabı sil (owner, 13.11.2026).
      if (user != null) ...[
        const SizedBox(height: 14),
        _MenuCard(children: [
          _MenuRow(
            key: const ValueKey('pf-change-password'),
            icon: Icons.lock_reset,
            iconColor: AppColors.blue,
            title: strings.t('pf_change_password'),
            subtitle: strings.t('pf_change_password_sub'),
            onTap: () => context.pushOnce('/change-password'),
          ),
          // Shown to everybody (owner, 13.11.2026); an admin's account is
          // not deleted this way (the server refuses it too).
          _MenuRow(
            key: const ValueKey('pf-delete-account'),
            icon: Icons.person_remove_outlined,
            iconColor: AppColors.danger,
            titleColor: AppColors.danger,
            title: strings.t('pf_delete_account'),
            subtitle: strings.t('pf_delete_account_sub'),
            onTap: user.role == AppConstants.roleAdmin
                ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('pf_delete_admin'))))
                : () => deleteMyAccount(context, ref, strings),
          ),
        ]),
      ],
    ]);
  }
}

/// The typed word, any case ("sil", "SİL", "SIL").
bool deleteWordMatches(String typed, String word) {
  String n(String x) => x.trim().replaceAll('İ', 'I').replaceAll('i', 'I').replaceAll('ı', 'I').toUpperCase();
  return typed.trim().isNotEmpty && n(typed) == n(word);
}

/// "Hesabı sil" (owner, 13.11.2026, SQL 0119): asked first (the word
/// typed), then the server closes the account, hides all its ads and
/// closes the sign-in; the app signs out and opens Yüklər.
Future<void> deleteMyAccount(BuildContext context, WidgetRef ref, AppStrings strings) async {
  final word = strings.t('pf_delete_word');
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: Text(strings.t('pf_delete_account')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(strings.t('pf_delete_body')),
          const SizedBox(height: 12),
          Text(strings.t('pf_delete_type', {'word': word}), style: TextStyle(color: AppColors.textSoft)),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('pf-delete-word'),
            controller: ctrl,
            autofocus: true,
            onChanged: (_) => setD(() {}),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(strings.t('common_cancel'))),
          FilledButton(
            key: const ValueKey('pf-delete-confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: deleteWordMatches(ctrl.text, word) ? () => Navigator.pop(c, true) : null,
            child: Text(strings.t('pf_delete_account')),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    await SupabaseConfig.client.rpc('delete_my_account', params: {'p_confirm': 'DELETE'}).timeout(const Duration(seconds: 20));
  } catch (e) {
    final notReady = e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883');
    messenger.showSnackBar(SnackBar(content: Text(strings.t(notReady ? 'pf_delete_not_ready' : 'pf_delete_failed'))));
    return;
  }
  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (_) {}
  messenger.showSnackBar(SnackBar(content: Text(strings.t('pf_delete_done'))));
  router.go('/');
}

/// Profil → "Mənim fəaliyyətim": the roles (Daşıyıcı · Yük verən · Usta /
/// Servis · Satış) and the activity sections, as before, on one page.
class ProfileActivityScreen extends ConsumerWidget {
  const ProfileActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    return _ProfileSubPage(title: strings.t('pf_activity'), children: [
      _MenuCard(children: [
        _GroupTitle(icon: Icons.layers_outlined, color: AppColors.blue, title: strings.t('pf_activity_roles')),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: ActivityButtons(s: strings, grid: true),
        ),
      ]),
      const SizedBox(height: 14),
      _MenuCard(children: [
        _GroupTitle(icon: Icons.grid_view_rounded, color: AppColors.blue, title: strings.t('pf_activity_sections')),
        _MenuRow(
          icon: Icons.inventory_2_outlined,
          iconColor: AppColors.blue,
          title: strings.t('pf_my_loads'),
          subtitle: strings.t('pf_my_loads_sub'),
          onTap: () => context.pushOnce('/my-cargo'),
        ),
        // Boş maşın elanlarım (owner, 13.11.2026): edit, pause / activate,
        // "Maşın doldu" — the same as on the ad page.
        _MenuRow(
          key: const ValueKey('pf-my-trucks'),
          icon: Icons.local_shipping_outlined,
          iconColor: AppColors.accent,
          title: strings.t('et_mine_title'),
          subtitle: strings.t('pf_my_trucks_sub'),
          onTap: () => context.pushOnce('/trucks/mine'),
        ),
        Consumer(builder: (context, ref, _) {
          final mine = ref.watch(myServiceProvider).valueOrNull;
          return _MenuRow(
            icon: mine == null ? Icons.add_business_outlined : Icons.storefront,
            iconColor: AppColors.text,
            title: mine == null ? strings.t('pf_join_service') : strings.t('svc_my_service'),
            subtitle: mine == null ? strings.t('pf_join_service_sub') : mine.name,
            onTap: () => context.pushOnce(mine == null ? '/service-join' : '/service/${mine.id}'),
          );
        }),
        if (user != null)
          _MenuRow(
            icon: Icons.storefront_outlined,
            iconColor: AppColors.accent,
            title: strings.t('pf_my_page'),
            subtitle: strings.t('profile_my_page_sub'),
            onTap: () => context.pushOnce('/user/${user.id}'),
          ),
        // İş Mərkəzi — SmartMatch (owner, 26.10.2026): the same page as
        // the icon on the Loads page.
        _MenuRow(
          icon: Icons.handshake_outlined,
          iconColor: AppColors.blue,
          title: strings.t('job_center'),
          subtitle: strings.t('job_center_profile_sub'),
          onTap: () => context.pushOnce('/jobs'),
        ),
        // The old banner ads are no longer offered in Profil (owner,
        // 06.11.2026: services / shops use "Önə çıxar"); only a user who
        // already has ad orders keeps the row, to pay / follow them.
        Consumer(builder: (context, ref, _) {
          final hasOrders = (ref.watch(myAdOrdersProvider).valueOrNull ?? const []).isNotEmpty;
          if (!hasOrders) return const SizedBox.shrink();
          return _MenuRow(
            icon: Icons.campaign_outlined,
            iconColor: AppColors.accent,
            title: strings.t('pf_ads'),
            subtitle: strings.t('pf_ads_sub'),
            onTap: () => context.pushOnce('/ads'),
          );
        }),
      ]),
    ]);
  }
}

/// Profil → "TIR Parkı": managing a park, working at a park (invitations,
/// the park admin's İşçilər) — the same entries and red counts as before
/// (0079 – 0089); the bookings are on Profil. Users do not add parking
/// spots (owner, 07.11.2026).
class ProfileTirParkScreen extends ConsumerWidget {
  const ProfileTirParkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    return _ProfileSubPage(title: strings.t('pf_tirpark'), children: [
      _MenuCard(children: [
        // A receipt waiting (0085): a red count and "n ödəniş
        // yoxlanılır" under the title.
        Consumer(builder: (context, ref, _) {
          final pay = ref.watch(tirParkManagerPendingProvider).valueOrNull ?? 0;
          // + workers waiting for approval (0088).
          final wk = ref.watch(tirParkPendingWorkersProvider).valueOrNull ?? 0;
          final n = pay + wk;
          return _MenuRow(
            key: const ValueKey('pf-tirpark-manage'),
            icon: Icons.local_parking,
            iconColor: AppColors.accent,
            title: strings.t('tpm_title'),
            subtitle: n > 0
                ? [
                    if (pay > 0) strings.t('tpm_pending_sub', {'n': '$pay'}),
                    if (wk > 0) strings.t('tpo_workers_pending', {'n': '$wk'}),
                  ].join(' · ')
                : strings.t('tpm_sub'),
            badge: n,
            onTap: () async {
              await context.pushOnce('/tirpark/manage');
              ref.invalidate(tirParkManagerPendingProvider);
              ref.invalidate(tirParkPendingWorkersProvider);
            },
          );
        }),
        // A park's worker (0087): joins by the owner's invitation.
        // The park's admin (0089): a red count of requests waiting.
        Consumer(builder: (context, ref, _) {
          final wk = [for (final p in ref.watch(myWorkParksProvider).valueOrNull ?? const <TirParkWorkPlace>[]) p.pending]
              .fold<int>(0, (a, b) => a + b);
          return _MenuRow(
            key: const ValueKey('pf-tirpark-work'),
            icon: Icons.badge_outlined,
            iconColor: AppColors.accent,
            title: strings.t('tpw_title'),
            subtitle: wk > 0 ? strings.t('tpo_workers_pending', {'n': '$wk'}) : strings.t('tpw_sub'),
            badge: wk,
            onTap: () async {
              await context.pushOnce('/tirpark/work');
              ref.invalidate(myWorkParksProvider);
            },
          );
        }),
      ]),
    ]);
  }
}

/// Photo (tap to change), name + pencil, role · country, badges, and the
/// e-mail / phone box (tap to add or change the phone).
class _ProfileCard extends ConsumerStatefulWidget {
  final String userId;
  final String fallbackName;
  final String? fallbackPhone;
  final String email;
  final String roleLabel;
  final AppStrings strings;
  /// false on the Profil page (picture, name, role, badges); true on
  /// "Şəxsi məlumatlarım" (+ name, e-mail, phone, birth date to edit).
  final bool details;
  const _ProfileCard({
    required this.userId,
    required this.fallbackName,
    required this.fallbackPhone,
    required this.email,
    required this.roleLabel,
    required this.strings,
    this.details = true,
  });

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _uploading = false;

  /// Şəxsi məlumatlarım (owner, 09.11.2026): the name is edited in its own
  /// field under the card (the saved name stays on top) and saved with the
  /// "Yadda saxla" button at the bottom.
  final _nameCtrl = TextEditingController();
  String? _lastSaved; // the saved name the field last followed
  bool _savingName = false;

  /// Saved and on the way back to Profil: a second tap does nothing.
  bool _left = false;
  String? _nameError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// The camera on the picture: a new picture, or — when there is one —
  /// "Yerini düzəlt" to move / zoom it in the circle (owner, 29.10.2026).
  Future<void> _photoMenu(String? current) async {
    if (current == null || current.isEmpty) return _changePhoto();
    final strings = widget.strings;
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('photo-new'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(strings.t('photo_new')),
            onTap: () => Navigator.of(ctx).pop('new'),
          ),
          ListTile(
            key: const ValueKey('photo-adjust'),
            leading: const Icon(Icons.crop_free),
            title: Text(strings.t('photo_adjust')),
            onTap: () => Navigator.of(ctx).pop('adjust'),
          ),
        ]),
      ),
    );
    if (pick == 'new') return _changePhoto();
    if (pick != 'adjust' || !mounted) return;
    final f = await Navigator.of(context, rootNavigator: true).push<ImageFraming>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageFrameEditorScreen(
        image: NetworkImage(ImageFraming.baseOf(current)),
        initial: ImageFraming.of(current),
        aspect: 1,
        circle: true,
        title: strings.t('profile_change_photo'),
        s: strings,
      ),
    ));
    if (f == null) return;
    try {
      await ref.read(profileRepositoryProvider).setAvatarFraming(current, f);
      ref.invalidate(publicProfileProvider(widget.userId));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_photo_error'))));
    }
  }

  Future<void> _changePhoto() async {
    final strings = widget.strings;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // A GIF stays animated: the picker leaves it as it is (web).
      final gif = isGifBytes(bytes);
      if (gif && bytes.length > kGifMaxBytes) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_gif_too_big'))));
        return;
      }
      if (!mounted) return;
      // Which part shows in the circle (owner, 29.10.2026).
      final framing = await Navigator.of(context, rootNavigator: true).push<ImageFraming>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageFrameEditorScreen(
          image: MemoryImage(bytes),
          aspect: 1,
          circle: true,
          title: strings.t('profile_change_photo'),
          s: strings,
        ),
      ));
      if (framing == null) return;
      setState(() => _uploading = true);
      await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(bytes, contentType: gif ? 'image/gif' : file.mimeType, framing: framing);
      ref.invalidate(publicProfileProvider(widget.userId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_photo_error'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Saves the display name (person or company) others see.
  Future<void> _saveName(String saved) async {
    if (_savingName || _left) return; // a double tap never saves twice
    final strings = widget.strings;
    final newName = _nameCtrl.text.trim();
    if (newName.length < 2) {
      setState(() => _nameError = strings.t('register_name_required'));
      return;
    }
    if (newName == saved.trim()) {
      // Nothing changed: "Yadda saxla" just goes back to Profil.
      _left = true;
      leaveAfterSave(context, fallback: '/profile');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _savingName = true;
      _nameError = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateName(newName);
      ref.invalidate(publicProfileProvider(widget.userId));
      ref.invalidate(authStateProvider);
      // Saved: back to Profil (owner, 09.11.2026), whose card shows the new
      // name at once (its profile was read again above).
      if (mounted) {
        _left = true;
        leaveAfterSave(context, fallback: '/profile', notice: strings.t('profile_name_saved'));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('error_generic'))));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  /// Pick / change the birth date Gün · Ay · İl (owner, 28.10.2026; 0074).
  Future<void> _editBirth(DateTime? current, String lang) async {
    final strings = widget.strings;
    DateTime? picked = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final allowed = picked != null && birthDateAllowed(picked!, DateTime.now());
          return AlertDialog(
            title: Text(strings.t('profile_birth_title')),
            content: SizedBox(
              width: 360,
              child: BirthDateField(
                key: const ValueKey('profile-birth-pick'),
                initial: current,
                strings: strings,
                languageCode: lang,
                errorText: picked != null && !allowed ? strings.t('birth_too_young') : null,
                onChanged: (d) => setLocal(() => picked = d),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(strings.t('common_cancel'))),
              FilledButton(
                key: const ValueKey('profile-birth-save'),
                onPressed: allowed ? () => Navigator.of(ctx).pop(true) : null,
                child: Text(strings.t('profile_phone_save')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || picked == null || picked == current) return;
    try {
      await ref.read(profileRepositoryProvider).updateBirthDate(picked!);
      ref.invalidate(publicProfileProvider(widget.userId));
      ref.invalidate(authStateProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_birth_saved'))));
    } on PostgrestException catch (e) {
      // The database has no age column yet (0074 not run): say so instead
      // of a vague error.
      final missing = e.code == 'PGRST204' || e.code == '42703';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(strings.t(missing ? 'profile_age_not_ready' : 'error_generic'))));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('error_generic'))));
    }
  }

  Future<void> _editPhone() async {
    final strings = widget.strings;
    final userId = widget.userId;
    String? phone;
    bool valid = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String? error;
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(strings.t('profile_phone_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.t('profile_phone_hint'), style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                const SizedBox(height: 12),
                IntlPhoneField(
                  initialCountryCode: 'AZ',
                  decoration: InputDecoration(labelText: strings.t('profile_phone_label')),
                  onChanged: (p) {
                    phone = p.completeNumber;
                    try {
                      valid = p.isValidNumber();
                    } catch (_) {
                      valid = false;
                    }
                  },
                ),
                if (error != null)
                  Text(error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(strings.t('common_cancel'))),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (phone == null || !valid) {
                          setLocal(() => error = strings.t('profile_phone_invalid'));
                          return;
                        }
                        setLocal(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await ref.read(profileRepositoryProvider).updatePhone(phone!);
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        } on PhoneTakenException {
                          setLocal(() {
                            saving = false;
                            error = strings.t('profile_phone_taken');
                          });
                        } catch (_) {
                          setLocal(() {
                            saving = false;
                            error = strings.t('error_generic');
                          });
                        }
                      },
                child: Text(strings.t('profile_phone_save')),
              ),
            ],
          ),
        );
      },
    );
    if (saved == true) ref.invalidate(publicProfileProvider(userId));
  }

  static const double _coverHeight = 120;
  static const double _avatarRadius = 44;

  Widget _summary({
    required AppStrings strings,
    required String lang,
    required PublicProfile? profile,
    required String name,
    required String initials,
    required String? country,
    required bool verified,
  }) {
    final cover = ref.watch(profileDetailsProvider(widget.userId)).valueOrNull?.coverUrl;
    const avatarLeft = 14.0;
    const textLeft = avatarLeft + _avatarRadius * 2 + 14;
    return Container(
      key: const ValueKey('profile-summary'),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: _coverHeight,
            child: LayoutBuilder(builder: (context, c) {
              final aspect = c.maxWidth / _coverHeight;
              return Stack(fit: StackFit.expand, children: [
                (cover ?? '').isNotEmpty
                    ? FramedImage(
                        key: const ValueKey('profile-tab-cover'),
                        image: NetworkImage(cover!),
                        framing: ImageFraming.of(cover),
                        errorBuilder: (_, __, ___) => const ProfileCoverPlaceholder(),
                      )
                    : const ProfileCoverPlaceholder(),
                // The existing cover editor (new picture / "Yerini düzəlt").
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filledTonal(
                    key: const ValueKey('profile-tab-cover-edit'),
                    tooltip: strings.t('profile_change_cover'),
                    onPressed: () => editProfileCover(
                        context: context, ref: ref, s: strings, userId: widget.userId, current: cover, aspect: aspect),
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                ),
              ]);
            }),
          ),
          Container(height: 1, color: AppColors.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(textLeft, 10, 14, 14),
            child: ConstrainedBox(
              // Tall enough for the photo's lower half.
              constraints: const BoxConstraints(minHeight: _avatarRadius + 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    key: const ValueKey('profile-summary-name'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    if (widget.roleLabel.isNotEmpty)
                      Text(widget.roleLabel, style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                    if (country != null) ...[
                      if (widget.roleLabel.isNotEmpty) Text('•', style: TextStyle(color: AppColors.textSoft)),
                      Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSoft),
                      Text(country, style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // "Təsdiqlənmiş hesab" (owner's picture, 07.11.2026, 0104):
                // the clear blue badge when verified; otherwise the pale
                // badge, the slogan and "Ayda 20 AZN · Aktiv et".
                VerifiedAccountBlock(s: strings, userId: widget.userId, legacyVerified: verified),
                if (profile?.isEarlyMember == true) ...[
                  const SizedBox(height: 6),
                  _Badge(icon: Icons.star_rounded, label: strings.t('badge_early_member'), color: AppColors.accent),
                ],
              ]),
            ),
          ),
        ]),
        // The photo, half over the cover's edge; the camera changes it (as before).
        Positioned(
          left: avatarLeft,
          top: _coverHeight - _avatarRadius,
          child: InkWell(
            key: const ValueKey('profile-summary-photo'),
            customBorder: const CircleBorder(),
            onTap: _uploading ? null : () => _photoMenu(profile?.avatarUrl),
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.card, width: 3)),
                child: UserAvatar(imageUrl: profile?.avatarUrl, initials: initials, radius: _avatarRadius),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.cardAlt,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 2),
                  ),
                  child: _uploading
                      ? Padding(padding: const EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.text))
                      : Icon(Icons.photo_camera, size: 16, color: AppColors.text),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final profile = ref.watch(publicProfileProvider(widget.userId)).valueOrNull;
    final name = (profile?.fullName.isNotEmpty ?? false) ? profile!.fullName : widget.fallbackName;
    final initials = profile?.initials ?? (name.isNotEmpty ? name[0].toUpperCase() : '?');
    final phone = profile?.phone ?? widget.fallbackPhone;
    final hasPhone = phone != null && phone.isNotEmpty;
    // Country from the phone's calling code (users have no country field).
    final country = hasPhone ? PhoneCountries.split(phone)?.country : null;
    final verified = profile?.isVerified == true;
    final birth = profile?.birthDate;
    final age = birth == null ? null : ageFromBirthDate(birth, DateTime.now());
    // The field starts with the saved name and follows it while untouched.
    // A newly saved name (after "Yadda saxla" or from elsewhere) comes in;
    // what the user is typing is never overwritten.
    if (name != _lastSaved) {
      if (_lastSaved == null || _nameCtrl.text.trim() == _lastSaved!.trim()) _nameCtrl.text = name;
      _lastSaved = name;
    }

    // Profil (owner's picture, 04.11.2026): the cover on top, the photo half
    // over its edge, name, roles, country and badges — from the account.
    if (!widget.details) {
      return _summary(
        strings: strings,
        lang: lang,
        profile: profile,
        name: name,
        initials: initials,
        country: country?.name(lang),
        verified: verified,
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                customBorder: const CircleBorder(),
                onTap: _uploading ? null : () => _photoMenu(profile?.avatarUrl),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(imageUrl: profile?.avatarUrl, initials: initials, radius: 44),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.cardAlt,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.card, width: 2),
                        ),
                        child: _uploading
                            ? const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(Icons.photo_camera, size: 16, color: AppColors.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
                        ),
                      ],
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(widget.roleLabel, style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                        if (country != null) ...[
                          Text('•', style: TextStyle(color: AppColors.textSoft)),
                          Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSoft),
                          Text(country.name(lang), style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Badge(
                          icon: verified ? Icons.verified : Icons.hourglass_empty,
                          label: strings.t(verified ? 'pf_verified_account' : 'profile_unverified'),
                          color: verified ? AppColors.blue : AppColors.textSoft,
                        ),
                        if (profile?.isEarlyMember == true)
                          _Badge(icon: Icons.star_rounded, label: strings.t('badge_early_member'), color: AppColors.accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.details) ...[
          const SizedBox(height: 14),
          // 1) Ad Soyad / Şirkət adı (owner, 09.11.2026): emptied = the faint
          // placeholder; saved with "Yadda saxla" below.
          Container(
            key: const ValueKey('profile-name-box'),
            padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _nameError == null ? AppColors.line : AppColors.danger),
            ),
            child: Row(children: [
              Icon(Icons.person_outline, size: 22, color: AppColors.text),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  key: const ValueKey('profile-name-field'),
                  controller: _nameCtrl,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _nameError = null),
                  onSubmitted: (_) => _saveName(name),
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: strings.t('profile_name_label'),
                    hintStyle: TextStyle(fontSize: 15, color: AppColors.textSoft.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ]),
          ),
          if (_nameError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_nameError!, style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
              ),
            ),
          const SizedBox(height: 10),
          // 2) e-mail and 3) phone; tap to add / change the phone.
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _editPhone,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.mail_outline, size: 22, color: AppColors.text),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(widget.email, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Icon(Icons.phone_outlined, size: 22, color: AppColors.text),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              hasPhone ? phone! : strings.t('pf_add_phone'),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 15, color: hasPhone ? AppColors.text : AppColors.accent),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textSoft),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Birth date (owner, 28.10.2026, 0074): private, used by İş Mərkəzi.
          InkWell(
            key: const ValueKey('profile-age'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => _editBirth(birth, lang),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                Icon(Icons.cake_outlined, size: 22, color: AppColors.text),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    birth == null
                        ? strings.t('profile_birth_add')
                        : '${strings.t('profile_birth')}: ${birthDateLabel(birth, lang)} (${strings.t('job_age', {'n': '$age'})})',
                    style: TextStyle(fontSize: 15, color: birth == null ? AppColors.accent : AppColors.text),
                  ),
                ),
                // A clear "Dəyiş" so it is obvious the age can be edited.
                TextButton.icon(
                  key: const ValueKey('profile-age-edit'),
                  onPressed: () => _editBirth(birth, lang),
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent, visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(strings.t('profile_age_edit')),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          // "Yadda saxla" at the very bottom (owner, 09.11.2026).
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('profile-save'),
              onPressed: _savingName ? null : () => _saveName(name),
              child: _savingName
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(strings.t('profile_phone_save')),
            ),
          ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback onTap;
  /// A red count before the arrow (0 = none).
  final int badge;
  const _MenuRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.titleColor,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: titleColor ?? AppColors.text)),
                  if ((subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                  ],
                ],
              ),
            ),
            if (badge > 0)
              Container(
                key: const ValueKey('pf-badge'),
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
              ),
            Icon(Icons.chevron_right, color: AppColors.textSoft),
          ],
        ),
      ),
    );
  }
}

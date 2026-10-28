import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/phone_countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/age.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/widgets/text_size_picker.dart';
import '../../../repositories/profile_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'providers/auth_providers.dart';
import 'widgets/activity_buttons.dart';
import '../data/activities_repository.dart';
import '../domain/activities.dart';
import '../../services/presentation/services_providers.dart';
import '../../ads/presentation/ads_providers.dart';
import '../../../core/router/safe_navigation.dart';
import '../../finance/presentation/finance_providers.dart';

/// Profile (owner's design): title + settings gear, a card with photo,
/// name, role · country and badges, a contact card (e-mail / phone), the
/// main links, then Settings and sign out. Language, haptic and password
/// moved to Settings (/settings).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  String _roleLabel(AppStrings strings, String role) => switch (role) {
        AppConstants.roleCargoOwner => strings.t('role_label_cargo_owner'),
        AppConstants.roleCarrier => strings.t('role_label_carrier'),
        AppConstants.roleDriver => strings.t('role_label_driver'),
        AppConstants.roleAdmin => strings.t('role_label_admin'),
        _ => role,
      };

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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Title + settings gear
                Row(
                  children: [
                    Expanded(
                      child: Text(strings.t('profile_title'),
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.text)),
                    ),
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
                // Daşıyıcı · Yük verən · Usta / Servis · Satış (any combination).
                ActivityButtons(s: strings),
                const SizedBox(height: 14),
                _ProfileCard(
                  userId: user.id,
                  fallbackName: user.fullName,
                  fallbackPhone: user.phone,
                  email: user.email,
                  // One account: what the user does, not the old signup role
                  // (admins keep their label).
                  roleLabel: isAdmin
                      ? _roleLabel(strings, user.role)
                      : activitiesWire(ref.watch(myActivitiesProvider).valueOrNull ?? const <Activity>{})
                          .map((w) => strings.t('act_$w'))
                          .join(' · '),
                  strings: strings,
                ),
                const SizedBox(height: 14),
                _MenuCard(children: [
                  _MenuRow(
                    icon: Icons.inventory_2_outlined,
                    iconColor: AppColors.blue,
                    title: strings.t('pf_my_loads'),
                    subtitle: strings.t('pf_my_loads_sub'),
                    onTap: () => context.pushOnce('/my-cargo'),
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
                  // Shown while the admin's "Reklam ver" switch is on, or
                  // when this user already has ad orders (to pay / follow).
                  Consumer(builder: (context, ref, _) {
                    final on = ref.watch(adsOrderingEnabledProvider).valueOrNull ?? false;
                    final hasOrders = (ref.watch(myAdOrdersProvider).valueOrNull ?? const []).isNotEmpty;
                    if (!on && !hasOrders) return const SizedBox.shrink();
                    return _MenuRow(
                      icon: Icons.campaign_outlined,
                      iconColor: AppColors.accent,
                      title: strings.t('pf_ads'),
                      subtitle: strings.t('pf_ads_sub'),
                      onTap: () => context.pushOnce('/ads'),
                    );
                  }),
                ]),
                const SizedBox(height: 14),
                // Text size 1—5 for everyone (owner, 24.10.2026), right in Profil.
                _MenuCard(children: [
                  Padding(
                    key: const ValueKey('profile-text-size'),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
                ]),
                const SizedBox(height: 14),
                _MenuCard(children: [
                  // Only the finance owner (server decides; 0037).
                  if (isAdmin)
                    Consumer(builder: (context, ref, _) {
                      if (ref.watch(isFinanceAdminProvider).valueOrNull != true) return const SizedBox.shrink();
                      return _MenuRow(
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: AppColors.accent,
                        title: strings.t('pf_finance'),
                        subtitle: strings.t('pf_finance_sub'),
                        onTap: () => context.pushOnce('/finance'),
                      );
                    }),
                  if (isAdmin)
                    _MenuRow(
                      icon: Icons.admin_panel_settings_outlined,
                      iconColor: AppColors.accent,
                      title: strings.t('admin_panel_title'),
                      subtitle: strings.t('admin_panel_subtitle'),
                      onTap: () => context.go('/admin'),
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

/// Photo (tap to change), name + pencil, role · country, badges, and the
/// e-mail / phone box (tap to add or change the phone).
class _ProfileCard extends ConsumerStatefulWidget {
  final String userId;
  final String fallbackName;
  final String? fallbackPhone;
  final String email;
  final String roleLabel;
  final AppStrings strings;
  const _ProfileCard({
    required this.userId,
    required this.fallbackName,
    required this.fallbackPhone,
    required this.email,
    required this.roleLabel,
    required this.strings,
  });

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final strings = widget.strings;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      await ref.read(profileRepositoryProvider).uploadAvatar(bytes, contentType: file.mimeType);
      ref.invalidate(publicProfileProvider(widget.userId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_photo_error'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Change the display name (company or person) others see.
  Future<void> _editName(String current) async {
    final strings = widget.strings;
    final ctrl = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('profile_name_edit')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: strings.t('profile_name_label')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(strings.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: Text(strings.t('profile_phone_save'))),
        ],
      ),
    );
    if (newName == null || newName.trim().length < 2 || newName.trim() == current) return;
    try {
      await ref.read(profileRepositoryProvider).updateName(newName);
      ref.invalidate(publicProfileProvider(widget.userId));
      ref.invalidate(authStateProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_name_saved'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('error_generic'))));
    }
  }

  /// Pick / change the age (saved as a birth date, 0074).
  Future<void> _editAge(int? current) async {
    final strings = widget.strings;
    int? picked = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(strings.t('profile_age_title')),
          content: DropdownButtonFormField<int>(
            key: const ValueKey('profile-age-pick'),
            initialValue: picked,
            menuMaxHeight: 360,
            decoration: InputDecoration(labelText: strings.t('register_age_label')),
            items: [for (final a in kAgeChoices) DropdownMenuItem(value: a, child: Text('$a'))],
            onChanged: (v) => setLocal(() => picked = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(strings.t('common_cancel'))),
            FilledButton(
              key: const ValueKey('profile-age-save'),
              onPressed: picked == null ? null : () => Navigator.of(ctx).pop(true),
              child: Text(strings.t('profile_phone_save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || picked == null || picked == current) return;
    try {
      await ref.read(profileRepositoryProvider).updateBirthDate(birthDateForAge(picked!, DateTime.now()));
      ref.invalidate(publicProfileProvider(widget.userId));
      ref.invalidate(authStateProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('profile_age_saved'))));
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
                onTap: _uploading ? null : _changePhoto,
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
                        IconButton(
                          tooltip: strings.t('profile_name_edit'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _editName(name),
                          icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.textSoft),
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
          const SizedBox(height: 14),
          // E-mail and phone; tap to add / change the phone.
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
          // Age (owner, 28.10.2026, 0074): private, used by İş Mərkəzi.
          InkWell(
            key: const ValueKey('profile-age'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => _editAge(age),
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
                    age == null ? strings.t('profile_age_add') : '${strings.t('profile_age')}: $age',
                    style: TextStyle(fontSize: 15, color: age == null ? AppColors.accent : AppColors.text),
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSoft),
              ]),
            ),
          ),
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
  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.titleColor,
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
            Icon(Icons.chevron_right, color: AppColors.textSoft),
          ],
        ),
      ),
    );
  }
}

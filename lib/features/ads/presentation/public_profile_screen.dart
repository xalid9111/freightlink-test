
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/phone_countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/presence/online_users.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/gif.dart';
import '../../../core/widgets/framed_image.dart';
import '../../../core/widgets/image_frame_editor.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../repositories/profile_page_repository.dart';
import '../../../repositories/profile_repository.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../cargo/presentation/widgets/cargo_card.dart';
import '../../chat/data/group_repository.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/call_options.dart';
import 'ads_providers.dart';
import 'profile_catalog.dart';
import '../../../core/router/safe_navigation.dart';
import '../../auth/data/activities_repository.dart';
import '../../auth/domain/activities.dart';

/// A user's / company's FreightLink page, in the same design language as
/// the Profile tab (title row, rounded cards, the same profile card, menu
/// rows with tinted icons): cover + photo, name, role · country, badges,
/// then actions (message · call · catalog · share — or, on my own page,
/// edit info / cover), the catalog, about / hours / address, services and
/// open loads. Every role has one. The owner edits it from here.
class PublicProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _opening = false;
  static const double _coverHeight = 120;

  Future<void> _message() async {
    final strings = ref.read(stringsProvider);
    setState(() => _opening = true);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(widget.userId);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('chat_open_failed'))));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Back; a shared link opened directly has no history → go to Loads.
  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/cargo');
    }
  }

  /// Link to this profile (the web app uses #/ routes).
  String _shareLink() => '${Uri.base.origin}${Uri.base.path}#/user/${widget.userId}';

  Future<void> _share(AppStrings s) async {
    await Clipboard.setData(ClipboardData(text: _shareLink()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('profile_link_copied'))));
  }

  /// The camera on the cover: a new picture, or — when there is one —
  /// "Yerini düzəlt" to move / zoom it in the cover's frame (owner, 29.10.2026).
  Future<void> _coverMenu(AppStrings s, String? current) async {
    if (current == null || current.isEmpty) return _changeCover(s);
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            key: const ValueKey('cover-new'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(s.t('photo_new')),
            onTap: () => Navigator.of(ctx).pop('new'),
          ),
          ListTile(
            key: const ValueKey('cover-adjust'),
            leading: const Icon(Icons.crop_free),
            title: Text(s.t('photo_adjust')),
            onTap: () => Navigator.of(ctx).pop('adjust'),
          ),
        ]),
      ),
    );
    if (pick == 'new') return _changeCover(s);
    if (pick != 'adjust' || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final f = await Navigator.of(context, rootNavigator: true).push<ImageFraming>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageFrameEditorScreen(
        image: NetworkImage(ImageFraming.baseOf(current)),
        initial: ImageFraming.of(current),
        aspect: _coverAspect(),
        circle: false,
        title: s.t('profile_change_cover'),
        s: s,
      ),
    ));
    if (f == null) return;
    try {
      await ref.read(profilePageRepositoryProvider).setCoverFraming(current, f);
      ref.invalidate(profileDetailsProvider(widget.userId));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('profile_photo_error'))));
    }
  }

  /// Same shape as the cover on this screen (its width × [_coverHeight]).
  double? _coverWidth;
  double _coverAspect() => (_coverWidth ?? MediaQuery.of(context).size.width - 32) / _coverHeight;

  Future<void> _changeCover(AppStrings s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2000, maxHeight: 2000, imageQuality: 85);
      if (file == null || !mounted) return;
      final picked = await file.readAsBytes();
      if (!mounted) return;
      // A GIF goes up as it is, so it stays animated (owner, 29.10.2026).
      final gif = isGifBytes(picked);
      if (gif && picked.length > kGifMaxBytes) {
        messenger.showSnackBar(SnackBar(content: Text(s.t('profile_gif_too_big'))));
        return;
      }
      // The whole picture is kept; the frame chooses which part shows.
      final framing = await Navigator.of(context, rootNavigator: true).push<ImageFraming>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageFrameEditorScreen(
          image: MemoryImage(picked),
          aspect: _coverAspect(),
          circle: false,
          title: s.t('profile_change_cover'),
          s: s,
        ),
      ));
      if (framing == null) return;
      await ref
          .read(profilePageRepositoryProvider)
          .uploadCover(picked, contentType: gif ? 'image/gif' : (file.mimeType ?? 'image/jpeg'), framing: framing);
      ref.invalidate(profileDetailsProvider(widget.userId));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('profile_photo_error'))));
    }
  }


  Future<void> _editInfo(AppStrings s, ProfileDetails? d) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => _EditInfoSheet(s: s, details: d),
    );
    if (saved == true) ref.invalidate(profileDetailsProvider(widget.userId));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserIdProvider);
    final profileAsync = ref.watch(publicProfileProvider(widget.userId));
    final p = profileAsync.valueOrNull;
    final online = ref.watch(isUserOnlineProvider(widget.userId));
    final details = ref.watch(profileDetailsProvider(widget.userId)).valueOrNull;
    final catalog = ref.watch(profileCatalogProvider(widget.userId)).valueOrNull ?? const <CatalogItem>[];
    final services = ref.watch(ownedServicesProvider(widget.userId)).valueOrNull ?? const <OwnedService>[];
    final loads = ref.watch(userOpenCargoProvider(widget.userId));
    final isMe = me == widget.userId;
    // Phone only when the server releases it (advertiser, open load, chat…).
    final contact = isMe ? null : ref.watch(userContactProvider(widget.userId)).valueOrNull;
    final contactPhone = contact?.phone?.trim();
    final hasPhone = (contactPhone ?? '').isNotEmpty;
    // E-mail under the same server rules (get_user_contact, 0019).
    final contactEmail = contact?.email?.trim();
    final hasEmail = (contactEmail ?? '').isNotEmpty;
    // Age as a number only, never the date (owner, 28.10.2026, 0075).
    final age = ref.watch(userAgeProvider(widget.userId)).valueOrNull;

    final lang = ref.watch(currentLocaleProvider).languageCode;
    // One account, several activities (0039); the old signup role only
    // while those are not available.
    final acts = activitiesWire(ref.watch(userActivitiesProvider(widget.userId)).valueOrNull ?? const <Activity>{});
    final roleText = acts.isNotEmpty
        ? acts.map((w) => s.t('act_$w')).join(' · ')
        : (p?.role == null ? null : s.t('role_label_${p!.role}'));
    final country = hasPhone ? PhoneCountries.split(contactPhone)?.country : null;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: profileAsync.isLoading && p == null
            ? const Center(child: CircularProgressIndicator())
            : p == null
                ? Column(children: [
                    _TitleRow(title: s.t('profile_title'), onBack: _back),
                    Expanded(child: Center(child: Text(s.t('profile_not_found')))),
                  ])
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(publicProfileProvider(widget.userId));
                      ref.invalidate(profileDetailsProvider(widget.userId));
                      ref.invalidate(profileCatalogProvider(widget.userId));
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      children: [
                        _TitleRow(
                          title: s.t('profile_title'),
                          onBack: _back,
                          action: _SquareButton(
                            icon: Icons.share_outlined,
                            tooltip: s.t('profile_share'),
                            onTap: () => _share(s),
                          ),
                        ),
                        // Same card as the Profile tab, with the cover on top.
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: _coverHeight,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // The place / zoom chosen in "Yerini düzəlt" (owner, 29.10.2026).
                                    LayoutBuilder(builder: (context, c) {
                                      _coverWidth = c.maxWidth;
                                      return (details?.coverUrl ?? '').isNotEmpty
                                          ? FramedImage(
                                              key: const ValueKey('profile-cover'),
                                              image: NetworkImage(details!.coverUrl!),
                                              framing: ImageFraming.of(details.coverUrl),
                                              errorBuilder: (_, __, ___) => const _CoverPlaceholder(),
                                            )
                                          : const _CoverPlaceholder();
                                    }),
                                    if (isMe)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: IconButton.filledTonal(
                                          tooltip: s.t('profile_change_cover'),
                                          onPressed: () => _coverMenu(s, details?.coverUrl),
                                          icon: const Icon(Icons.photo_camera_outlined),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    UserAvatar(imageUrl: p.avatarUrl, initials: p.initials, radius: 44, online: online),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(p.fullName.isEmpty ? '—' : p.fullName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            children: [
                                              if (roleText != null)
                                                Text(roleText, style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                                              if (age != null) ...[
                                                if (roleText != null) Text('•', style: TextStyle(color: AppColors.textSoft)),
                                                Text(s.t('job_age', {'n': '$age'}),
                                                    key: const ValueKey('profile-public-age'),
                                                    style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                                              ],
                                              if (country != null) ...[
                                                if (roleText != null) Text('•', style: TextStyle(color: AppColors.textSoft)),
                                                Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSoft),
                                                Text(country.name(lang), style: TextStyle(color: AppColors.textSoft, fontSize: 13.5)),
                                              ],
                                            ],
                                          ),
                                          if (p.isVerified || p.isEarlyMember) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: [
                                                if (p.isVerified)
                                                  _Badge(icon: Icons.verified, label: s.t('pf_verified_account'), color: AppColors.blue),
                                                if (p.isEarlyMember)
                                                  _Badge(icon: Icons.star_rounded, label: s.t('badge_early_member'), color: AppColors.accent),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Actions — the same rows as the Profile tab menu.
                        _MenuCard(children: [
                          if (!isMe)
                            _MenuRow(
                              icon: Icons.chat_bubble_outline,
                              iconColor: AppColors.online,
                              title: s.t('detail_message_button'),
                              subtitle: s.t('pf_message_sub'),
                              busy: _opening,
                              onTap: _opening ? null : _message,
                            ),
                          if (!isMe && hasPhone)
                            _MenuRow(
                              icon: Icons.call_outlined,
                              iconColor: AppColors.online,
                              title: s.t('chat_call'),
                              subtitle: contactPhone,
                              onTap: () => showCallOptions(context, s, contactPhone!),
                            ),
                          _MenuRow(
                            icon: Icons.storefront_outlined,
                            iconColor: AppColors.accent,
                            title: s.t('profile_catalog'),
                            subtitle: s.t('pf_catalog_sub', {'n': '${catalog.length}'}),
                            onTap: () => context.pushOnce('/user/${widget.userId}/catalog'),
                          ),
                          if (isMe)
                            _MenuRow(
                              icon: Icons.edit_note,
                              iconColor: AppColors.blue,
                              title: s.t('profile_edit_info'),
                              subtitle: s.t('pf_edit_info_sub'),
                              onTap: () => _editInfo(s, details),
                            ),
                          _MenuRow(
                            icon: Icons.share_outlined,
                            iconColor: AppColors.text,
                            title: s.t('profile_share'),
                            subtitle: s.t('pf_share_sub'),
                            onTap: () => _share(s),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        // Catalog preview (owner always sees the "add" tile).
                        if (catalog.isNotEmpty || isMe)
                          _Section(
                            title: s.t('profile_catalog'),
                            trailing: catalog.isEmpty
                                ? null
                                : TextButton(
                                    onPressed: () => context.pushOnce('/user/${widget.userId}/catalog'),
                                    child: Text('${s.t('catalog_see_all')} ›'),
                                  ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isMe && catalog.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(s.t('catalog_empty_me'), style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                                  ),
                                CatalogGrid(userId: widget.userId, limit: 6),
                              ],
                            ),
                          ),
                        // About / hours / address.
                        if (!(details?.isEmpty ?? true) || isMe || hasPhone || hasEmail)
                          _Section(
                            title: s.t('profile_info'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((details?.about ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(details!.about!, style: const TextStyle(fontSize: 15, height: 1.35)),
                                  ),
                                if ((details?.workHours ?? '').isNotEmpty)
                                  _InfoRow(icon: Icons.schedule_outlined, text: details!.workHours!),
                                if ((details?.address ?? '').isNotEmpty)
                                  _InfoRow(icon: Icons.place_outlined, text: details!.address!),
                                if (hasPhone) _InfoRow(icon: Icons.call_outlined, text: contactPhone!),
                                if (hasEmail) _InfoRow(icon: Icons.mail_outline, text: contactEmail!),
                                if (isMe && (details?.isEmpty ?? true))
                                  Text(s.t('profile_info_empty_me'), style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                              ],
                            ),
                          ),
                        // Their service(s) → service page.
                        if (services.isNotEmpty) ...[
                          _MenuCard(children: [
                            for (final svc in services)
                              _MenuRow(
                                icon: Icons.home_repair_service_outlined,
                                iconColor: AppColors.accent,
                                title: svc.name,
                                subtitle: s.t('profile_services'),
                                onTap: () => context.pushOnce('/service/${svc.id}'),
                              ),
                          ]),
                          const SizedBox(height: 12),
                        ],
                        _Section(
                          title: s.t('profile_open_loads'),
                          child: loads.when(
                            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                            error: (_, __) => Text(s.t('home_error_loading')),
                            data: (list) => list.isEmpty
                                ? Text(s.t('profile_no_open_loads'), style: TextStyle(color: AppColors.textSoft))
                                : Column(
                                    children: [
                                      for (final c in list)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: CargoCard(
                                            cargo: c,
                                            strings: s,
                                            compact: true,
                                            onTap: () => context.pushOnce('/load/${c.id}'),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Back button · big title · optional square action (same look as the
/// Profile tab's title row with the settings gear).
class _TitleRow extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? action;
  const _TitleRow({required this.title, required this.onBack, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      child: Row(
        children: [
          _SquareButton(icon: Icons.arrow_back, tooltip: MaterialLocalizations.of(context).backButtonTooltip, onTap: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _SquareButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.line),
      ),
      child: IconButton(tooltip: tooltip, icon: Icon(icon, color: AppColors.text), onPressed: onTap),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
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
  final VoidCallback? onTap;
  final bool busy;
  const _MenuRow({required this.icon, required this.iconColor, required this.title, this.subtitle, this.onTap, this.busy = false});

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
              decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: busy
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
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

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.isDay
              ? [const Color(0xFFBFE3EC), const Color(0xFFE2F1F5), AppColors.background]
              : [const Color(0xFF0F4C5C), const Color(0xFF14323F), AppColors.background],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSoft),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}

/// About / working hours / address editor for my own profile.
class _EditInfoSheet extends ConsumerStatefulWidget {
  final AppStrings s;
  final ProfileDetails? details;
  const _EditInfoSheet({required this.s, required this.details});

  @override
  ConsumerState<_EditInfoSheet> createState() => _EditInfoSheetState();
}

class _EditInfoSheetState extends ConsumerState<_EditInfoSheet> {
  late final _about = TextEditingController(text: widget.details?.about ?? '');
  late final _hours = TextEditingController(text: widget.details?.workHours ?? '');
  late final _address = TextEditingController(text: widget.details?.address ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _about.dispose();
    _hours.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(profilePageRepositoryProvider).saveDetails(about: _about.text, workHours: _hours.text, address: _address.text);
      nav.pop(true);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(widget.s.t('error_generic'))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    InputDecoration deco(String label, String hint) =>
        InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.t('profile_edit_info'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 14),
              TextField(
                controller: _about,
                maxLines: 4,
                maxLength: 500,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                decoration: deco(s.t('profile_about'), s.t('profile_about_hint')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _hours,
                maxLength: 120,
                inputFormatters: [LengthLimitingTextInputFormatter(120)],
                decoration: deco(s.t('profile_work_hours'), s.t('profile_work_hours_hint')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _address,
                maxLength: 200,
                inputFormatters: [LengthLimitingTextInputFormatter(200)],
                decoration: deco(s.t('profile_address'), s.t('profile_address_hint')),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s.t('catalog_save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

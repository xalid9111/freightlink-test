import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/supabase_config.dart';
import '../constants/app_constants.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

/// Banner at the top of a page (owner, 21.10.2026): TIR Bazarı ('market',
/// table market_hero, 0044) and Servislər ('services', services_hero,
/// 0049). A night and a day picture; the admin changes them on the page.
class PageHero {
  final String? imageUrl; // night (and the only one before 0049)
  final String? imageUrlDay;
  final String? title, titleAccent, subtitle;
  const PageHero({this.imageUrl, this.imageUrlDay, this.title, this.titleAccent, this.subtitle});

  static String? _s(Object? v) {
    final t = (v as String?)?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  factory PageHero.fromJson(Map<String, dynamic> j) => PageHero(
        imageUrl: _s(j['image_url']),
        imageUrlDay: _s(j['image_url_day']),
        title: _s(j['title']),
        titleAccent: _s(j['title_accent']),
        subtitle: _s(j['subtitle']),
      );

  /// The picture for the current theme; the other one if that is missing.
  String? imageFor({required bool day}) => day ? (imageUrlDay ?? imageUrl) : (imageUrl ?? imageUrlDay);
}

const kPageHeroTables = {'market': 'market_hero', 'services': 'services_hero'};

class PageHeroRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<PageHero?> fetch(String page) async {
    final row = await _c.from(kPageHeroTables[page]!).select().eq('id', 1).maybeSingle().timeout(const Duration(seconds: 15));
    return row == null ? null : PageHero.fromJson(row);
  }

  /// Admins only — checked on the server (admin_set_page_hero, 0049).
  Future<void> save(String page, PageHero h) async {
    await _c.rpc('admin_set_page_hero', params: {
      'p_page': page,
      'p_image_url': h.imageUrl,
      'p_image_url_day': h.imageUrlDay,
      'p_title': h.title,
      'p_title_accent': h.titleAccent,
      'p_subtitle': h.subtitle,
    }).timeout(const Duration(seconds: 15));
  }

  /// Picture into the public market-photos bucket, folder = my user id.
  Future<String> upload(Uint8List bytes, String ext) async {
    final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
    final path = '${_c.auth.currentUser!.id}/hero_${DateTime.now().microsecondsSinceEpoch}.$e';
    await _c.storage
        .from('market-photos')
        .uploadBinary(path, bytes,
            fileOptions: FileOptions(contentType: e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : 'image/jpeg')))
        .timeout(const Duration(minutes: 2));
    return _c.storage.from('market-photos').getPublicUrl(path);
  }
}

final pageHeroRepositoryProvider = Provider<PageHeroRepository>((ref) => PageHeroRepository());

final pageHeroProvider = FutureProvider.autoDispose.family<PageHero?, String>((ref, page) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.watch(pageHeroRepositoryProvider).fetch(page);
  } catch (_) {
    // Table not there yet (0049 not run) or offline: the default banner.
    return null;
  }
});

bool isAdminUser(WidgetRef ref) => ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin;

/// Banner background until a picture is added.
class PageHeroGround extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  const PageHeroGround({super.key, required this.icon, this.iconSize = 220});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.card, Color.lerp(AppColors.card, AppColors.accentFill, 0.18)!],
        ),
      ),
      child: Align(
        alignment: const Alignment(0.75, 0.3),
        child: Icon(icon, size: iconSize, color: AppColors.accent.withValues(alpha: 0.12)),
      ),
    );
  }
}

/// The banner: picture for the theme (or the ground), kicker, title with
/// the coloured part, subtitle; admins get a pencil.
class PageHeroBanner extends ConsumerWidget {
  final String page;
  final String kicker;
  final String defaultTitle, defaultAccent, defaultSubtitle;
  final IconData icon;
  final double height;
  final bool compact;
  final AppStrings strings;
  const PageHeroBanner({
    super.key,
    required this.page,
    required this.kicker,
    required this.defaultTitle,
    required this.defaultAccent,
    required this.defaultSubtitle,
    required this.icon,
    required this.height,
    required this.strings,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hero = ref.watch(pageHeroProvider(page)).valueOrNull;
    final admin = isAdminUser(ref);
    final img = hero?.imageFor(day: AppColors.isDay);
    final onPhoto = img != null;
    final ink = onPhoto ? Colors.white : AppColors.text;
    final soft = onPhoto ? Colors.white.withValues(alpha: 0.85) : AppColors.textSoft;
    final shadow = onPhoto ? const [Shadow(color: Color(0x99000000), blurRadius: 12)] : null;
    final pad = compact ? 16.0 : 32.0;
    return ClipRRect(
      key: ValueKey('page-hero-$page'),
      borderRadius: BorderRadius.circular(compact ? 18 : 22),
      child: SizedBox(
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          if (img != null)
            Image.network(img,
                key: ValueKey(img),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => PageHeroGround(icon: icon, iconSize: height * 0.6))
          else
            PageHeroGround(icon: icon, iconSize: height * 0.6),
          if (onPhoto)
            // Darker on the left so the texts stay readable on any photo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xCC000000), Color(0x66000000), Color(0x00000000)],
                  stops: [0, 0.5, 0.9],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, admin ? pad + 36 : pad, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Text(kicker.toUpperCase(), style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2, size: compact ? 11 : 14)),
                ]),
                SizedBox(height: compact ? 4 : 8),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${hero?.title ?? defaultTitle}\n'),
                    TextSpan(text: hero?.titleAccent ?? defaultAccent, style: TextStyle(color: AppColors.accent)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.display(size: compact ? 20 : 34, color: ink, height: 1.15).copyWith(shadows: shadow),
                ),
                SizedBox(height: compact ? 4 : 8),
                Text(hero?.subtitle ?? defaultSubtitle,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 12.5 : 16, color: soft, height: 1.3, shadows: shadow)),
              ],
            ),
          ),
          if (admin)
            Positioned(
              right: 10,
              top: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  key: ValueKey('page-hero-edit-$page'),
                  tooltip: strings.t('mk_hero_edit'),
                  icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                  onPressed: () => showPageHeroEditor(context, strings: strings, page: page, hero: hero, icon: icon),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

Future<void> showPageHeroEditor(
  BuildContext context, {
  required AppStrings strings,
  required String page,
  required PageHero? hero,
  required IconData icon,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => PageHeroEditDialog(s: strings, page: page, hero: hero, icon: icon),
    );

/// Admin: night picture, day picture, three texts.
class PageHeroEditDialog extends ConsumerStatefulWidget {
  final AppStrings s;
  final String page;
  final PageHero? hero;
  final IconData icon;
  const PageHeroEditDialog({super.key, required this.s, required this.page, required this.hero, required this.icon});

  @override
  ConsumerState<PageHeroEditDialog> createState() => _PageHeroEditDialogState();
}

class _PageHeroEditDialogState extends ConsumerState<PageHeroEditDialog> {
  late final _title = TextEditingController(text: widget.hero?.title ?? '');
  late final _accent = TextEditingController(text: widget.hero?.titleAccent ?? '');
  late final _subtitle = TextEditingController(text: widget.hero?.subtitle ?? '');
  late String? _night = widget.hero?.imageUrl;
  late String? _day = widget.hero?.imageUrlDay;
  bool _busy = false;
  String? _error;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _title.dispose();
    _accent.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool day}) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 1200, imageQuality: 85);
    if (f == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await f.readAsBytes();
      final ext = f.name.contains('.') ? f.name.split('.').last : 'jpg';
      final url = await ref.read(pageHeroRepositoryProvider).upload(bytes, ext);
      if (mounted) setState(() => day ? _day = url : _night = url);
    } catch (_) {
      if (mounted) setState(() => _error = 'mk_hero_upload_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(pageHeroRepositoryProvider).save(
            widget.page,
            PageHero(imageUrl: _night, imageUrlDay: _day, title: _title.text, titleAccent: _accent.text, subtitle: _subtitle.text),
          );
      ref.invalidate(pageHeroProvider(widget.page));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'mk_hero_save_failed';
        });
      }
    }
  }

  Widget _picture({required bool day}) {
    final url = day ? _day : _night;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t(day ? 'hero_pic_day' : 'hero_pic_night'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 2.4,
            child: url == null
                ? PageHeroGround(icon: widget.icon, iconSize: 60)
                : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => PageHeroGround(icon: widget.icon, iconSize: 60)),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 4, children: [
          OutlinedButton.icon(
            key: ValueKey('page-hero-pick-${day ? 'day' : 'night'}'),
            onPressed: _busy ? null : () => _pick(day: day),
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(s.t('mk_hero_pick')),
          ),
          if (url != null)
            TextButton(
              onPressed: _busy ? null : () => setState(() => day ? _day = null : _night = null),
              child: Text(s.t('mk_hero_remove_pic')),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(labelText: s.t(label));
    return AlertDialog(
      title: Text(s.t('mk_hero_edit')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _picture(day: false),
              const SizedBox(width: 12),
              _picture(day: true),
            ]),
            const SizedBox(height: 4),
            Text(s.t('hero_pic_note'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: _title, maxLength: 80, decoration: deco('mk_hero_f_title')),
            TextField(controller: _accent, maxLength: 80, decoration: deco('mk_hero_f_accent')),
            TextField(controller: _subtitle, maxLength: 160, decoration: deco('mk_hero_f_subtitle')),
            Text(s.t('mk_hero_empty_note'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(s.t(_error!), style: TextStyle(color: AppColors.danger)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
        FilledButton(
          key: const ValueKey('page-hero-save'),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(s.t('mk_hero_save')),
        ),
      ],
    );
  }
}

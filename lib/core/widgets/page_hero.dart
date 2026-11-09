import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/supabase_config.dart';
import '../constants/app_constants.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../utils/gif.dart';

/// Banner at the top of a page (owner, 21.10.2026): TIR Bazarı ('market',
/// table market_hero, 0044) and Servislər ('services', services_hero,
/// 0049). A night and a day picture; the admin changes them on the page.
class PageHero {
  final String? imageUrl; // night (and the only one before 0049)
  final String? imageUrlDay;
  final String? title, titleAccent, subtitle;

  /// false = only the picture (it carries its own writing), 0050.
  final bool showText;

  /// The part of each picture kept in view, -1..1 (0,0 = middle), 0051.
  final double focusX, focusY, focusDayX, focusDayY;
  const PageHero({
    this.imageUrl,
    this.imageUrlDay,
    this.title,
    this.titleAccent,
    this.subtitle,
    this.showText = true,
    this.focusX = 0,
    this.focusY = 0,
    this.focusDayX = 0,
    this.focusDayY = 0,
    this.zoom = 1,
    this.zoomDay = 1,
  });

  /// Zoom into each picture, 1 (whole width) .. 3, 0052.
  final double zoom, zoomDay;
  static double _z(Object? v) => ((v as num?)?.toDouble() ?? 1).clamp(1.0, 3.0);

  static double _f(Object? v) => ((v as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0);

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
        showText: j['show_text'] != false,
        focusX: _f(j['focus_x']),
        focusY: _f(j['focus_y']),
        focusDayX: _f(j['focus_day_x']),
        focusDayY: _f(j['focus_day_y']),
        zoom: _z(j['zoom']),
        zoomDay: _z(j['zoom_day']),
      );

  /// The same row as the server sends it (kept on the device, PageHeroMemory).
  Map<String, dynamic> toJson() => {
        'image_url': imageUrl,
        'image_url_day': imageUrlDay,
        'title': title,
        'title_accent': titleAccent,
        'subtitle': subtitle,
        'show_text': showText,
        'focus_x': focusX,
        'focus_y': focusY,
        'focus_day_x': focusDayX,
        'focus_day_y': focusDayY,
        'zoom': zoom,
        'zoom_day': zoomDay,
      };

  /// The picture for the current theme; the other one if that is missing.
  String? imageFor({required bool day}) => day ? (imageUrlDay ?? imageUrl) : (imageUrl ?? imageUrlDay);

  /// Which part of that picture stays in view (follows the picture shown).
  Alignment alignmentFor({required bool day}) =>
      _useDay(day) ? Alignment(focusDayX, focusDayY) : Alignment(focusX, focusY);

  /// The zoom of the picture shown.
  double zoomFor({required bool day}) => _useDay(day) ? zoomDay : zoom;

  bool _useDay(bool day) => day ? imageUrlDay != null : imageUrl == null;
}

/// A banner picture: fills the frame, zoomed in [zoom] times around the
/// chosen point [align] (that part stays in view).
///
/// First open (owner, 09.11.2026): until the picture is ready only
/// [placeholder] stands in the banner's place; the picture and what is
/// written on it ([overlay]) then appear together, at once. A picture
/// already in memory is drawn on the first frame, with no placeholder.
class PageHeroImage extends StatelessWidget {
  final String url;
  final Alignment align;
  final double zoom;
  final Widget Function(BuildContext) fallback;
  final Widget Function(BuildContext)? placeholder;

  /// Drawn over the picture (not zoomed) once it is shown.
  final Widget? overlay;
  const PageHeroImage(
      {super.key,
      required this.url,
      required this.align,
      required this.zoom,
      required this.fallback,
      this.placeholder,
      this.overlay});

  @override
  Widget build(BuildContext context) => ClipRect(
        // Decoded at the size it is shown (zoom included), not the full
        // upload: a small picture in memory stays in the image cache while
        // scrolling, so it never has to be read and opened again.
        child: LayoutBuilder(
          builder: (context, c) => Image.network(url,
              key: ValueKey(url),
              fit: BoxFit.cover,
              alignment: align,
              gaplessPlayback: true,
              cacheWidth: heroDecodeWidth(c, MediaQuery.devicePixelRatioOf(context), zoom),
              frameBuilder: (c, child, frame, sync) {
                final ready = sync || frame != null;
                return Stack(fit: StackFit.expand, children: [
                  if (!ready) (placeholder ?? fallback)(c),
                  Transform.scale(scale: zoom, alignment: align, child: child),
                  if (ready && overlay != null) overlay!,
                ]);
              },
              errorBuilder: (c, __, ___) =>
                  Stack(fit: StackFit.expand, children: [fallback(c), if (overlay != null) overlay!])),
        ),
      );
}

/// The width a banner picture is decoded at: the banner's width on screen ×
/// pixel ratio × zoom, twice over — "cover" may crop the sides of a picture
/// wider than the banner, so this keeps it sharp up to twice the banner's
/// width-to-height — within 480…2400 px; null (full size) when unknown.
int? heroDecodeWidth(BoxConstraints c, double devicePixelRatio, double zoom) {
  if (!c.hasBoundedWidth || c.maxWidth <= 0) return null;
  final z = zoom < 1 ? 1.0 : zoom;
  return (c.maxWidth * devicePixelRatio * z * 2).round().clamp(480, 2400);
}

/// TIRPark's banner too (owner, 31.10.2026, 0078).
/// Mağazalar its own banner (shops_hero, 0108, owner 08.11.2026).
const kPageHeroTables = {'market': 'market_hero', 'services': 'services_hero', 'tirpark': 'tirpark_hero', 'shops': 'shops_hero'};

class PageHeroRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<PageHero?> fetch(String page) async {
    final row =
        await _c.from(kPageHeroTables[page]!).select().eq('id', 1).maybeSingle().timeout(const Duration(seconds: 15));
    return row == null ? null : PageHero.fromJson(row);
  }

  /// Admins only — checked on the server (admin_set_page_hero, 0049 /
  /// 0050). Until 0050 is run the save works without the text switch.
  Future<void> save(String page, PageHero h) async {
    final params = {
      'p_page': page,
      'p_image_url': h.imageUrl,
      'p_image_url_day': h.imageUrlDay,
      'p_title': h.title,
      'p_title_accent': h.titleAccent,
      'p_subtitle': h.subtitle,
    };
    try {
      await _c.rpc('admin_set_page_hero',
          params: {...params, 'p_show_text': h.showText}).timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST202') rethrow;
      await _c.rpc('admin_set_page_hero', params: params).timeout(const Duration(seconds: 15));
    }
    try {
      await _c.rpc('admin_set_page_hero_focus', params: {
        'p_page': page,
        'p_x': h.focusX,
        'p_y': h.focusY,
        'p_day_x': h.focusDayX,
        'p_day_y': h.focusDayY,
      }).timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      // 0051 not run yet: the pictures are saved, they stay centred.
      if (e.code != 'PGRST202') rethrow;
    }
    try {
      await _c.rpc('admin_set_page_hero_zoom',
          params: {'p_page': page, 'p_zoom': h.zoom, 'p_zoom_day': h.zoomDay}).timeout(const Duration(seconds: 15));
    } on PostgrestException catch (e) {
      // 0052 not run yet: the pictures are saved without zoom.
      if (e.code != 'PGRST202') rethrow;
    }
  }

  /// Picture into the public market-photos bucket, folder = my user id.
  Future<String> upload(Uint8List bytes, String ext) async {
    final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
    final path = '${_c.auth.currentUser!.id}/hero_${DateTime.now().microsecondsSinceEpoch}.$e';
    await _c.storage
        .from('market-photos')
        .uploadBinary(path, bytes,
            fileOptions:
                FileOptions(contentType: switch (e) { 'png' => 'image/png', 'webp' => 'image/webp', 'gif' => 'image/gif', _ => 'image/jpeg' }))
        .timeout(const Duration(minutes: 2));
    return _c.storage.from('market-photos').getPublicUrl(path);
  }
}

final pageHeroRepositoryProvider = Provider<PageHeroRepository>((ref) => PageHeroRepository());

final pageHeroProvider = FutureProvider.autoDispose.family<PageHero?, String>((ref, page) async {
  // Every page banner stays in memory (owner, 08.11.2026 map banners;
  // 09.11.2026 TIR Bazarı): its banner sits in the scrolling list, so
  // scrolling away and back used to drop it and ask the server again — the
  // default banner showed first, then the picture "opened a second time".
  // An admin's edit still refreshes it (the editor invalidates this provider).
  ref.keepAlive();
  ref.watch(currentUserIdProvider);
  try {
    final hero = await (PageHeroPrefetch.take(page) ?? ref.watch(pageHeroRepositoryProvider).fetch(page));
    PageHeroMemory.remember(page, hero);
    return hero;
  } catch (_) {
    // Offline: the banner kept on this device; table not there yet (0049
    // not run) and nothing kept: the default banner.
    return PageHeroMemory.known(page) ? PageHeroMemory.of(page) : null;
  }
});

/// What a banner shows (owner, 09.11.2026: TIR Bazarı's banner must not
/// show the default design first and then change): [known] = the server's
/// answer, or the banner kept on this device from the last visit (shown at
/// once, the server's answer replaces it when it differs); not known (the
/// very first visit, the answer still on its way) = only the banner's
/// ground in its fixed place, no default texts or picture.
typedef PageHeroShown = ({PageHero? hero, bool known});

final pageHeroShownProvider = Provider.autoDispose.family<PageHeroShown, String>((ref, page) {
  final a = ref.watch(pageHeroProvider(page));
  if (a.hasValue) return (hero: a.value, known: true);
  if (PageHeroMemory.known(page)) return (hero: PageHeroMemory.of(page), known: true);
  return (hero: null, known: a.hasError);
});

/// The last banner of every page, kept on the device (read once before the
/// first screen, main.dart): a repeat visit draws the banner at once from
/// it — and its picture from the browser's cache — instead of the default
/// banner while the server answers. Only the public banner row (picture
/// addresses, texts, place, zoom) is kept; nothing private.
class PageHeroMemory {
  PageHeroMemory._();
  static const _prefix = 'page_hero_v1_';
  static const _none = 'none';
  static final Map<String, PageHero?> _kept = {};

  static bool known(String page) => _kept.containsKey(page);
  static PageHero? of(String page) => _kept[page];

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final page in kPageHeroTables.keys) {
        final raw = p.getString('$_prefix$page');
        if (raw == null) continue;
        _raw[page] = raw;
        _kept[page] = raw == _none ? null : PageHero.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Nothing kept (private mode, old data): the banner waits for the server.
    }
  }

  static void remember(String page, PageHero? hero) {
    final raw = hero == null ? _none : jsonEncode(hero.toJson());
    _kept[page] = hero;
    if (_raw[page] == raw) return; // unchanged: nothing written
    _raw[page] = raw;
    () async {
      try {
        await (await SharedPreferences.getInstance()).setString('$_prefix$page', raw);
      } catch (_) {}
    }();
  }

  /// What is written on the device per page.
  static final Map<String, String> _raw = {};

  /// Tests only.
  static void clear() {
    _kept.clear();
    _raw.clear();
  }
}

/// The banner request of the page the app opens on leaves during start-up
/// (main.dart, right after Supabase is ready) instead of after the first
/// screen; pageHeroProvider takes that answer once.
class PageHeroPrefetch {
  PageHeroPrefetch._();
  static final Map<String, Future<PageHero?>> _pending = {};

  /// The banner page of the address the app opens on, or null.
  static String? pageOf(Uri address) {
    final f = address.fragment;
    final route = f.isNotEmpty ? f.split('?').first : '';
    final q = f.contains('?') ? Uri.splitQueryString(f.substring(f.indexOf('?') + 1)) : const <String, String>{};
    return switch (route) {
      '/market' => 'market',
      '/tirpark' => 'tirpark',
      '/services' => q['shops'] == '1' ? 'shops' : 'services',
      _ => null,
    };
  }

  static void start(PageHeroRepository repo, Uri address) {
    final page = pageOf(address);
    if (page == null) return;
    final f = repo.fetch(page);
    f.ignore(); // an error is handled where it is taken
    _pending[page] = f;
  }

  static Future<PageHero?>? take(String page) => _pending.remove(page);
}

/// The map pages' banners (MapPageBanner): TIRPark and Servislər / Mağazalar.
const kMapBannerPages = {'tirpark', 'services', 'shops'};

bool isAdminUser(WidgetRef ref) => ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin;

/// Banner background until a picture is added.
class PageHeroGround extends StatelessWidget {
  /// null = only the ground (while the banner is on its way, first visit).
  final IconData? icon;
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
      child: icon == null
          ? null
          : Align(
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
    final shown = ref.watch(pageHeroShownProvider(page));
    final hero = shown.hero;
    final admin = isAdminUser(ref);
    final img = hero?.imageFor(day: AppColors.isDay);
    final onPhoto = img != null;
    // Picture with its own writing: no app texts and no dark shade on it.
    // Not known yet (first visit): only the ground, no default texts.
    final texts = shown.known && (!onPhoto || (hero?.showText ?? true));
    final ink = onPhoto ? Colors.white : AppColors.text;
    final soft = onPhoto ? Colors.white.withValues(alpha: 0.85) : AppColors.textSoft;
    final shadow = onPhoto ? const [Shadow(color: Color(0x99000000), blurRadius: 12)] : null;
    final pad = compact ? 16.0 : 32.0;
    // Darker on the left so the texts stay readable on any photo.
    const shade = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xCC000000), Color(0x66000000), Color(0x00000000)],
          stops: [0, 0.5, 0.9],
        ),
      ),
    );
    final words = Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, admin ? pad + 36 : pad, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(kicker.toUpperCase(),
                style: AppFonts.mono(color: AppColors.accent, letterSpacing: 1.2, size: compact ? 11 : 14)),
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
    );
    return ClipRRect(
      key: ValueKey('page-hero-$page'),
      borderRadius: BorderRadius.circular(compact ? 18 : 22),
      child: SizedBox(
        height: height,
        child: Stack(fit: StackFit.expand, children: [
          if (img != null)
            PageHeroImage(
                url: img,
                align: hero!.alignmentFor(day: AppColors.isDay),
                zoom: hero.zoomFor(day: AppColors.isDay),
                fallback: (_) => PageHeroGround(icon: icon, iconSize: height * 0.6),
                placeholder: (_) => const PageHeroGround(icon: null),
                // The texts come with the picture, not before it.
                overlay: texts ? Stack(fit: StackFit.expand, children: [shade, words]) : null)
          else ...[
            PageHeroGround(icon: shown.known ? icon : null, iconSize: height * 0.6),
            if (texts) words,
          ],
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
  late bool _showText = widget.hero?.showText ?? true;
  late Offset _focus = Offset(widget.hero?.focusX ?? 0, widget.hero?.focusY ?? 0);
  late Offset _focusDay = Offset(widget.hero?.focusDayX ?? 0, widget.hero?.focusDayY ?? 0);
  late double _zoom = widget.hero?.zoom ?? 1;
  late double _zoomDay = widget.hero?.zoomDay ?? 1;
  double _zoomStart = 1;
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
    final f =
        await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 1200, imageQuality: 85);
    if (f == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await f.readAsBytes();
      // A GIF stays a GIF (animated) whatever the file name says (owner, 31.10.2026).
      final ext = isGifBytes(bytes) ? 'gif' : (f.name.contains('.') ? f.name.split('.').last : 'jpg');
      if (bytes.length > kGifMaxBytes) {
        if (mounted) setState(() => _error = 'profile_gif_too_big');
        return;
      }
      final url = await ref.read(pageHeroRepositoryProvider).upload(bytes, ext);
      // A new picture starts centred.
      if (mounted) {
        setState(() => day
            ? (_day = url, _focusDay = Offset.zero, _zoomDay = 1)
            : (_night = url, _focus = Offset.zero, _zoom = 1));
      }
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
            PageHero(
                imageUrl: _night,
                imageUrlDay: _day,
                title: _title.text,
                titleAccent: _accent.text,
                subtitle: _subtitle.text,
                showText: _showText,
                focusX: _focus.dx,
                focusY: _focus.dy,
                focusDayX: _focusDay.dx,
                focusDayY: _focusDay.dy,
                zoom: _zoom,
                zoomDay: _zoomDay),
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

  void _setZoom(bool day, double v) => setState(() => day ? _zoomDay = v.clamp(1.0, 3.0) : _zoom = v.clamp(1.0, 3.0));

  Widget _picture({required bool day}) {
    final url = day ? _day : _night;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(s.t(day ? 'hero_pic_day' : 'hero_pic_night'), style: const TextStyle(fontWeight: FontWeight.w400)),
      const SizedBox(height: 6),
      // Banner-shaped frame: drag the picture (or tap a spot) to choose
      // the part that stays in view.
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 2.4,
          child: url == null
              ? PageHeroGround(icon: widget.icon, iconSize: 60)
              : LayoutBuilder(builder: (context, c) {
                  final f = day ? _focusDay : _focus;
                  final z = day ? _zoomDay : _zoom;
                  void set(Offset o) => setState(() {
                        final v = Offset(o.dx.clamp(-1.0, 1.0), o.dy.clamp(-1.0, 1.0));
                        day ? _focusDay = v : _focus = v;
                      });
                  return GestureDetector(
                    key: ValueKey('page-hero-focus-${day ? 'day' : 'night'}'),
                    // One finger moves the picture, two fingers zoom it.
                    onScaleStart: _busy ? null : (_) => _zoomStart = z,
                    onScaleUpdate: _busy
                        ? null
                        : (d) {
                            set(f -
                                Offset(d.focalPointDelta.dx * 4 / (c.maxWidth * z),
                                    d.focalPointDelta.dy * 4 / (c.maxHeight * z)));
                            if (d.pointerCount > 1) _setZoom(day, _zoomStart * d.scale);
                          },
                    onTapUp: _busy
                        ? null
                        : (d) => set(
                            Offset(d.localPosition.dx / c.maxWidth * 2 - 1, d.localPosition.dy / c.maxHeight * 2 - 1)),
                    child: Stack(fit: StackFit.expand, children: [
                      PageHeroImage(
                          url: url,
                          align: Alignment(f.dx, f.dy),
                          zoom: z,
                          fallback: (_) => PageHeroGround(icon: widget.icon, iconSize: 60)),
                      const Positioned(
                        right: 6,
                        bottom: 6,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.open_with, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
        ),
      ),
      if (url != null)
        // Zoom: enlarge the picture, then drag it to the part to show.
        Row(children: [
          const Icon(Icons.zoom_out, size: 18),
          Expanded(
            child: Slider(
              key: ValueKey('page-hero-zoom-${day ? 'day' : 'night'}'),
              min: 1,
              max: 3,
              value: day ? _zoomDay : _zoom,
              onChanged: _busy ? null : (v) => _setZoom(day, v),
            ),
          ),
          const Icon(Icons.zoom_in, size: 18),
        ]),
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
    ]);
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
            // One under the other, full width: easy to drag on a phone.
            _picture(day: false),
            const SizedBox(height: 12),
            _picture(day: true),
            const SizedBox(height: 4),
            Text(s.t('hero_pic_note'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            const SizedBox(height: 2),
            Text(s.t('hero_focus_note'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            Text(s.t('hero_zoom_note'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            const SizedBox(height: 6),
            // Off: the picture has its own writing — nothing is written on it.
            SwitchListTile(
              key: const ValueKey('page-hero-show-text'),
              contentPadding: EdgeInsets.zero,
              value: _showText,
              onChanged: _busy ? null : (v) => setState(() => _showText = v),
              title: Text(s.t('hero_show_text'), style: const TextStyle(fontWeight: FontWeight.w400)),
              subtitle: Text(s.t(_showText ? 'hero_show_text_on' : 'hero_show_text_off'),
                  style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            ),
            if (_showText) ...[
              TextField(controller: _title, maxLength: 80, decoration: deco('mk_hero_f_title')),
              TextField(controller: _accent, maxLength: 80, decoration: deco('mk_hero_f_accent')),
              TextField(controller: _subtitle, maxLength: 160, decoration: deco('mk_hero_f_subtitle')),
              Text(s.t('mk_hero_empty_note'), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            ],
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
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(s.t('mk_hero_save')),
        ),
      ],
    );
  }
}

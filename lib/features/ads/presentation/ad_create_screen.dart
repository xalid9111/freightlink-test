import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/autofix/autofix.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/ads_repository.dart';
import 'ad_creative_view.dart';
import 'ad_error_keys.dart';
import '../../services/presentation/services_providers.dart' show serviceByIdProvider;
import 'ads_providers.dart';
import 'cover_crop_screen.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import 'advertise_screen.dart' show adMoney, adSectionHeader;

/// "Reklam yarat" (and "Redaktə et" for an own order): pick a background →
/// company / activity / phone → logo → font, size, colour per line → (new
/// orders) destination, targeting, 5/15/30 days → confirm. No start date:
/// the ad starts when the admin approves the payment.
/// Positions are fixed by the standard 1200×400 layout.
///
/// Admin mode ([adminOrderId]): the admin edits any order or published ad —
/// banner, link, target countries, route and (published ad) dates.
class AdCreateScreen extends ConsumerStatefulWidget {
  final String? initialTemplateId;
  /// Edit an existing own order instead of creating a new one.
  final String? editOrderId;
  /// Admin: edit this order (and its published ad).
  final String? adminOrderId;
  /// Service owner advertising his service (0029): service templates,
  /// countries only (no route), the banner opens the service page.
  final String? serviceId;
  const AdCreateScreen({super.key, this.initialTemplateId, this.editOrderId, this.adminOrderId, this.serviceId});

  @override
  ConsumerState<AdCreateScreen> createState() => _AdCreateScreenState();
}

const _lineKeys = ['company', 'activity', 'phone'];

/// Removes the invisible characters iPhone adds when a number is pasted or
/// autofilled (direction marks etc.) and turns odd spaces into normal ones.
/// The server does the same (0024), so preview == what is saved.
String adCleanText(String v) => v
    .replaceAll(RegExp('[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF\u00AD]'), '')
    .replaceAll(RegExp('[\u00A0\u2007\u202F\t]'), ' ')
    .trim();

class _AdCreateScreenState extends ConsumerState<AdCreateScreen> {
  AdTemplate? _tpl;
  final _company = TextEditingController();
  final _activity = TextEditingController();
  final _phone = TextEditingController();
  final Map<String, AdTextStyle> _style = {for (final k in _lineKeys) k: AdTextStyle.defaults(k)};
  String _styleLine = 'company';
  String? _logoUrl;
  String _logoBg = 'dark';
  bool _logoUploading = false;

  String _destination = 'profile';
  final _url = TextEditingController();
  final _note = TextEditingController();
  final Set<String> _countries = {};
  /// Target route: country codes (AZ, GE …) or null = any.
  String? _routeFrom;
  String? _routeTo;
  /// Admin: an old free-text route value that matches no country.
  String? _legacyRoute;
  int? _days;
  bool _busy = false;
  bool _ownUploading = false;
  bool _loadedOrder = false;

  /// Admin: the published ad's run dates (null when not published yet).
  String? _adId;
  DateTime? _adStart;
  DateTime? _adEnd;
  /// The order's background when its template is no longer offered.
  AdTemplate? _keptTpl;

  bool get _editing => widget.editOrderId != null;
  bool get _admin => widget.adminOrderId != null;
  bool get _forService => widget.serviceId != null;
  /// Admin editing a service ad (it always leads to the service page).
  bool _adminServiceAd = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_company, _activity, _phone]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_company, _activity, _phone, _url, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _texts => {
        'company': adCleanText(_company.text),
        'activity': adCleanText(_activity.text),
        'phone': adCleanText(_phone.text),
      };

  void _loadOrder(AdOrder o, List<AdTemplate> list, {Ad? ad}) {
    final c = o.creative;
    if (c != null && c.isStandard) {
      _company.text = c.texts['company'] ?? '';
      _activity.text = c.texts['activity'] ?? '';
      _phone.text = c.texts['phone'] ?? '';
      for (final k in _lineKeys) {
        _style[k] = c.styleOf(k);
      }
      _logoUrl = c.logoUrl;
      _logoBg = c.logoBg;
    }
    for (final t in list) {
      if (t.id == o.templateId) _tpl = t;
    }
    if (_admin) {
      // Template switched off / deleted since: keep the order's own background.
      if (_tpl == null && c != null && c.imageUrl.isNotEmpty) {
        _keptTpl = AdTemplate(
          id: o.templateId ?? '',
          name: 'Hazırkı fon',
          imageUrl: c.imageUrl,
          fields: const [],
          colors: const [],
          layout: 'standard_v2',
          isActive: false,
          sort: -1,
        );
        _tpl = _keptTpl;
      }
      _adminServiceAd = o.destinationType == 'service';
      _destination = o.destinationType == 'external' ? 'external' : 'profile';
      _url.text = o.destinationUrl ?? '';
      _countries
        ..clear()
        ..addAll(o.targetCountries);
      final legacy = <String>[];
      String? code(String? v) {
        if ((v ?? '').trim().isEmpty) return null;
        final c = Countries.find(v);
        if (c == null) legacy.add(v!.trim());
        return c?.code;
      }
      _routeFrom = code(o.routeFrom);
      _routeTo = code(o.routeTo);
      _legacyRoute = legacy.isEmpty ? null : legacy.join(' → ');
      if (ad != null) {
        _adId = ad.id;
        _adStart = ad.startsAt.toLocal();
        _adEnd = ad.endsAt.toLocal();
      }
    }
    if (list.isNotEmpty) _tpl ??= list.first;
  }

  Future<void> _pickLogo(AppStrings s) async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000, maxHeight: 1000);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final name = f.name.toLowerCase();
    final ext = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : (name.endsWith('.jpg') || name.endsWith('.jpeg') ? 'jpg' : ''));
    if (ext.isEmpty) {
      _toast(s.t('adv_logo_type'));
      return;
    }
    if (bytes.length > 2 * 1024 * 1024) {
      _toast(s.t('adv_logo_size'));
      return;
    }
    // Must really be an image (not just a renamed file).
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } catch (_) {
      _toast(s.t('adv_logo_type'));
      return;
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || !mounted) return;
    setState(() => _logoUploading = true);
    try {
      final url = await ref.read(adsRepositoryProvider).uploadLogo(bytes, ext, uid);
      if (mounted) setState(() => _logoUrl = url);
    } catch (_) {
      _toast(s.t('adv_logo_failed'));
    } finally {
      if (mounted) setState(() => _logoUploading = false);
    }
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Map<int, AdPackage> _durations(List<AdPackage> packages) {
    final out = <int, AdPackage>{};
    final sorted = [...packages]..sort((a, b) => a.sort.compareTo(b.sort));
    for (final p in sorted) {
      if (const [5, 15, 30].contains(p.days) && p.isActive && p.price > 0) out.putIfAbsent(p.days, () => p);
    }
    return out;
  }

  static DateTime _minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static DateTime _maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  /// Admin: change the published ad's start / end (time of day kept).
  Future<void> _pickAdDate(bool isStart) async {
    final cur = (isStart ? _adStart : _adEnd) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: _minDate(cur, DateTime.now().subtract(const Duration(days: 365))),
      lastDate: _maxDate(cur, DateTime.now().add(const Duration(days: 400))),
    );
    if (d == null || !mounted) return;
    setState(() {
      final v = DateTime(d.year, d.month, d.day, cur.hour, cur.minute);
      if (isStart) {
        _adStart = v;
      } else {
        _adEnd = v;
      }
    });
  }

  String? _validate(AppStrings s, Map<int, AdPackage> durations) {
    if (_tpl == null) return s.t('adv_err_template');
    if (adCleanText(_company.text).isEmpty) return s.t('adv_err_company');
    final phone = adCleanText(_phone.text);
    if (phone.isNotEmpty && !RegExp(r'^[+0-9 ()\-]{5,25}$').hasMatch(phone)) return s.t('adv_err_invalid_phone');
    if (_editing) return null;
    if (_destination == 'external') {
      final uri = Uri.tryParse(_url.text.trim());
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return s.t('ad_external_url_invalid');
    }
    if (_admin) {
      if (_adId != null && (_adStart == null || _adEnd == null || !_adEnd!.isAfter(_adStart!))) {
        return 'Bitmə tarixi başlamadan sonra olmalıdır';
      }
      return null;
    }
    if (_days == null || !durations.containsKey(_days)) return s.t('adv_err_duration');
    return null;
  }

  /// Unknown server error → its short code in brackets, e.g. " (invalid_font)",
  /// so the problem can be found from a screenshot.
  String _errCode(Object e) {
    final m = RegExp(r'\b[a-z]+(?:_[a-z]+)+\b').firstMatch(e.toString());
    return m == null ? '' : ' (${m.group(0)})';
  }

  String _errKey(Object e) {
    final raw = e.toString();
    return [
      'package_not_found',
      'template_not_found',
      'service_not_found',
      'invalid_start_date',
      'invalid_external_url',
      'text_too_long',
      'text_required',
      'account_blocked',
      'invalid_logo',
      'invalid_phone',
      'invalid_route',
      'ordering_disabled',
      'order_locked',
    ].firstWhere(raw.contains, orElse: () => '');
  }

  Future<void> _submit(AppStrings s, Map<int, AdPackage> durations, String lang) async {
    final err = _validate(s, durations);
    if (err != null) {
      _toast(err);
      return;
    }
    final repo = ref.read(adsRepositoryProvider);
    if (_admin) {
      setState(() => _busy = true);
      try {
        await repo.adminUpdateOrderV2(
          orderId: widget.adminOrderId!,
          templateId: _tpl!.id,
          texts: _texts,
          style: _style,
          logoUrl: _logoUrl,
          logoBg: _logoBg,
          destinationType: _destination,
          destinationUrl: _destination == 'external' ? _url.text.trim() : null,
          targetCountries: _countries.toList(),
          routeFrom: _routeFrom,
          routeTo: _routeTo,
          startsAt: _adId == null ? null : _adStart,
          endsAt: _adId == null ? null : _adEnd,
        );
        if (!mounted) return;
        ref.invalidate(liveAdsProvider);
        _toast('Yadda saxlandı — reklam yeniləndi');
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        final k = _errKey(e);
        _toast(k.isEmpty ? '${s.t('ad_action_failed')} ($e)' : s.t('adv_err_$k'));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    if (_editing) {
      setState(() => _busy = true);
      try {
        final o = await repo.updateOrderV2(
          orderId: widget.editOrderId!,
          templateId: _tpl!.id,
          texts: _texts,
          style: _style,
          logoUrl: _logoUrl,
          logoBg: _logoBg,
        );
        if (!mounted) return;
        ref.invalidate(myAdOrdersProvider);
        _toast(s.t(o.receiptPath != null ? 'adv_saved_review' : 'adv_saved'));
        if (mounted) context.pop();
      } catch (e) {
        final k = _errKey(e);
        _toast(k.isEmpty ? '${s.t('ad_action_failed')}${_errCode(e)}' : s.t('adv_err_$k'));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final pkg = durations[_days]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('adv_confirm_title')),
        content: Text(s.t('adv_confirm_body_nodate', {
          'amount': adMoney(pkg.price, pkg.currency),
          'days': '${pkg.days}',
        })),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('adv_confirm_ok'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    if (_forService) {
      try {
        final order = await repo.createServiceOrder(
          serviceId: widget.serviceId!,
          templateId: _tpl!.id,
          texts: _texts,
          style: _style,
          logoUrl: _logoUrl,
          logoBg: _logoBg,
          days: pkg.days,
          targetCountries: _countries.toList(),
          note: _note.text.trim(),
        );
        if (!mounted) return;
        ref.invalidate(myAdOrdersProvider);
        if (mounted) context.pushReplacement('/ad-order/${order.id}');
      } catch (e, st) {
        final k = _errKey(e);
        if (k.isEmpty) AutoFix.instance.capture(e, st, source: 'ads.service_order');
        _toast(k.isEmpty ? '${s.t('ad_action_failed')}${_errCode(e)}' : s.t('adv_err_$k'));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    try {
      final order = await repo.createOrderV2(
        templateId: _tpl!.id,
        texts: _texts,
        style: _style,
        logoUrl: _logoUrl,
        logoBg: _logoBg,
        days: pkg.days,
        destinationType: _destination,
        destinationUrl: _destination == 'external' ? _url.text.trim() : null,
        targetCountries: _countries.toList(),
        routeFrom: _routeFrom,
        routeTo: _routeTo,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(myAdOrdersProvider);
      if (mounted) context.pushReplacement('/ad-order/${order.id}');
    } catch (e) {
      final k = _errKey(e);
      _toast(k.isEmpty ? '${s.t('ad_action_failed')}${_errCode(e)}' : s.t('adv_err_$k'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Service ad (0032): pick my own picture, choose the 1200×400 part,
  /// upload it as a private background and select it.
  Future<void> _addOwnImage(AppStrings s) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null || _ownUploading) return;
    XFile? f;
    try {
      f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2400, maxHeight: 2400, imageQuality: 90);
    } catch (e, st) {
      _ownImageFailed(s, e, st);
      return;
    }
    if (f == null || !mounted) return;
    final picked = await f.readAsBytes();
    if (!mounted) return;
    final png = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CoverCropScreen(bytes: picked, aspect: 3, s: s, title: s.t('adv_own_image')),
    ));
    if (png == null || !mounted) return;
    setState(() => _ownUploading = true);
    try {
      final t = await ref.read(adsRepositoryProvider).createOwnBackground(png, uid);
      ref.invalidate(serviceAdTemplatesProvider);
      if (mounted) setState(() => _tpl = t);
    } catch (e, st) {
      _ownImageFailed(s, e, st);
    } finally {
      if (mounted) setState(() => _ownUploading = false);
    }
  }

  /// Say why the picture was not accepted (never just "failed"): known
  /// causes get their own text; anything else its short code, and the full
  /// error goes to Admin → AutoFix.
  void _ownImageFailed(AppStrings s, Object e, StackTrace st) {
    final raw = e.toString();
    final key = ownImageErrorKey(raw);
    if (key != 'adv_own_image_failed') {
      _toast(s.t(key));
      return;
    }
    AutoFix.instance.capture(e, st, source: 'ads.own_image');
    final code = adErrorCode(raw);
    _toast(code.isEmpty ? s.t(key) : '${s.t(key)} ($code)');
  }

  Widget _orderingOffNote(AppStrings s) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Text(s.t('adv_err_ordering_disabled'), textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
      );

  Widget _ownImageButton(AppStrings s) => OutlinedButton.icon(
        onPressed: _ownUploading ? null : () => _addOwnImage(s),
        icon: _ownUploading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(s.t('adv_own_image_add')),
      );

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final templates = ref.watch((_forService || _adminServiceAd) ? serviceAdTemplatesProvider : adTemplatesProvider);
    // Service ad: start with the service's own name and phone.
    if (_forService && !_prefilled) {
      final svc = ref.watch(serviceByIdProvider(widget.serviceId!)).valueOrNull;
      if (svc != null) {
        _prefilled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_company.text.isEmpty) _company.text = svc.name.length > 40 ? svc.name.substring(0, 40) : svc.name;
          final ph = (svc.phone ?? '').trim();
          if (_phone.text.isEmpty && ph.isNotEmpty) _phone.text = ph.length > 25 ? ph.substring(0, 25) : ph;
          if (_countries.isEmpty) {
            final c = Countries.find(svc.country);
            if (c != null) setState(() => _countries.add(c.code));
          }
        });
      }
    }
    final durations = _durations(ref.watch(adPackagesProvider).valueOrNull ?? const []);
    // New order while the admin has "Reklam ver" switched off: the server
    // refuses pictures and orders (ordering_disabled) — say so up front.
    final orderingOff = !_admin && !_editing && ref.watch(adsOrderingEnabledProvider).valueOrNull == false;
    final fmt = DateFormat('d MMM yyyy', lang);
    final pkg = _days == null ? null : durations[_days];
    final editOrder = _editing ? ref.watch(myAdOrderProvider(widget.editOrderId!)).valueOrNull : null;
    AdOrder? adminOrder;
    Ad? adminAd;
    var adminLoaded = false;
    if (_admin) {
      final oa = ref.watch(adminAdOrdersProvider);
      final aa = ref.watch(adminAdsProvider);
      adminLoaded = oa.hasValue && aa.hasValue;
      for (final o in oa.valueOrNull ?? const <AdOrder>[]) {
        if (o.id == widget.adminOrderId) adminOrder = o;
      }
      for (final a in aa.valueOrNull ?? const <Ad>[]) {
        if (a.orderId == widget.adminOrderId) adminAd = a;
      }
    }

    Widget section(int n, String key) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text('$n. ${s.t(key)}'.toUpperCase(), style: adSectionHeader),
        );

    return Scaffold(
      appBar: AppBar(
          title: Text(_admin
              ? 'Reklamı redaktə et (admin)'
              : s.t(_editing ? 'adv_edit_title' : (_forService ? 'adv_create_service' : 'adv_create')))),
      body: templates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(s.t('home_error_loading'))),
        data: (list) {
          if (list.isEmpty && !_admin) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (orderingOff) ...[_orderingOffNote(s), const SizedBox(height: 16)],
                    Text(s.t('adv_no_templates'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                    if (_forService) ...[
                      const SizedBox(height: 8),
                      Text(s.t('adv_own_image_or'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                      const SizedBox(height: 16),
                      _ownImageButton(s),
                    ],
                  ],
                ),
              ),
            );
          }
          if (_editing && !_loadedOrder && editOrder != null) {
            _loadedOrder = true;
            // Filling the text fields notifies listeners → do it after this frame.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _loadOrder(editOrder, list));
            });
          } else if (_admin && !_loadedOrder && adminLoaded && adminOrder != null) {
            _loadedOrder = true;
            final o = adminOrder;
            final a = adminAd;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _loadOrder(o, list, ad: a));
            });
          } else if (!_editing && !_admin && _tpl == null && list.isNotEmpty) {
            AdTemplate first = list.first;
            for (final x in list) {
              if (x.id == widget.initialTemplateId) first = x;
            }
            _tpl = first;
          }
          final t = _tpl;
          if (t == null) {
            if (_admin && adminLoaded && adminOrder == null) {
              return Center(child: Text(s.t('adv_order_missing')));
            }
            final orders = _editing ? ref.watch(myAdOrdersProvider) : null;
            if (orders != null && orders.hasValue && editOrder == null) {
              return Center(child: Text(s.t('adv_order_missing')));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final preview = AdCreative(
            version: 2,
            imageUrl: t.imageUrl,
            texts: _texts,
            style: Map.of(_style),
            logoUrl: _logoUrl,
            logoBg: _logoBg,
          );
          final st = _style[_styleLine]!;
          final shownList = [if (_keptTpl != null && !list.any((x) => x.id == _keptTpl!.id)) _keptTpl!, ...list];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
            children: [
              if (orderingOff) ...[_orderingOffNote(s), const SizedBox(height: 12)],
              Text(s.t('adv_preview').toUpperCase(), style: adSectionHeader),
              const SizedBox(height: 8),
              AdCreativeView(creative: preview, radius: BorderRadius.circular(14), showPlaceholders: true),
              if (_editing && editOrder?.receiptPath != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(s.t('adv_edit_review_note'), style: TextStyle(color: AppColors.blue, fontSize: 12.5)),
                ),
              ],
              section(1, 'adv_step_background'),
              SizedBox(
                // 104 at the normal text size; grows with the template name.
                height: 90 + MediaQuery.textScalerOf(context).scale(14),
                child: MouseDragScroll(child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: shownList.length + (_forService && !_admin ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    // Service ad: first tile = "upload my own picture".
                    final ownTile = _forService && !_admin;
                    if (ownTile && index == 0) {
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _ownUploading ? null : () => _addOwnImage(s),
                        child: Container(
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.line),
                            color: AppColors.cardAlt,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ownUploading
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(Icons.add_photo_alternate_outlined, color: AppColors.accent),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(s.t('adv_own_image_add'), textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final i = ownTile ? index - 1 : index;
                    final x = shownList[i];
                    final sel = x.id == t.id;
                    return GestureDetector(
                      onTap: () => setState(() => _tpl = x),
                      child: Container(
                        width: 220,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sel ? AppColors.accent : AppColors.line, width: sel ? 2 : 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AdCreativeView(creative: x.sample(), radius: BorderRadius.circular(8)),
                            const SizedBox(height: 4),
                            Text(x.isOwn ? s.t('adv_own_image') : x.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
                          ],
                        ),
                      ),
                    );
                  },
                )),
              ),
              section(2, 'adv_step_texts'),
              TextField(
                controller: _company,
                maxLength: AdStandardLayout.maxLen['company'],
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: s.t('adv_company'), hintText: 'DELTA-GEO'),
              ),
              TextField(
                controller: _activity,
                maxLength: AdStandardLayout.maxLen['activity'],
                decoration: InputDecoration(labelText: s.t('adv_activity'), hintText: 'Logistics'),
              ),
              TextField(
                controller: _phone,
                maxLength: AdStandardLayout.maxLen['phone'],
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.t('adv_phone'), hintText: '+994 00 000 00 00', prefixIcon: const Icon(Icons.phone_in_talk, size: 18)),
              ),
              section(3, 'adv_step_logo'),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _logoUploading ? null : () => _pickLogo(s),
                    icon: _logoUploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(s.t(_logoUrl == null ? 'adv_logo_add' : 'adv_logo_change')),
                  ),
                  if (_logoUrl != null)
                    TextButton(onPressed: () => setState(() => _logoUrl = null), child: Text(s.t('adv_logo_remove'))),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.t('adv_logo_rules'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'dark', label: Text(s.t('adv_logo_bg_dark'))),
                  ButtonSegment(value: 'light', label: Text(s.t('adv_logo_bg_light'))),
                  ButtonSegment(value: 'none', label: Text(s.t('adv_logo_bg_none'))),
                ],
                selected: {_logoBg},
                onSelectionChanged: (v) => setState(() => _logoBg = v.first),
              ),
              section(4, 'adv_step_style'),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'company', label: Text(s.t('adv_company_short'))),
                  ButtonSegment(value: 'activity', label: Text(s.t('adv_activity_short'))),
                  ButtonSegment(value: 'phone', label: Text(s.t('adv_phone'))),
                ],
                selected: {_styleLine},
                onSelectionChanged: (v) => setState(() => _styleLine = v.first),
              ),
              // Font choice is shown only when there is more than one font;
              // the app uses only Arial, so it is hidden.
              if (AdStandardLayout.fonts.length > 1) ...[
                const SizedBox(height: 10),
                Text(s.t('adv_font'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in AdStandardLayout.fonts)
                      ChoiceChip(
                        label: Text('Əa Şş', style: adFontStyle(f, const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                        tooltip: f,
                        selected: st.font == f,
                        onSelected: (_) => setState(() => _style[_styleLine] = st.copyWith(font: f)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(width: 72, child: Text(s.t('adv_size'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft))),
                  Expanded(
                    child: Slider(
                      value: st.size,
                      min: 0.6,
                      max: 1.0,
                      divisions: 8,
                      label: '${(st.size * 100).round()}%',
                      onChanged: (v) => setState(() => _style[_styleLine] = st.copyWith(size: v)),
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${(st.size * 100).round()}%', style: const TextStyle(fontSize: 12))),
                ],
              ),
              Text(s.t('adv_color'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
              const SizedBox(height: 6),
              _ColorPicker(
                value: st.color,
                onChanged: (c) => setState(() => _style[_styleLine] = st.copyWith(color: c)),
              ),
              const SizedBox(height: 4),
              Text(s.t('adv_shadow_note'), style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
              if (!_editing && (_forService || _adminServiceAd)) ...[
                section(5, 'ad_destination'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.home_repair_service_outlined, color: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.t('adv_service_destination'), style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
                section(6, 'adv_service_countries'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in Countries.all)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${c.flag} ${c.name(lang)}', style: const TextStyle(fontSize: 12.5)),
                        selected: _countries.contains(c.code),
                        onSelected: (v) => setState(() => v ? _countries.add(c.code) : _countries.remove(c.code)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(s.t('adv_service_countries_hint'), style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
              ],
              if (!_editing && !_forService && !_adminServiceAd) ...[
                section(5, 'ad_destination'),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'profile', label: Text(s.t('ad_destination_profile')), icon: const Icon(Icons.person_outline)),
                    ButtonSegment(value: 'external', label: Text(s.t('ad_destination_external')), icon: const Icon(Icons.open_in_new)),
                  ],
                  selected: {_destination},
                  onSelectionChanged: (v) => setState(() => _destination = v.first),
                ),
                if (_destination == 'external') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(labelText: s.t('ad_external_url'), hintText: 'https://example.com'),
                  ),
                ],
                section(6, 'ad_targeting'),
                Text(s.t('ad_target_countries'), style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in Countries.all)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${c.flag} ${c.name(lang)}', style: const TextStyle(fontSize: 12.5)),
                        selected: _countries.contains(c.code),
                        onSelected: (v) => setState(() => v ? _countries.add(c.code) : _countries.remove(c.code)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _CountryDropdown(
                  label: s.t('ad_route_from'),
                  value: _routeFrom,
                  anyLabel: s.t('ad_route_any'),
                  lang: lang,
                  onChanged: (v) => setState(() => _routeFrom = v),
                ),
                const SizedBox(height: 8),
                _CountryDropdown(
                  label: s.t('ad_route_to'),
                  value: _routeTo,
                  anyLabel: s.t('ad_route_any'),
                  lang: lang,
                  onChanged: (v) => setState(() => _routeTo = v),
                ),
                const SizedBox(height: 4),
                Text(s.t('ad_route_hint'), style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                if (_admin && _legacyRoute != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      'Köhnə marşrut dəyəri tanınmadı: "$_legacyRoute". Bu səbəbdən reklam heç bir yükə uyğun gəlmirdi. '
                      'Ölkə seçin və ya "${s.t('ad_route_any')}" saxlayın, sonra yadda saxlayın.',
                      style: TextStyle(color: AppColors.danger, fontSize: 12.5),
                    ),
                  ),
                ],
              ],
              if (_admin && _adId != null) ...[
                section(7, 'adv_admin_dates'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickAdDate(true),
                        icon: const Icon(Icons.event, size: 18),
                        label: Text('Başlama: ${_adStart == null ? '—' : fmt.format(_adStart!)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickAdDate(false),
                        icon: const Icon(Icons.event_busy, size: 18),
                        label: Text('Bitmə: ${_adEnd == null ? '—' : fmt.format(_adEnd!)}'),
                      ),
                    ),
                  ],
                ),
              ],
              if (!_editing && !_admin) ...[
                section(7, 'adv_step_duration'),
                if (durations.isEmpty)
                  Text(s.t('adv_no_prices'), style: TextStyle(color: AppColors.textSoft))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in const [5, 15, 30])
                        ChoiceChip(
                          label: Text(durations[d] == null
                              ? s.t('ad_days', {'n': '$d'})
                              : '${s.t('ad_days', {'n': '$d'})} · ${adMoney(durations[d]!.price, durations[d]!.currency)}'),
                          selected: _days == d,
                          onSelected: durations[d] == null ? null : (_) => setState(() => _days = d),
                        ),
                    ],
                  ),
                if (pkg != null) ...[
                  const SizedBox(height: 8),
                  Text(s.t('adv_starts_on_approval', {'days': '${pkg.days}'}),
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                ],
                const SizedBox(height: 14),
                TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: s.t('ad_note_label'))),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(color: AppColors.hero, border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(
            children: [
              Expanded(
                child: _admin
                    ? Text('Dəyişikliklər yadda saxlanan kimi reklamda görünür.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSoft))
                    : _editing
                    ? Text(s.t('adv_edit_hint'), style: TextStyle(fontSize: 12, color: AppColors.textSoft))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.t('adv_total'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                          Text(
                            pkg != null ? adMoney(pkg.price, pkg.currency) : '—',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          if (pkg != null)
                            Text(s.t('adv_starts_after_approval_short', {'days': '${pkg.days}'}),
                                style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                        ],
                      ),
              ),
              FilledButton(
                onPressed: _busy ? null : () => _submit(s, durations, lang),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(s.t((_editing || _admin) ? 'adv_save' : 'adv_confirm_ok')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Free colour choice: quick swatches + any colour (hue / lightness).
class _ColorPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _ColorPicker({required this.value, required this.onChanged});

  static const _swatches = [
    '#FFFFFF', '#F2F4F7', '#FFCC00', '#FFB020', '#FF6B33', '#E11D48',
    '#4ADE80', '#22C55E', '#3BA3FF', '#1D4ED8', '#A78BFA', '#000000',
  ];

  static String _hex(Color c) {
    String h(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${h(c.r)}${h(c.g)}${h(c.b)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final current = Color(adColorValue(value));
    final hsl = HSLColor.fromColor(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in _swatches)
              GestureDetector(
                onTap: () => onChanged(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(adColorValue(c)),
                    shape: BoxShape.circle,
                    border: Border.all(color: value.toUpperCase() == c ? AppColors.accent : AppColors.line, width: value.toUpperCase() == c ? 3 : 1),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Any colour: hue + lightness
        Container(
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            gradient: LinearGradient(colors: [
              for (var h = 0; h <= 360; h += 60) HSLColor.fromAHSL(1, h.toDouble(), 0.85, 0.55).toColor(),
            ]),
          ),
        ),
        Slider(
          value: hsl.hue,
          min: 0,
          max: 360,
          onChanged: (h) => onChanged(_hex(HSLColor.fromAHSL(1, h, hsl.saturation < 0.2 ? 0.85 : hsl.saturation,
              (hsl.lightness < 0.15 || hsl.lightness > 0.9) ? 0.55 : hsl.lightness).toColor())),
        ),
        Row(
          children: [
            Icon(Icons.brightness_6, size: 16, color: AppColors.textSoft),
            Expanded(
              child: Slider(
                value: hsl.lightness,
                min: 0,
                max: 1,
                onChanged: (l) => onChanged(_hex(hsl.withLightness(l).toColor())),
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: current, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
            ),
            const SizedBox(width: 6),
            Text(value.toUpperCase(), style: AppFonts.mono(size: 12, color: AppColors.textSoft)),
          ],
        ),
      ],
    );
  }
}

/// Route end: one country from the list (stored as its code) or "any".
class _CountryDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final String anyLabel;
  final String lang;
  final ValueChanged<String?> onChanged;
  const _CountryDropdown({required this.label, required this.value, required this.anyLabel, required this.lang, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      // ignore: deprecated_member_use
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(anyLabel)),
        for (final c in Countries.all)
          DropdownMenuItem<String?>(value: c.code, child: Text('${c.flag} ${c.name(lang)}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

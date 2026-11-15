import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/brand/site_logos.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/framed_image.dart';
import '../../../core/widgets/image_frame_editor.dart';
import '../../../core/widgets/tirlink_wordmark.dart';
import '../../verified/verified_account.dart' show isChiefAdminProvider;
import 'admin_widgets.dart' show runAdmin;

/// One place a logo shows (owner, 15.11.2026: "3 hissəyə ayır").
class LogoPlace {
  final String slot;
  final String title;
  final String where;

  /// The size of the PNG made from the framed picture.
  final int size;

  /// Not transparent (the phone icon).
  final bool opaque;
  const LogoPlace(this.slot, this.title, this.where, this.size, {this.opaque = false});
}

const kLogoPlaces = [
  LogoPlace('app_icon', 'Telefon ikonu', 'iPhone / Android "Ana ekrana əlavə et" ikonu və brauzer sekməsi', 512,
      opaque: true),
  LogoPlace('home_logo', 'Ana səhifədəki loqo',
      '"TırLink" yazısının solunda: Yüklər, kompüterin yan menyusu, giriş səhifəsi', 256),
  LogoPlace('splash', 'Yüklənmə səhifəsi', 'Sayt açılarkən qara fonda görünən loqo', 288),
];

/// Admin → "Loqolar" (owner, 15.11.2026, SQL 0124): the Baş admin uploads a
/// picture for each place, frames it (move / zoom, square), sees the result
/// and saves; "Standarta qaytar" brings the built-in logo back. Checked and
/// logged on the server (admin_site_logo_set, chief admin only).
class AdminLogosPage extends ConsumerWidget {
  const AdminLogosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chief = ref.watch(isChiefAdminProvider).valueOrNull == true;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
      Text('Loqolar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
      const SizedBox(height: 6),
      Text(
        chief
            ? 'Şəkli yükləyin, yerini və ölçüsünü düzəldin, sonra yadda saxlayın. Dəyişiklik sayta dərhal düşür.'
            : 'Loqoları yalnız Baş admin dəyişə bilər.',
        style: TextStyle(color: AppColors.textSoft),
      ),
      const SizedBox(height: 14),
      for (final p in kLogoPlaces) ...[_LogoCard(place: p, enabled: chief), const SizedBox(height: 12)],
      Text(
        'Qeyd: iPhone artıq ana ekrana əlavə edilmiş ikonu öz-özünə dəyişmir. Yeni ikonu görmək üçün köhnə ikonu silib '
        'Safari-də yenidən "Ana ekrana əlavə et" edin. Yüklənmə səhifəsi növbəti açılışdan yenilənir.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSoft),
      ),
    ]);
  }
}

class _LogoCard extends ConsumerStatefulWidget {
  final LogoPlace place;
  final bool enabled;
  const _LogoCard({required this.place, required this.enabled});

  @override
  ConsumerState<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends ConsumerState<_LogoCard> {
  bool _busy = false;

  Future<void> _upload() async {
    final p = widget.place;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final framing = await Navigator.of(context).push<ImageFraming>(MaterialPageRoute(
      builder: (_) => ImageFrameEditorScreen(
        image: MemoryImage(bytes),
        aspect: 1,
        circle: false,
        title: p.title,
        s: ref.read(stringsProvider),
      ),
    ));
    if (framing == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final png = await renderFramedSquare(bytes, framing, p.size, background: p.opaque ? kAppIconGround : null);
      if (!mounted) return;
      final ok = await _confirm(png);
      if (ok != true || !mounted) return;
      await runAdmin(context, () => SiteLogos.save(p.slot, png), success: 'Loqo yeniləndi ✓');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Şəkil hazırlanmadı, başqa şəkil seçin')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The result before it is saved.
  Future<bool?> _confirm(Uint8List png) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(widget.place.title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _Preview(image: MemoryImage(png), icon: widget.place.opaque),
            const SizedBox(height: 8),
            Text(widget.place.where, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Ləğv et')),
            FilledButton(
                key: const ValueKey('admin-logo-save'),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Yadda saxla')),
          ],
        ),
      );

  Future<void> _reset() async {
    setState(() => _busy = true);
    await runAdmin(context, () => SiteLogos.reset(widget.place.slot), success: 'Standart loqo qaytarıldı');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    return Container(
      key: ValueKey('admin-logo-${p.slot}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: ValueListenableBuilder<String?>(
        valueListenable: SiteLogos.of(p.slot),
        builder: (context, url, _) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Preview(
            image: url != null ? NetworkImage(url) as ImageProvider : const AssetImage(TirLinkWordmark.logoAsset),
            icon: p.opaque,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
              const SizedBox(height: 4),
              Text(p.where, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
              const SizedBox(height: 4),
              Text(url == null ? 'İndi: standart loqo' : 'İndi: sizin yüklədiyiniz loqo',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  key: ValueKey('admin-logo-upload-${p.slot}'),
                  onPressed: !widget.enabled || _busy ? null : _upload,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_outlined, size: 18),
                  label: const Text('Şəkil yüklə və düzəlt'),
                ),
                if (url != null)
                  OutlinedButton(
                    key: ValueKey('admin-logo-reset-${p.slot}'),
                    onPressed: !widget.enabled || _busy ? null : _reset,
                    child: const Text('Standarta qaytar'),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The logo on a dark square; a phone icon gets the phone's rounded corners.
class _Preview extends StatelessWidget {
  final ImageProvider image;
  final bool icon;
  const _Preview({required this.image, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(color: kAppIconGround, borderRadius: BorderRadius.circular(icon ? 20 : 10)),
      clipBehavior: Clip.antiAlias,
      padding: icon ? EdgeInsets.zero : const EdgeInsets.all(6),
      child: Image(image: image, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
    );
  }
}

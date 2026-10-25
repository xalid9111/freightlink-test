import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';
import '../../../repositories/profile_repository.dart';
import '../data/ads_repository.dart';
import 'ad_creative_view.dart';
import '../../../core/router/safe_navigation.dart';

const _verifiedBlue = Color(0xFF1D9BF0);

/// Compact sponsored slot in the home feed — no taller than a cargo
/// card: only the banner (fixed 4.5:1 format), a small "SPONSORLU" tag
/// in the top-left corner and, for verified advertisers, the blue tick
/// top-right. Tapping opens the advertiser's FreightLink profile.
class SponsoredBanner extends ConsumerStatefulWidget {
  final Ad ad;
  final AppStrings strings;
  const SponsoredBanner({super.key, required this.ad, required this.strings});

  @override
  ConsumerState<SponsoredBanner> createState() => _SponsoredBannerState();
}

class _SponsoredBannerState extends ConsumerState<SponsoredBanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adsRepositoryProvider).recordEvent(widget.ad.id, 'impression');
    });
  }

  Future<void> _open() async {
    await ref.read(adsRepositoryProvider).recordEvent(widget.ad.id, 'click');
    if (!mounted) return;
    final ad = widget.ad;
    if (ad.destinationType == 'external' && ad.destinationUrl != null) {
      final uri = Uri.tryParse(ad.destinationUrl!);
      if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    if (ad.destinationType == 'service' && (ad.destinationUrl ?? '').isNotEmpty) {
      context.pushOnce('/service/${ad.destinationUrl}');
      return;
    }
    context.pushOnce('/user/${ad.advertiserId}');
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final strings = widget.strings;
    final p = ref.watch(publicProfileProvider(ad.advertiserId)).valueOrNull;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: AspectRatio(
          aspectRatio: AdBannerSpec.ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ad.creative != null)
                AdCreativeView(creative: ad.creative!)
              else
              Image.network(
                ad.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.cardAlt,
                  alignment: Alignment.center,
                  child: Text(p?.fullName ?? '', style: TextStyle(color: AppColors.textSoft)),
                ),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : ColoredBox(color: AppColors.cardAlt),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(strings.t('ad_badge'),
                      style: AppFonts.mono(size: 8.5, color: AppColors.accent, letterSpacing: 1.0)),
                ),
              ),
              if (p?.isVerified == true)
                const Positioned(
                  top: 5,
                  right: 6,
                  child: Icon(Icons.verified, color: _verifiedBlue, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty ad slot (no unused ad left for this position): same size as a
/// banner, just "Reklam əlavə et" — opens the advertise screen.
class AdPlaceholder extends StatelessWidget {
  final AppStrings strings;
  const AdPlaceholder({super.key, required this.strings});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushOnce('/ads'),
        child: AspectRatio(
          aspectRatio: AdBannerSpec.ratio,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_circle_outline, size: 18, color: AppColors.textSoft),
                const SizedBox(width: 8),
                Text(strings.t('ad_place_here'),
                    style: TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w400)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

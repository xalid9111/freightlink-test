import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/supabase_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/theme/app_theme.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../finance/domain/finance_models.dart';
import '../finance/presentation/card_checkout.dart';
import '../finance/presentation/finance_providers.dart';

/// "Təsdiqlənmiş hesab" (owner, 07.11.2026, 0104). Two ways to the blue
/// badge, kept apart on the server:
///  * [granted] — the Baş admin's own grant (users.is_verified; only the Baş
///    admin changes it, checked by a trigger for every path);
///  * [paid] — the 20 AZN / month subscription, activated only by a verified
///    LIVE payment (a test payment never activates it).
class VerifiedStatus {
  final bool granted, paid;
  final DateTime? paidUntil;
  const VerifiedStatus({this.granted = false, this.paid = false, this.paidUntil});

  bool get verified => granted || paid;

  factory VerifiedStatus.fromJson(Map<String, dynamic> j) => VerifiedStatus(
        granted: j['granted'] == true,
        paid: j['paid'] == true,
        paidUntil: j['paid_until'] == null ? null : DateTime.tryParse('${j['paid_until']}')?.toLocal(),
      );
}

/// The monthly plan (the server's price; null = not offered / SQL 0104 not run).
class VerifiedPlan {
  final int months;
  final double price;
  final String currency;
  const VerifiedPlan({required this.months, required this.price, required this.currency});
}

const _timeout = Duration(seconds: 20);

class VerifiedAccountRepository {
  Future<VerifiedStatus?> status(String userId) async {
    try {
      final res = await SupabaseConfig.client
          .rpc('account_verification', params: {'p_user': userId}).timeout(_timeout);
      return res == null ? null : VerifiedStatus.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (_) {
      return null; // before SQL 0104 / offline: the old is_verified decides
    }
  }

  Future<VerifiedPlan?> plan() async {
    try {
      final rows = await SupabaseConfig.client
          .from('verified_plans')
          .select()
          .eq('months', 1)
          .eq('is_active', true)
          .limit(1)
          .timeout(_timeout);
      if ((rows as List).isEmpty) return null;
      final r = rows.first;
      return VerifiedPlan(
          months: (r['months'] as num).toInt(), price: (r['price'] as num).toDouble(), currency: (r['currency'] as String?) ?? 'AZN');
    } catch (_) {
      return null;
    }
  }

  /// My order; the server sets the price.
  Future<VipCheckoutTarget> order() async {
    final res = await SupabaseConfig.client.rpc('verified_order_create', params: {'p_months': 1}).timeout(_timeout);
    final j = Map<String, dynamic>.from(res as Map);
    return VipCheckoutTarget(
        vipOrderId: '${j['id']}', amount: (j['amount'] as num).toDouble(), currency: (j['currency'] as String?) ?? 'AZN', verified: true);
  }

  /// The Baş admin only (checked on the server).
  Future<bool> isChiefAdmin() async {
    try {
      return (await SupabaseConfig.client.rpc('is_chief_admin').timeout(_timeout)) == true;
    } catch (_) {
      return false;
    }
  }

  /// Baş admin: give / take the blue badge without payment (refused for
  /// everybody else on the server).
  Future<void> adminSet(String userId, bool on) =>
      SupabaseConfig.client.rpc('admin_set_account_verified', params: {'p_user': userId, 'p_on': on}).timeout(_timeout);
}

final verifiedAccountRepositoryProvider = Provider<VerifiedAccountRepository>((ref) => VerifiedAccountRepository());

final verifiedStatusProvider = FutureProvider.autoDispose.family<VerifiedStatus?, String>((ref, userId) {
  ref.watch(currentUserIdProvider);
  return ref.watch(verifiedAccountRepositoryProvider).status(userId);
});

final verifiedPlanProvider = FutureProvider.autoDispose<VerifiedPlan?>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(verifiedAccountRepositoryProvider).plan();
});

final isChiefAdminProvider = FutureProvider.autoDispose<bool>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return ref.watch(verifiedAccountRepositoryProvider).isChiefAdmin();
});

String _price(double v, String c) => '${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)} $c';

/// The badge on the Profil card (owner's picture, 07.11.2026), under the
/// account owner's details: verified → the clear blue badge; not yet → the
/// pale badge, the slogan and "Ayda 20 AZN · Aktiv et".
class VerifiedAccountBlock extends ConsumerStatefulWidget {
  final AppStrings s;
  final String userId;
  /// users.is_verified as the profile loaded it (used until 0104 answers).
  final bool legacyVerified;
  /// The account's own card (the offer is shown only to its owner).
  final bool own;
  const VerifiedAccountBlock({super.key, required this.s, required this.userId, required this.legacyVerified, this.own = true});

  @override
  ConsumerState<VerifiedAccountBlock> createState() => _VerifiedAccountBlockState();
}

class _VerifiedAccountBlockState extends ConsumerState<VerifiedAccountBlock> {
  bool _busy = false;

  AppStrings get s => widget.s;

  Future<void> _activate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final av = await ref.read(checkoutAvailabilityProvider.future);
      if (!mounted) return;
      // No real (LIVE) payment yet: say so; never a made-up activation.
      if (!av.available || av.mode != 'live') {
        setState(() => _busy = false);
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            key: const ValueKey('vf-not-live'),
            title: Text(s.t('pf_verified_account')),
            content: Text(s.t('vf_not_live')),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(MaterialLocalizations.of(c).okButtonLabel))],
          ),
        );
        return;
      }
      final target = await ref.read(verifiedAccountRepositoryProvider).order();
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        builder: (_) => CheckoutSheet(vip: target, s: s, availability: av, methods: methodsForDevice(currentDeviceKind(), av.methods)),
      );
      container.invalidate(verifiedStatusProvider(widget.userId));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('vf_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(verifiedStatusProvider(widget.userId)).valueOrNull;
    final verified = st?.verified ?? widget.legacyVerified;
    final blue = AppColors.blue;
    if (verified) {
      return _pill(
        key: const ValueKey('vf-active'),
        icon: Icons.verified,
        label: s.t('pf_verified_account'),
        color: blue,
        bg: blue.withValues(alpha: 0.14),
      );
    }
    final plan = widget.own ? ref.watch(verifiedPlanProvider).valueOrNull : null;
    return Column(key: const ValueKey('vf-offer'), crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      // Pale, passive: not verified yet.
      _pill(
        key: const ValueKey('vf-passive'),
        icon: Icons.verified,
        label: s.t('pf_verified_account'),
        color: blue.withValues(alpha: 0.45),
        bg: blue.withValues(alpha: 0.07),
      ),
      if (widget.own) ...[
        const SizedBox(height: 4),
        Text(s.t('vf_slogan'),
            key: const ValueKey('vf-slogan'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSoft, fontSize: 12, fontStyle: FontStyle.italic)),
        // Only with the server's price (no made-up amount).
        if (plan != null) ...[
          const SizedBox(height: 6),
          Material(
            color: AppColors.accent.withValues(alpha: 0.10),
            shape: StadiumBorder(side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6))),
            child: InkWell(
              key: const ValueKey('vf-activate'),
              customBorder: const StadiumBorder(),
              onTap: _busy ? null : _activate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _busy
                      ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                      : Icon(Icons.workspace_premium_outlined, size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(s.t('vf_activate', {'price': _price(plan.price, plan.currency)}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ],
    ]);
  }

  Widget _pill({required Key key, required IconData icon, required String label, required Color color, required Color bg}) => Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w400))),
        ]),
      );
}

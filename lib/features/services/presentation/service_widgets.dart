import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/service_models.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../chat/data/group_repository.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/presentation/widgets/call_options.dart';
import '../../chat/presentation/widgets/location_message.dart';
import 'services_providers.dart';
import '../../../core/router/safe_navigation.dart';

/// Round map pin: colour + icon by type (mobile mechanic / service centre /
/// tow truck). Inactive providers are drawn faded.
class ServicePin extends StatelessWidget {
  final ServiceMarkerType type;
  final bool active;
  final bool selected;
  /// PRO service: gold ring around the pin.
  final bool pro;
  const ServicePin({super.key, required this.type, this.active = true, this.selected = false, this.pro = false});

  @override
  Widget build(BuildContext context) {
    final c = serviceMarkerColor(type);
    final size = selected ? 40.0 : 32.0;
    return Center(
      child: Opacity(
        opacity: active ? 1 : 0.55,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: pro ? kProGold : Colors.white, width: pro ? (selected ? 4 : 3) : (selected ? 3 : 2)),
            boxShadow: pro
                ? const [BoxShadow(color: Color(0x99FFC83D), blurRadius: 10, spreadRadius: 1)]
                : const [BoxShadow(color: Colors.black54, blurRadius: 5)],
          ),
          child: Icon(serviceMarkerIcon(type), size: selected ? 22 : 18, color: type == ServiceMarkerType.tow ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}

/// Gold colour of PRO services.
const kProGold = Color(0xFFFFC83D);

/// Gold "PRO" badge for services the admin marked as PRO (0028).
class ServiceProBadge extends StatelessWidget {
  final bool compact;
  const ServiceProBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 8, vertical: compact ? 1 : 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFE08A), kProGold, Color(0xFFE59A1A)]),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Color(0x66FFC83D), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: compact ? 11 : 14, color: const Color(0xFF3A2500)),
          SizedBox(width: compact ? 2 : 3),
          Text('PRO',
              style: TextStyle(
                fontSize: compact ? 9.5 : 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: const Color(0xFF3A2500),
              )),
        ],
      ),
    );
  }
}

/// Verified tick, or an "unverified" chip for profiles whose owner has
/// not been confirmed yet.
class ServiceTrustBadge extends StatelessWidget {
  final ServiceProvider p;
  final AppStrings s;
  final bool compact;
  const ServiceTrustBadge({super.key, required this.p, required this.s, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (p.isVerified) {
      return Icon(Icons.verified, size: compact ? 15 : 18, color: AppColors.blue);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(s.t('svc_unverified'), style: TextStyle(fontSize: compact ? 9.5 : 11, color: AppColors.textSoft)),
    );
  }
}

class RatingStars extends StatelessWidget {
  final double value;
  final double size;
  const RatingStars({super.key, required this.value, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i ? Icons.star_rounded : (value >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
            size: size,
            color: const Color(0xFFFACC15),
          ),
      ],
    );
  }
}

/// Call / Message / Route buttons for a provider.
class ServiceContactBar extends ConsumerStatefulWidget {
  final ServiceProvider p;
  final AppStrings s;
  final bool dense;
  const ServiceContactBar({super.key, required this.p, required this.s, this.dense = false});

  @override
  ConsumerState<ServiceContactBar> createState() => _ServiceContactBarState();
}

class _ServiceContactBarState extends ConsumerState<ServiceContactBar> {
  bool _opening = false;

  Future<void> _message() async {
    final owner = widget.p.ownerId;
    if (owner == null) return;
    setState(() => _opening = true);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(owner);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.s.t('chat_open_failed'))));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// WhatsApp number of the service (its WhatsApp field, else its phone),
  /// digits only for wa.me; null if it has neither.
  String? _waDigits() {
    final raw = (widget.p.whatsapp ?? '').trim().isNotEmpty ? widget.p.whatsapp! : (widget.p.phone ?? '');
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return d.length >= 7 ? d : null;
  }

  /// "Mesaj yaz": two choices — FreightLink chat and WhatsApp.
  Future<void> _messageOptions(bool canChat) async {
    final s = widget.s;
    final wa = _waDigits();
    final me = ref.read(currentUserIdProvider);
    final isMine = widget.p.ownerId != null && widget.p.ownerId == me;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(s.t('svc_msg_title'), style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: AppColors.accent),
              title: Text(s.t('svc_msg_in_app')),
              subtitle: canChat
                  ? null
                  : Text(s.t(isMine ? 'svc_msg_own' : 'svc_msg_no_owner'),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
              enabled: canChat,
              onTap: canChat
                  ? () {
                      Navigator.of(ctx).pop();
                      _message();
                    }
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined, color: Color(0xFF25D366)),
              title: Text(s.t('svc_msg_whatsapp')),
              subtitle: wa == null
                  ? Text(s.t('svc_msg_no_whatsapp'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft))
                  : null,
              enabled: wa != null,
              onTap: wa == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      launchUrl(Uri.parse('https://wa.me/$wa'), mode: LaunchMode.externalApplication);
                    },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _route() {
    final p = widget.p;
    showNavigationPicker(
      context,
      widget.s,
      ChatLocation(url: 'https://maps.google.com/?q=${p.lat},${p.lng}', lat: p.lat, lng: p.lng),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final s = widget.s;
    final me = ref.watch(currentUserIdProvider);
    final phone = (p.phone ?? '').trim();
    final canMessage = p.ownerId != null && p.ownerId != me;
    final pad = widget.dense ? const EdgeInsets.symmetric(horizontal: 6, vertical: 8) : const EdgeInsets.symmetric(horizontal: 10, vertical: 12);
    final style = TextStyle(fontSize: widget.dense ? 12 : 13.5, fontWeight: FontWeight.w600);

    Widget btn({required IconData icon, required String label, VoidCallback? onTap, bool primary = false}) {
      final child = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: widget.dense ? 16 : 18),
          const SizedBox(width: 5),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        ],
      );
      return Expanded(
        child: primary
            ? FilledButton(onPressed: onTap, style: FilledButton.styleFrom(padding: pad, minimumSize: Size.zero), child: child)
            : OutlinedButton(onPressed: onTap, style: OutlinedButton.styleFrom(padding: pad, minimumSize: Size.zero), child: child),
      );
    }

    return Row(
      children: [
        btn(
          icon: Icons.call,
          label: s.t('svc_call'),
          primary: true,
          onTap: phone.isEmpty ? null : () => showCallOptions(context, s, phone),
        ),
        const SizedBox(width: 6),
        btn(
          icon: Icons.chat_bubble_outline,
          label: s.t('svc_message'),
          // Always active: a short choice — in-app chat or WhatsApp.
          onTap: _opening ? null : () => _messageOptions(canMessage),
        ),
        const SizedBox(width: 6),
        btn(icon: Icons.directions, label: s.t('svc_route'), onTap: _route),
      ],
    );
  }
}

/// Small coloured legend row: what each marker means.
class ServiceLegend extends StatelessWidget {
  final AppStrings s;
  const ServiceLegend({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final t in ServiceMarkerType.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: serviceMarkerColor(t), shape: BoxShape.circle),
                child: Icon(serviceMarkerIcon(t), size: 10, color: t == ServiceMarkerType.tow ? Colors.black : Colors.white),
              ),
              const SizedBox(width: 4),
              Text(s.t(serviceMarkerLabelKey(t)), style: const TextStyle(fontSize: 11, color: AppColors.textSoft)),
            ],
          ),
      ],
    );
  }
}

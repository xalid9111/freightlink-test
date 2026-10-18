import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Round profile photo with initials fallback and an optional online dot.
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String initials;
  final double radius;
  /// null = no presence dot; true/false = green/grey dot.
  final bool? online;

  const UserAvatar({super.key, this.imageUrl, required this.initials, this.radius = 19, this.online});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.cardAlt,
          // Decoded at the size it is shown (×3 for sharp retina), not at
          // the full upload size — saves a lot of memory on iPhones.
          foregroundImage: hasImage ? ResizeImage(NetworkImage(imageUrl!), width: (radius * 6).round()) : null,
          child: Text(initials, style: AppFonts.display(size: radius * 0.85, color: AppColors.text)),
        ),
        if (online != null)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: radius * 0.62,
              height: radius * 0.62,
              decoration: BoxDecoration(
                color: online! ? AppColors.online : AppColors.textSoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.hero, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

/// Blue "verified" tick shown after a verified user's name.
class VerifiedTick extends StatelessWidget {
  final double size;
  const VerifiedTick({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => Icon(Icons.verified, size: size, color: AppColors.blue);
}

/// Small "Early member" pill.
class EarlyMemberChip extends StatelessWidget {
  final String label;
  const EarlyMemberChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 13, color: AppColors.accent),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
        ],
      ),
    );
  }
}

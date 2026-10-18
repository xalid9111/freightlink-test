import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';

/// TIR Bazarı (truck / trailer / machinery sales). Loaded as a separate
/// part of the app (deferred) only when the tab is opened. The listing
/// module comes in the next stage; until then the page says so honestly.
class MarketHomeScreen extends ConsumerWidget {
  const MarketHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: AppColors.accent, size: 26),
                const SizedBox(width: 10),
                Text(s.t('nav_market'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.text)),
              ],
            ),
            const SizedBox(height: 40),
            const Icon(Icons.construction, size: 44, color: AppColors.textSoft),
            const SizedBox(height: 12),
            Text(s.t('market_coming'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSoft, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

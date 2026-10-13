import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../localization/locale_controller.dart';
import '../theme/app_theme.dart';
import 'autofix.dart';

/// Unknown route / broken link: reported to AutoFix (navigation) and the
/// user gets a way back instead of a dead end.
class RouteErrorScreen extends ConsumerStatefulWidget {
  final String location;
  final Object? error;
  const RouteErrorScreen({super.key, required this.location, this.error});

  @override
  ConsumerState<RouteErrorScreen> createState() => _RouteErrorScreenState();
}

class _RouteErrorScreenState extends ConsumerState<RouteErrorScreen> {
  @override
  void initState() {
    super.initState();
    AutoFix.instance.captureNavigation(widget.location, widget.error);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off, size: 48, color: AppColors.textSoft),
                const SizedBox(height: 12),
                Text(s.t('autofix_route_missing'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => context.go('/cargo'), child: Text(s.t('autofix_go_home'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../autofix/autofix_platform_stub.dart' if (dart.library.js_interop) '../autofix/autofix_platform_web.dart' as platform;

/// Shows a page from a `deferred as` library: its code is downloaded only
/// the first time the page is opened (smaller first load of the app).
class DeferredPage extends StatefulWidget {
  final Future<void> Function() load;
  final WidgetBuilder builder;
  const DeferredPage({super.key, required this.load, required this.builder});

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  late Future<void> _future = _load();

  /// Right after a new version is published the old app code can still be
  /// cached while this part is new, so loading it fails: then fetch fresh
  /// files and reload the app once (session kept). If that was just done,
  /// the retry button shows instead.
  Future<void> _load() async {
    try {
      await widget.load();
    } catch (_) {
      if (platform.freshReload()) await Future<void>.delayed(const Duration(seconds: 30));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) return widget.builder(context);
        if (snap.hasError) {
          // Network hiccup while downloading the part: tap to try again.
          return Scaffold(
            body: Center(
              child: IconButton(
                iconSize: 36,
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() => _future = widget.load()),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

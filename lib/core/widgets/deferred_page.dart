import 'package:flutter/material.dart';

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
  late Future<void> _future = widget.load();

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

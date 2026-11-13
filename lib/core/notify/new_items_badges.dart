import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/supabase_config.dart';

/// "New since you last looked" counts next to the TIRPark and TIR Bazarı
/// buttons (owner, 13.11.2026: "yeni park, servis, mağaza əlavə edilərsə,
/// TIR Bazarında yeni elan paylaşılarsa düymənin qarşısında 1 yazılsın").
///
/// * tirpark = approved parks created / approved since then + published
///   services and shops created since then (not one's own service / shop).
/// * market = active TIR Bazarı ads created since then (not one's own).
/// The moment of the last look is kept on the device per account; the very
/// first time it is "now" (nothing old is counted). Opening the section
/// sets it to now. The server only counts (one number, no rows); asked when
/// the app opens, comes back, and every minute.
enum NewItemsSection { tirpark, market }

const kNewItemsEvery = Duration(seconds: 60);

String newItemsSeenKey(NewItemsSection s, String? uid) => 'fl_seen_${s.name}_${uid ?? 'guest'}';

class NewItemsController extends StateNotifier<Map<NewItemsSection, int>> {
  final String? uid;
  final Future<int> Function(NewItemsSection section, DateTime since, String? uid) count;
  Timer? _timer;
  final Map<NewItemsSection, DateTime> _seen = {};
  bool _busy = false;

  NewItemsController({required this.uid, required this.count, bool start = true}) : super(const {}) {
    if (start) {
      refresh();
      _timer = Timer.periodic(kNewItemsEvery, (_) => refresh());
    }
  }

  Future<DateTime> _since(NewItemsSection s) async {
    final known = _seen[s];
    if (known != null) return known;
    try {
      final p = await SharedPreferences.getInstance();
      final saved = DateTime.tryParse(p.getString(newItemsSeenKey(s, uid)) ?? '');
      if (saved != null) return _seen[s] = saved;
      final now = DateTime.now().toUtc();
      await p.setString(newItemsSeenKey(s, uid), now.toIso8601String());
      return _seen[s] = now;
    } catch (_) {
      return _seen[s] = DateTime.now().toUtc();
    }
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final next = <NewItemsSection, int>{};
      for (final s in NewItemsSection.values) {
        try {
          next[s] = await count(s, await _since(s), uid);
        } catch (_) {
          next[s] = state[s] ?? 0;
        }
      }
      if (mounted) state = next;
    } finally {
      _busy = false;
    }
  }

  /// The section was opened: nothing is new any more.
  Future<void> markSeen(NewItemsSection s) async {
    final now = DateTime.now().toUtc();
    _seen[s] = now;
    if ((state[s] ?? 0) != 0 && mounted) state = {...state, s: 0};
    try {
      (await SharedPreferences.getInstance()).setString(newItemsSeenKey(s, uid), now.toIso8601String());
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The server count (head-only, exact). Missing tables (an older database)
/// simply count 0.
Future<int> countNewItems(NewItemsSection section, DateTime since, String? uid) async {
  final c = SupabaseConfig.client;
  final t = since.toUtc().toIso8601String();
  Future<int> safe(Future<int> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 15));
    } on PostgrestException {
      return 0;
    }
  }

  switch (section) {
    case NewItemsSection.tirpark:
      final parks = await safe(() async => (await c
              .from('tir_parks')
              .select('id')
              .eq('status', 'approved')
              .or('created_at.gt.$t,reviewed_at.gt.$t')
              .limit(1)
              .count(CountOption.exact))
          .count);
      final services = await safe(() async {
        var q = c.from('service_providers').select('id').eq('status', 'approved').eq('is_active', true).gt('created_at', t);
        if (uid != null) q = q.or('owner_id.is.null,owner_id.neq.$uid');
        return (await q.limit(1).count(CountOption.exact)).count;
      });
      return parks + services;
    case NewItemsSection.market:
      return safe(() async {
        var q = c.from('market_listings').select('id').eq('status', 'active').gt('created_at', t);
        if (uid != null) q = q.neq('owner_id', uid);
        return (await q.limit(1).count(CountOption.exact)).count;
      });
  }
}

final newItemsProvider = StateNotifierProvider<NewItemsController, Map<NewItemsSection, int>>(
    (ref) => NewItemsController(uid: ref.watch(currentUserIdProvider), count: countNewItems));

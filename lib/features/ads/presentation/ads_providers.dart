import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/ad_models.dart';
import '../../../models/cargo_model.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../../core/config/supabase_config.dart';
import '../data/ads_repository.dart';

/// Live banners for the home feed. Failing to load ads must never break
/// the feed, so errors simply mean "no ads".
/// Only paid, started ads — and nothing at all while the admin's
/// "home ads" switch is off (migration 0021, default off).
final liveAdsProvider = FutureProvider<List<Ad>>((ref) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.watch(adsRepositoryProvider).homeFeedAds();
  } catch (_) {
    return const <Ad>[];
  }
});

/// Admin switch for ads on the home feed (false on any error / before 0021).
final homeAdsEnabledProvider = FutureProvider<bool>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(adsRepositoryProvider).homeAdsEnabled();
});

/// Where ads go in the loads list and how long each stays (0025).
final adsFeedLayoutProvider = FutureProvider<AdFeedLayout>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(adsRepositoryProvider).feedLayout();
});

/// Current minute number (minutes since epoch), updated while the app is
/// open — drives the time-based ad rotation.
final adMinuteTickProvider = StreamProvider.autoDispose<int>((ref) async* {
  int now() => DateTime.now().millisecondsSinceEpoch ~/ 60000;
  var last = now();
  yield last;
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 15))) {
    final m = now();
    if (m != last) {
      last = m;
      yield m;
    }
  }
});

/// Templates customers can pick: active and in the standard 1200×400 layout
/// — for load ads (audience cargo / all).
final adTemplatesProvider = FutureProvider.autoDispose<List<AdTemplate>>((ref) async {
  final list = await ref.watch(adsRepositoryProvider).templates();
  return list.where((t) => t.isStandard && t.forCargo).toList();
});

/// Templates for service ads (audience service / all) — same 1200×400 layout.
final serviceAdTemplatesProvider = FutureProvider.autoDispose<List<AdTemplate>>((ref) async {
  final list = await ref.watch(adsRepositoryProvider).templates();
  return list.where((t) => t.isStandard && t.forService).toList();
});

/// Second admin switch: show "Reklam ver" to customers (false before 0023).
final adsOrderingEnabledProvider = FutureProvider<bool>((ref) async {
  ref.watch(currentUserIdProvider);
  return ref.watch(adsRepositoryProvider).adsOrderingEnabled();
});

final adminAdTemplatesProvider = FutureProvider.autoDispose<List<AdTemplate>>((ref) async {
  // Users' own pictures (0032) are not admin templates — keep them out.
  final list = await ref.watch(adsRepositoryProvider).templates(all: true);
  return list.where((t) => !t.isOwn).toList();
});

/// One of my orders (live updates through the orders stream).
final myAdOrderProvider = Provider.autoDispose.family<AsyncValue<AdOrder?>, String>((ref, id) {
  return ref.watch(myAdOrdersProvider).whenData((list) {
    for (final o in list) {
      if (o.id == id) return o;
    }
    return null;
  });
});

final adReceiptUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) {
  return ref.watch(adsRepositoryProvider).receiptUrl(path);
});

final adPackagesProvider = FutureProvider.autoDispose<List<AdPackage>>((ref) {
  return ref.watch(adsRepositoryProvider).packages();
});

final adPaymentInfoProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    return await ref.watch(adsRepositoryProvider).paymentInfo();
  } catch (_) {
    return null;
  }
});

final myAdOrdersProvider = StreamProvider.autoDispose<List<AdOrder>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <AdOrder>[]);
  return ref.watch(adsRepositoryProvider).watchMyOrders(uid);
});

final myAdStatsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(adsRepositoryProvider).myAdStats();
});

/// A user's open loads (public profile page).
final userOpenCargoProvider = FutureProvider.autoDispose.family<List<CargoModel>, String>((ref, userId) async {
  final rows = await SupabaseConfig.client
      .from('cargo')
      .select()
      .eq('owner_id', userId)
      .eq('status', 'new')
      .order('created_at', ascending: false)
      .limit(30);
  return (rows as List)
      .map((r) => CargoModel.fromJson(Map<String, dynamic>.from(r as Map)))
      .where((c) => c.isListedOn(DateTime.now()))
      .toList();
});

// ---- admin ----------------------------------------------------------------

final adminAdOrdersProvider = StreamProvider.autoDispose<List<AdOrder>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(adsRepositoryProvider).watchAllOrders();
});

final adminAdsProvider = StreamProvider.autoDispose<List<Ad>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(adsRepositoryProvider).watchAllAds();
});

final adminAdPackagesProvider = FutureProvider.autoDispose<List<AdPackage>>((ref) {
  return ref.watch(adsRepositoryProvider).allPackages();
});

/// Orders waiting for the admin (drives the bell / sidebar badge).
final adminAdWaitingProvider = Provider.autoDispose<int>((ref) {
  final orders = ref.watch(adminAdOrdersProvider).valueOrNull ?? const <AdOrder>[];
  return orders.where((o) => o.status == 'awaiting_approval' || o.status == 'approved').length;
});

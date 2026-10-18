import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/activities.dart';
import '../presentation/providers/auth_providers.dart';

const _timeout = Duration(seconds: 20);

/// Profile activities (migration 0039).
class ActivitiesRepository {
  final SupabaseClient _c = SupabaseConfig.client;

  Future<Set<Activity>> mine(String uid) async {
    Map<String, dynamic>? row;
    try {
      row = await _c.from('users').select('role, activities').eq('id', uid).maybeSingle().timeout(_timeout);
    } on PostgrestException {
      // 0039 not applied yet (no column): fall back to the old role.
      row = await _c.from('users').select('role').eq('id', uid).maybeSingle().timeout(_timeout);
    }
    var hasService = false;
    if (row != null && row['activities'] == null) {
      final svc = await _c.from('service_providers').select('id').eq('owner_id', uid).limit(1).timeout(_timeout);
      hasService = (svc as List).isNotEmpty;
    }
    return activitiesFrom(row?['activities'], role: row?['role'] as String?, hasService: hasService);
  }

  /// Saves the whole set; returns what the server stored.
  Future<Set<Activity>> save(Set<Activity> activities) async {
    final res = await _c.rpc('set_my_activities', params: {'p_activities': activitiesWire(activities)}).timeout(_timeout);
    return activitiesFrom(res is List ? res : const []);
  }

  /// Someone else's activities for their public profile (empty before 0039).
  Future<Set<Activity>> ofUser(String uid) async {
    try {
      final row = await _c.from('user_activities').select('activities').eq('id', uid).maybeSingle().timeout(_timeout);
      return activitiesFrom(row?['activities'] ?? const []);
    } on PostgrestException {
      return const {};
    }
  }
}

final activitiesRepositoryProvider = Provider<ActivitiesRepository>((ref) => ActivitiesRepository());

/// The signed-in user's activities; toggled from the Profile buttons.
class MyActivitiesController extends StateNotifier<AsyncValue<Set<Activity>>> {
  MyActivitiesController(this._repo, this._uid) : super(const AsyncValue.loading()) {
    _load();
  }

  final ActivitiesRepository _repo;
  final String? _uid;

  Future<void> _load() async {
    if (_uid == null) {
      state = const AsyncValue.data({});
      return;
    }
    state = await AsyncValue.guard(() => _repo.mine(_uid));
  }

  /// Optimistic: the button changes at once; on a server error the old
  /// set comes back and the error is rethrown for a message.
  Future<void> toggle(Activity a) async {
    final before = state.valueOrNull ?? const <Activity>{};
    final next = toggleActivity(before, a);
    state = AsyncValue.data(next);
    try {
      state = AsyncValue.data(await _repo.save(next));
    } catch (_) {
      state = AsyncValue.data(before);
      rethrow;
    }
  }

  /// Turns one activity on (no-op when it is already on).
  Future<void> enable(Activity a) async {
    if ((state.valueOrNull ?? const {}).contains(a)) return;
    await toggle(a);
  }
}

final myActivitiesProvider = StateNotifierProvider<MyActivitiesController, AsyncValue<Set<Activity>>>((ref) {
  return MyActivitiesController(ref.watch(activitiesRepositoryProvider), ref.watch(currentUserIdProvider));
});

/// Public profile: that user's activities.
final userActivitiesProvider = FutureProvider.autoDispose.family<Set<Activity>, String>((ref, uid) {
  return ref.watch(activitiesRepositoryProvider).ofUser(uid);
});

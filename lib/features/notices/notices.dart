import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/localization/app_strings.dart';
import '../../core/localization/locale_controller.dart';
import '../../core/realtime/live_resync.dart';
import '../../core/router/guest_access.dart';
import '../../core/router/safe_navigation.dart';
import '../../core/startup/startup_steps.dart';
import '../../core/theme/app_theme.dart';
import '../auth/presentation/providers/auth_providers.dart';
import '../jobs/domain/job_applications.dart';
import '../tirpark/domain/tir_park.dart' show kParkManagementOn;
import '../jobs/presentation/job_applications_screen.dart' show jobNoticeTime;

// "Bildirişlər" (owner, 17.11.2026: "mesajdan başqa gələn bütün bildirişlər
// ora gəlsin, neçə bildiriş varsa kənarına yazılsın"; "ürək və bildirişlər
// hər səhifədə sabitlənsin"). One bell left of the heart on every page; its
// red number = my unread notices (the existing notifications table: offers
// on my loads and their answers (0128), İş Mərkəzi (0069), TIR Park
// receipts / worker requests / bookings (0085, 0088, 0128)). Chat messages
// are NOT here — Mesajlar keeps its own count.

/// One notice of the notifications table.
class AppNotice {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime? createdAt;
  const AppNotice({
    required this.id,
    required this.type,
    this.title = '',
    this.body = '',
    this.data = const {},
    this.isRead = false,
    this.createdAt,
  });

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        id: '${j['id']}',
        type: '${j['type'] ?? ''}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        data: Map<String, dynamic>.from((j['data'] as Map?) ?? const {}),
        isRead: j['is_read'] == true,
        createdAt: j['created_at'] == null ? null : DateTime.tryParse('${j['created_at']}'),
      );

  JobNotice get _job => JobNotice(id: id, type: type, title: title, data: data, isRead: isRead, createdAt: createdAt);

  bool get isJob => kJobNoticeTypes.contains(type);

  /// "6000 USD" from the offer's own numbers (no ".00" on whole amounts).
  String get amount {
    final v = num.tryParse('${data['amount'] ?? ''}');
    final cur = '${data['currency'] ?? ''}'.trim();
    if (v == null) return cur;
    final n = v == v.roundToDouble() ? v.round().toString() : v.toString();
    return cur.isEmpty ? n : '$n $cur';
  }

  /// The line in the user's language (the server stores Azerbaijani).
  String text(AppStrings s) => switch (type) {
        'cargo_offer_new' => s.t('ntf_offer_new', {'amount': amount}),
        'cargo_offer_accepted' => s.t('ntf_offer_accepted', {'amount': amount}),
        'cargo_offer_rejected' => s.t('ntf_offer_rejected', {'amount': amount}),
        'tirpark_booking' => s.t('ntf_tp_booking'),
        'tirpark_payment_review' => s.t('ntf_tp_payment'),
        'tirpark_worker_request' => s.t('ntf_tp_worker'),
        'fleet_expense' => s.t('ntf_fleet_expense', {'name': '${data['name'] ?? ''}'}),
        _ when isJob => s.t(_job.textKey),
        _ => title,
      };

  /// The small line under it: the route of the load, the plate / park.
  String detail() => switch (type) {
        'cargo_offer_new' || 'cargo_offer_accepted' || 'cargo_offer_rejected' => body,
        'tirpark_booking' => [data['plate'] ?? data['booking_no'], body].where((v) => '${v ?? ''}'.trim().isNotEmpty).join(' · '),
        'fleet_expense' => [data['truck'], amount].where((v) => '${v ?? ''}'.trim().isNotEmpty).join(' · '),
        'tirpark_payment_review' || 'tirpark_worker_request' => [title.split(': ').skip(1).join(': '), body]
            .where((v) => v.trim().isNotEmpty)
            .join(' · '),
        _ => isJob ? '' : body,
      };

  IconData get icon => switch (type) {
        'cargo_offer_new' => Icons.local_offer_outlined,
        'cargo_offer_accepted' => Icons.check_circle_outline,
        'cargo_offer_rejected' => Icons.highlight_off,
        'tirpark_booking' || 'tirpark_payment_review' || 'tirpark_worker_request' => Icons.local_parking,
        'fleet_expense' => Icons.receipt_long_outlined,
        'job_match_vacancy' => Icons.work_outline,
        'job_match_seeker' => Icons.local_shipping_outlined,
        _ when isJob => Icons.assignment_ind_outlined,
        _ => Icons.notifications_none,
      };

  /// Where a tap goes (null = nowhere to go, it is only read).
  String? get route {
    final cargo = data['cargo_id'];
    if (type.startsWith('cargo_offer') && cargo != null) return '/load/$cargo';
    if (type.startsWith('tirpark_')) return '/tirpark/manage';
    if (type == 'fleet_expense' && data['truck_id'] != null) return '/fleet/t/${data['truck_id']}';
    if (isJob) return _job.route;
    return null;
  }

  /// The route lives inside a bottom-bar tab (TIRPark): it is opened with
  /// go — pushed over the full-screen /notifications page it stayed black
  /// (owner, 18.11.2026).
  bool get opensInTab => (route?.startsWith('/tirpark') ?? false) || (route?.startsWith('/fleet') ?? false);

  /// An "act on it" notice whose matter may be settled later.
  bool get isAction => type == 'tirpark_worker_request' || type == 'tirpark_payment_review' || type == 'fleet_expense';
}

/// The notices without the settled ones (owner, 18.11.2026: "işçi təsdiqi
/// təsdiqlənib, amma yenə də görünür"): a worker request already approved /
/// rejected, a receipt already confirmed / rejected leave the list and the
/// count. Stored rows are never changed.
/// With the park management off (owner, 20.11.2026) its notices (booking,
/// receipt, worker request) are not shown either; the rows stay.
List<AppNotice> visibleNotices(List<AppNotice> list, Set<String> settled, {bool parkManagement = kParkManagementOn}) => [
      for (final n in list)
        if (!settled.contains(n.id) && (parkManagement || !n.type.startsWith('tirpark_'))) n
    ];

/// The newest stand on top; the unread ones are counted on the bell.
int unreadNoticeCount(List<AppNotice> list) => list.where((n) => !n.isRead).length;

/// "99+" over 99.
String noticeBadgeLabel(int n) => n > 99 ? '99+' : '$n';

class NoticesRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  static const _cols = 'id,type,title,body,data,is_read,created_at';

  Stream<List<AppNotice>> watch(String uid) => _c
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', uid)
      .order('created_at', ascending: false)
      .limit(100)
      .map((rows) => [for (final r in rows) AppNotice.fromJson(r)]);

  Future<List<AppNotice>> fetch(String uid) async {
    final rows = await _c
        .from('notifications')
        .select(_cols)
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(100)
        .timeout(const Duration(seconds: 15));
    return [for (final r in rows as List) AppNotice.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  /// Which action notices are settled: the worker is no longer 'pending',
  /// the booking no longer 'payment_review'. Only a definite answer hides a
  /// notice (no answer / no access = it stays).
  Future<Set<String>> settled(List<AppNotice> list) async {
    final out = <String>{};
    final workers = [
      for (final n in list)
        if (n.type == 'tirpark_worker_request' && n.data['park_id'] != null && n.data['worker_id'] != null) n
    ];
    for (final park in {for (final n in workers) '${n.data['park_id']}'}) {
      try {
        final res = await _c.rpc('tir_park_workers_list', params: {'p_park': park}).timeout(const Duration(seconds: 15));
        final status = <String, String>{
          for (final w in ((res as Map)['workers'] as List? ?? const []))
            '${(w as Map)['user_id']}': '${w['status'] ?? ''}',
        };
        for (final n in workers.where((n) => '${n.data['park_id']}' == park)) {
          final st = status['${n.data['worker_id']}'];
          if (st != null && st != 'pending') out.add(n.id);
        }
      } catch (_) {}
    }
    final pays = [
      for (final n in list)
        if (n.type == 'tirpark_payment_review' && n.data['booking_id'] != null) n
    ];
    if (pays.isNotEmpty) {
      try {
        final rows = await _c
            .from('tir_park_bookings')
            .select('id,status')
            .inFilter('id', [for (final n in pays) '${n.data['booking_id']}'])
            .timeout(const Duration(seconds: 15));
        final status = {for (final r in rows as List) '${(r as Map)['id']}': '${r['status'] ?? ''}'};
        for (final n in pays) {
          final st = status['${n.data['booking_id']}'];
          if (st != null && st != 'payment_review') out.add(n.id);
        }
      } catch (_) {}
    }
    // A driver's expense the owner already approved / rejected (0130).
    final exp = [
      for (final n in list)
        if (n.type == 'fleet_expense' && n.data['expense_id'] != null) n
    ];
    if (exp.isNotEmpty) {
      try {
        final rows = await _c
            .from('fleet_expenses')
            .select('id,status,deleted_at')
            .inFilter('id', [for (final n in exp) '${n.data['expense_id']}'])
            .timeout(const Duration(seconds: 15));
        final state = {for (final r in rows as List) '${(r as Map)['id']}': r['deleted_at'] != null ? 'deleted' : '${r['status'] ?? ''}'};
        for (final n in exp) {
          final st = state['${n.data['expense_id']}'];
          if (st != null && st != 'pending') out.add(n.id);
        }
      } catch (_) {}
    }
    return out;
  }

  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _c.from('notifications').update({'is_read': true}).inFilter('id', ids).timeout(const Duration(seconds: 15));
  }
}

final noticesRepositoryProvider = Provider<NoticesRepository>((ref) => NoticesRepository());

/// My notices: realtime + a server read every 20 s (never waits for
/// realtime alone); opened on Yüklər it starts with the messages (step 1).
final myNoticesProvider = StreamProvider<List<AppNotice>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <AppNotice>[]);
  final repo = ref.watch(noticesRepositoryProvider);
  return StartupSteps.after(1, () => liveWithResync(ref, () => repo.watch(uid), () => repo.fetch(uid), every: const Duration(seconds: 20)));
});

/// The settled action notices; asked again only when the set of action
/// notices changes or the Bildirişlər page opens.
final _actionKeyProvider = Provider<String>(
    (ref) => [for (final n in ref.watch(myNoticesProvider).valueOrNull ?? const <AppNotice>[]) if (n.isAction) n.id].join(','));

final settledNoticesProvider = FutureProvider<Set<String>>((ref) async {
  final key = ref.watch(_actionKeyProvider);
  if (key.isEmpty) return const {};
  final list = ref.read(myNoticesProvider).valueOrNull ?? const <AppNotice>[];
  return ref.read(noticesRepositoryProvider).settled([for (final n in list) if (n.isAction) n]);
});

/// What the bell and the page show.
final shownNoticesProvider = Provider<AsyncValue<List<AppNotice>>>((ref) {
  final settled = ref.watch(settledNoticesProvider).valueOrNull ?? const <String>{};
  return ref.watch(myNoticesProvider).whenData((l) => visibleNotices(l, settled));
});

final unreadNoticesProvider = Provider<int>((ref) => unreadNoticeCount(ref.watch(shownNoticesProvider).valueOrNull ?? const []));

/// The bell: left of the heart on every page.
class NoticeBell extends ConsumerWidget {
  /// Draws the round button around the icon (the page's own look).
  final Widget Function(Widget icon, VoidCallback onTap, String tooltip) frame;
  final double size;
  final Color? color;

  /// The page's own texts (else the app's).
  final AppStrings? strings;
  const NoticeBell({super.key, required this.frame, this.size = 22, this.color, this.strings});

  /// A plain [IconButton] (AppBar actions).
  static Widget plain(Widget icon, VoidCallback onTap, String tooltip) =>
      IconButton(key: const ValueKey('notice-bell'), tooltip: tooltip, onPressed: onTap, icon: icon);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppStrings s = strings ?? ref.watch<AppStrings>(stringsProvider);
    final n = ref.watch(unreadNoticesProvider);
    final icon = Badge(
      key: const ValueKey('notice-bell-badge'),
      isLabelVisible: n > 0,
      label: Text(noticeBadgeLabel(n)),
      backgroundColor: AppColors.danger,
      child: Icon(n > 0 ? Icons.notifications : Icons.notifications_none, size: size, color: color ?? AppColors.text),
    );
    return frame(icon, () {
      if (askSignIn(context)) return;
      context.pushOnce('/notifications');
    }, s.t('ntf_title'));
  }
}

/// The page /notifications.
class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  final _marked = <String>{};

  @override
  void initState() {
    super.initState();
    // A worker may have been approved since the last look.
    Future.microtask(() => ref.invalidate(settledNoticesProvider));
  }

  Future<void> _read(List<String> ids) async {
    final todo = ids.where(_marked.add).toList();
    if (todo.isEmpty) return;
    try {
      await ref.read(noticesRepositoryProvider).markRead(todo);
    } catch (_) {
      _marked.removeAll(todo);
    }
    ref.invalidate(myNoticesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final notices = ref.watch(shownNoticesProvider);
    final list = notices.valueOrNull ?? const <AppNotice>[];
    final unread = [for (final n in list) if (!n.isRead && !_marked.contains(n.id)) n.id];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('ntf_title')),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              key: const ValueKey('notice-read-all'),
              onPressed: () => _read(unread),
              child: Text(s.t('ntf_read_all'), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w500)),
            ),
        ],
      ),
      body: notices.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(s.t('home_error_loading'), style: TextStyle(color: AppColors.textSoft))),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none, size: 48, color: AppColors.textSoft),
                  const SizedBox(height: 10),
                  Text(s.t('ntf_empty'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                ]),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
            itemCount: list.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.line),
            itemBuilder: (context, i) {
              final n = list[i];
              final isNew = !n.isRead && !_marked.contains(n.id);
              final detail = n.detail();
              final when = n.createdAt == null ? '' : jobNoticeTime(n.createdAt!.toLocal(), lang);
              return ListTile(
                key: ValueKey('notice-${n.id}'),
                tileColor: isNew ? AppColors.accent.withValues(alpha: 0.06) : null,
                leading: CircleAvatar(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.14),
                  child: Icon(n.icon, color: AppColors.accent),
                ),
                title: Text(n.text(s),
                    style: TextStyle(color: AppColors.text, fontWeight: isNew ? FontWeight.w600 : FontWeight.w400)),
                subtitle: Text([detail, when].where((v) => v.trim().isNotEmpty).join('\n'),
                    style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                isThreeLine: detail.trim().isNotEmpty && when.isNotEmpty,
                trailing: isNew ? Icon(Icons.circle, size: 10, color: AppColors.accent) : null,
                onTap: () {
                  _read([n.id]);
                  final r = n.route;
                  if (r == null) return;
                  if (n.opensInTab) {
                    context.go(r);
                  } else {
                    context.pushOnce(r);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        _ when isJob => s.t(_job.textKey),
        _ => title,
      };

  /// The small line under it: the route of the load, the plate / park.
  String detail() => switch (type) {
        'cargo_offer_new' || 'cargo_offer_accepted' || 'cargo_offer_rejected' => body,
        'tirpark_booking' => [data['plate'] ?? data['booking_no'], body].where((v) => '${v ?? ''}'.trim().isNotEmpty).join(' · '),
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
    if (isJob) return _job.route;
    return null;
  }
}

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

final unreadNoticesProvider = Provider<int>((ref) => unreadNoticeCount(ref.watch(myNoticesProvider).valueOrNull ?? const []));

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
    final notices = ref.watch(myNoticesProvider);
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
                  if (r != null) context.pushOnce(r);
                },
              );
            },
          );
        },
      ),
    );
  }
}

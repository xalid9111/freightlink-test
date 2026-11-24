import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';

/// Users block one another (owner, 24.11.2026, SQL 0135): Mesajlar → the
/// name → the profile → "Blok et" at its end, asked first. The server
/// refuses every private message across a block (both ways); old chats stay.
class UserBlockState {
  final bool iBlocked;
  final bool blockedMe;
  const UserBlockState({this.iBlocked = false, this.blockedMe = false});
  static const none = UserBlockState();

  bool get any => iBlocked || blockedMe;

  factory UserBlockState.fromJson(Object? j) {
    if (j is! Map) return none;
    return UserBlockState(iBlocked: j['i_blocked'] == true, blockedMe: j['blocked_me'] == true);
  }
}

/// The block between me and [userId]; a visitor, my own id or a server
/// without 0135 = no block (nothing changes for them).
final userBlockStateProvider = FutureProvider.autoDispose.family<UserBlockState, String>((ref, userId) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null || me == userId) return UserBlockState.none;
  try {
    final r = await SupabaseConfig.client
        .rpc('user_block_state', params: {'p_user': userId})
        .timeout(const Duration(seconds: 15));
    return UserBlockState.fromJson(r);
  } catch (_) {
    return UserBlockState.none;
  }
});

/// The accounts that blocked me (0136): the Mesajlar list shows them
/// without picture or presence. One read; a server without 0136 = none.
final blockedMeIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return const <String>{};
  try {
    final r = await SupabaseConfig.client.rpc('user_blocked_me_ids').timeout(const Duration(seconds: 15));
    return {for (final id in (r as List? ?? const [])) '$id'};
  } catch (_) {
    return const <String>{};
  }
});

/// "Blok et" / "Blokdan çıxar" — always asked first. True = done.
Future<bool> confirmAndSetUserBlock({
  required BuildContext context,
  required WidgetRef ref,
  required AppStrings s,
  required String userId,
  required bool block,
  String? name,
}) async {
  final who = (name ?? '').trim().isEmpty ? s.t('ub_this_user') : name!.trim();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('user-block-confirm'),
      title: Text(s.t(block ? 'ub_block_q' : 'ub_unblock_q', {'name': who})),
      content: Text(s.t(block ? 'ub_block_body' : 'ub_unblock_body')),
      actions: [
        TextButton(
          key: const ValueKey('user-block-no'),
          onPressed: () => Navigator.pop(c, false),
          child: Text(s.t('pf_sign_out_no')),
        ),
        FilledButton(
          key: const ValueKey('user-block-yes'),
          style: FilledButton.styleFrom(backgroundColor: block ? AppColors.danger : AppColors.accent),
          onPressed: () => Navigator.pop(c, true),
          child: Text(s.t(block ? 'ub_block_yes' : 'ub_unblock_yes')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await SupabaseConfig.client
        .rpc('user_block_set', params: {'p_user': userId, 'p_block': block})
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(s.t('ub_failed'))));
    return false;
  }
  ref.invalidate(userBlockStateProvider(userId));
  messenger.showSnackBar(SnackBar(content: Text(s.t(block ? 'ub_blocked_done' : 'ub_unblocked_done'))));
  return true;
}

/// In place of the message field while a block stands.
class ChatBlockedBar extends ConsumerWidget {
  final String otherId;
  final String? otherName;
  final UserBlockState state;
  const ChatBlockedBar({super.key, required this.otherId, required this.state, this.otherName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('chat-blocked-bar'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.block, size: 18, color: AppColors.danger),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.t(state.iBlocked ? 'ub_chat_i_blocked' : 'ub_chat_blocked_me'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSoft),
              ),
            ),
          ]),
          if (state.iBlocked)
            TextButton(
              key: const ValueKey('chat-unblock'),
              onPressed: () => confirmAndSetUserBlock(
                  context: context, ref: ref, s: s, userId: otherId, block: false, name: otherName),
              child: Text(s.t('ub_unblock')),
            ),
        ]),
      ),
    );
  }
}

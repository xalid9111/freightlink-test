import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../models/group_models.dart';
import '../providers/group_providers.dart';

/// Search-by-name list with check marks — used to pick group members.
/// [exclude] hides people who are already in (e.g. current members).
class PeoplePicker extends ConsumerStatefulWidget {
  final AppStrings strings;
  final Map<String, UserHit> selected;
  final ValueChanged<UserHit> onToggle;
  final Set<String> exclude;
  const PeoplePicker({
    super.key,
    required this.strings,
    required this.selected,
    required this.onToggle,
    this.exclude = const {},
  });

  @override
  ConsumerState<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends ConsumerState<PeoplePicker> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final results = ref.watch(userSearchProvider(_query));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: s.t('chat_search_people_hint'),
            isDense: true,
          ),
        ),
        if (widget.selected.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in widget.selected.values)
                InputChip(
                  label: Text(u.fullName),
                  onDeleted: () => widget.onToggle(u),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (_query.length < 2)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(s.t('chat_search_min_chars'), style: TextStyle(color: AppColors.textSoft)),
          )
        else
          results.when(
            loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            error: (_, __) => Padding(padding: const EdgeInsets.all(16), child: Text(s.t('home_error_loading'))),
            data: (list) {
              final shown = list.where((u) => !widget.exclude.contains(u.id)).toList();
              if (shown.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.t('chat_search_nobody'), style: TextStyle(color: AppColors.textSoft)),
                );
              }
              return Column(
                children: [
                  for (final u in shown)
                    CheckboxListTile(
                      value: widget.selected.containsKey(u.id),
                      onChanged: (_) => widget.onToggle(u),
                      secondary: UserAvatar(imageUrl: u.avatarUrl, initials: u.initials),
                      title: Text(u.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: u.role == null ? null : Text(s.t('role_label_${u.role}')),
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

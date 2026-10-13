import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../models/group_models.dart';
import '../data/group_repository.dart';
import 'providers/group_providers.dart';
import 'widgets/people_picker.dart';

/// "New group": a name + people picked by name search. The creator
/// becomes the group's admin and can add / remove members later.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _nameCtrl = TextEditingController();
  final Map<String, UserHit> _selected = {};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final strings = ref.read(stringsProvider);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = strings.t('chat_group_name_required'));
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = strings.t('chat_group_pick_people'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await ref.read(groupRepositoryProvider).createGroup(name, _selected.keys.toList());
      ref.invalidate(myGroupsProvider);
      if (mounted) context.pushReplacement('/chat-group/${g.id}');
    } catch (_) {
      if (mounted) setState(() => _error = strings.t('chat_group_create_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('chat_new_group'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameCtrl,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: strings.t('chat_group_name'),
                prefixIcon: const Icon(Icons.groups_2_outlined),
              ),
            ),
            const SizedBox(height: 8),
            Text(strings.t('chat_group_members_label'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            PeoplePicker(
              strings: strings,
              selected: _selected,
              onToggle: (u) => setState(() {
                if (_selected.containsKey(u.id)) {
                  _selected.remove(u.id);
                } else {
                  _selected[u.id] = u;
                }
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.check),
        label: Text(strings.t('chat_group_create', {'n': '${_selected.length}'})),
      ),
    );
  }
}

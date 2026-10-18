import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/admin_repository.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';

// ---------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------

DateTime? _parse(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : (v is DateTime ? v.toLocal() : null);

String fmtDateTime(Object? v) {
  final d = _parse(v);
  return d == null ? '—' : DateFormat('dd.MM.yyyy HH:mm').format(d);
}

String fmtDate(Object? v) {
  final d = _parse(v);
  return d == null ? '—' : DateFormat('dd.MM.yyyy').format(d);
}

String shortId(Object? id) {
  final s = id?.toString() ?? '';
  return s.length > 8 ? s.substring(0, 8) : (s.isEmpty ? '—' : s);
}

String txt(Object? v) => (v == null || '$v'.trim().isEmpty) ? '—' : '$v';

const statusLabels = <String, String>{
  // cargo / shipments
  'new': 'Yeni',
  'carrier_found': 'Daşıyıcı tapıldı',
  'agreed': 'Razılaşıldı',
  'loading': 'Yüklənir',
  'in_transit': 'Yolda',
  'delivered': 'Çatdırıldı',
  'completed': 'Tamamlandı',
  'cancelled': 'Ləğv edildi',
  // offers
  'pending': 'Gözləmədə',
  'accepted': 'Qəbul edildi',
  'rejected': 'Rədd edildi',
  'countered': 'Əks-təklif',
  // reports
  'reviewing': 'Baxılır',
  'resolved': 'Həll edildi',
};

const cargoStatuses = ['new', 'carrier_found', 'agreed', 'loading', 'in_transit', 'delivered', 'completed', 'cancelled'];
const offerStatuses = ['pending', 'accepted', 'rejected', 'countered', 'cancelled'];
const reportStatuses = ['new', 'reviewing', 'resolved', 'rejected'];

const roleLabels = <String, String>{
  'cargo_owner': 'Yük sahibi',
  'carrier': 'Daşıyıcı',
  'driver': 'Sürücü',
  'admin': 'Admin',
};

String statusLabel(Object? s) => statusLabels['$s'] ?? txt(s);
String roleLabel(Object? r) => roleLabels['$r'] ?? txt(r);

Color statusColor(Object? s) {
  switch ('$s') {
    case 'new':
    case 'pending':
      return AppColors.blue;
    case 'carrier_found':
    case 'agreed':
    case 'loading':
    case 'in_transit':
    case 'reviewing':
    case 'countered':
      return AppColors.accent;
    case 'delivered':
    case 'completed':
    case 'accepted':
    case 'resolved':
      return AppColors.online;
    case 'cancelled':
    case 'rejected':
      return AppColors.danger;
    default:
      return AppColors.textSoft;
  }
}

// ---------------------------------------------------------------------
// Small building blocks
// ---------------------------------------------------------------------

class AdminChip extends StatelessWidget {
  final String label;
  final Color? _color;
  const AdminChip(this.label, {super.key, Color? color}) : _color = color;
  Color get color => _color ?? AppColors.textSoft;

  factory AdminChip.status(Object? status, {Key? key}) =>
      AdminChip(statusLabel(status), key: key, color: statusColor(status));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final Object? value;
  final IconData icon;
  final Color? _color;
  final VoidCallback? onTap;
  const StatCard({super.key, required this.label, required this.value, required this.icon, Color? color, this.onTap}) : _color = color;
  Color get color => _color ?? AppColors.accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 172,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 10),
              Text(value == null ? '…' : '$value', style: AppFonts.mono(size: 22, color: AppColors.text, letterSpacing: 0)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(color: AppColors.textSoft, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Label / value line in detail views.
class KV extends StatelessWidget {
  final String label;
  final Object? value;
  const KV(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: TextStyle(color: AppColors.textSoft, fontSize: 13))),
          Expanded(
            child: value is Widget ? value as Widget : SelectableText(txt(value), style: TextStyle(color: AppColors.text, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// One list line: title, subtitle, trailing chips. Works on phone and desktop.
class AdminRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final List<Widget> chips;
  final VoidCallback? onTap;
  final bool dimmed;
  const AdminRow({super.key, this.leading, required this.title, this.subtitle, this.chips = const [], this.onTap, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.lineSoft),
            ),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 4, children: chips),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) Icon(Icons.chevron_right, color: AppColors.textSoft, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal filter chips.
class FilterBar extends StatelessWidget {
  final Map<String, String> options; // value -> label
  final String selected;
  final ValueChanged<String> onSelected;
  const FilterBar({super.key, required this.options, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return MouseDragScroll(child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onSelected(e.key),
              ),
            ),
        ],
      ),
    ));
  }
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(text, style: TextStyle(color: AppColors.textSoft))),
      );
}

// ---------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------

Future<bool> confirmAction(BuildContext context, String title, String message, {String ok = 'Bəli', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ləğv et')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res == true;
}

/// Runs an admin action and shows a success / error snackbar. Returns
/// true on success.
Future<bool> runAdmin(BuildContext context, Future<void> Function() action, {String success = 'Yadda saxlanıldı'}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(backgroundColor: AppColors.danger, content: Text(adminErrorText(e))));
    return false;
  }
}

Future<String?> askText(BuildContext context, String title, {String hint = '', String initial = '', bool required = false}) async {
  final ctrl = TextEditingController(text: initial);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ləğv et')),
        FilledButton(
          onPressed: () {
            if (required && ctrl.text.trim().isEmpty) return;
            Navigator.pop(ctx, ctrl.text.trim());
          },
          child: const Text('Təsdiqlə'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return res;
}

Future<String?> pickOne(BuildContext context, String title, Map<String, String> options, {String? current}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final e in options.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, e.key),
            child: Row(
              children: [
                Icon(e.key == current ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 18, color: e.key == current ? AppColors.accent : AppColors.textSoft),
                const SizedBox(width: 10),
                Text(e.value),
              ],
            ),
          ),
      ],
    ),
  );
}

String prettyJson(Object? v) {
  if (v == null) return '—';
  try {
    return const JsonEncoder.withIndent('  ').convert(v);
  } catch (_) {
    return '$v';
  }
}

/// Detail view: a centered dialog on wide screens, a bottom sheet on phones.
Future<void> showDetail(BuildContext context, {required String title, required Widget Function(BuildContext) body}) {
  final wide = MediaQuery.of(context).size.width >= 900;
  Widget frame(BuildContext ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
            child: Row(
              children: [
                Expanded(child: Text(title, style: AppFonts.display(size: 22, color: AppColors.text))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.line),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              child: body(ctx),
            ),
          ),
        ],
      );
  if (wide) {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.hero,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760), child: frame(ctx)),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.hero,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
      child: frame(ctx),
    ),
  );
}

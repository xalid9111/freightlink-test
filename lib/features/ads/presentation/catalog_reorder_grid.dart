import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../repositories/profile_page_repository.dart';
import 'catalog_order.dart';

/// The owner's catalog grid with drag & drop ordering.
///
/// Press and hold a photo: it lifts (slightly larger, with a shadow) and
/// follows the finger in every direction, across rows. The other photos
/// slide to their new places while it moves. Releasing keeps the new order
/// and reports it through [onOrderChanged]; saving is up to the screen.
///
/// The long press wins the gesture over the page scroll, so the page does
/// not move while a photo is dragged (iPhone Safari / PWA included); near
/// the top or bottom edge the page scrolls on purpose to reach far rows.
/// Every tile is its own RepaintBoundary and only positions animate, which
/// keeps it smooth on weak phones.
class CatalogReorderGrid extends StatefulWidget {
  final List<CatalogItem> items;
  final Widget? leading; // fixed first tile (e.g. "add photo")
  final Widget Function(CatalogItem item) tileBuilder;
  final ValueChanged<CatalogItem> onOpen;
  final ValueChanged<List<String>> onOrderChanged;

  const CatalogReorderGrid({
    super.key,
    required this.items,
    required this.tileBuilder,
    required this.onOpen,
    required this.onOrderChanged,
    this.leading,
  });

  @override
  State<CatalogReorderGrid> createState() => _CatalogReorderGridState();
}

class _CatalogReorderGridState extends State<CatalogReorderGrid> {
  static const _move = Duration(milliseconds: 180);
  static const _lift = 1.08;
  static const _edge = 72.0; // auto-scroll zone at the top / bottom
  static const _scrollStep = 9.0;

  final GlobalKey _stackKey = GlobalKey();
  late List<String> _order = [for (final i in widget.items) i.id];
  String? _dragId;
  Offset _finger = Offset.zero; // global position of the finger
  Offset _grab = Offset.zero; // finger offset inside the lifted tile
  Offset _dragLocal = Offset.zero; // finger in grid coordinates (set by gestures, never read from layout in build)
  Timer? _autoScroll;
  GridGeometry _geo = const GridGeometry(width: 0);

  int get _lead => widget.leading == null ? 0 : 1;

  @override
  void didUpdateWidget(CatalogReorderGrid old) {
    super.didUpdateWidget(old);
    final fresh = [for (final i in widget.items) i.id];
    final next = reconcileOrder(_order, fresh);
    if (_dragId != null && !next.contains(_dragId)) {
      // The lifted photo was deleted elsewhere: drop the drag quietly.
      _autoScroll?.cancel();
      _autoScroll = null;
      _dragId = null;
    }
    if (!listEqualsIds(next, _order)) {
      _order = next;
      // A photo was added / deleted while an arrangement was pending.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onOrderChanged(List.of(_order));
      });
    }
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    super.dispose();
  }

  Offset? _toLocal(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  void _startDrag(String id, LongPressStartDetails d) {
    final local = _toLocal(d.globalPosition);
    if (local == null) return;
    HapticFeedback.mediumImpact();
    final slot = _order.indexOf(id) + _lead;
    setState(() {
      _dragId = id;
      _finger = d.globalPosition;
      _dragLocal = local;
      _grab = local - _geo.slotOffset(slot);
    });
  }

  void _dragTo(Offset global) {
    final id = _dragId;
    if (id == null) return;
    _finger = global;
    final local = _toLocal(global);
    if (local == null) return;
    final center = local - _grab + Offset(_geo.tile / 2, _geo.tile / 2);
    final slot = _geo.slotAt(center, first: _lead, last: _lead + _order.length - 1);
    final from = _order.indexOf(id);
    final to = slot - _lead;
    setState(() {
      _dragLocal = local;
      if (from != to) _order = moveItem(_order, from, to);
    });
    _updateAutoScroll(global);
  }

  void _updateAutoScroll(Offset global) {
    final scrollable = Scrollable.maybeOf(context);
    final box = scrollable?.context.findRenderObject();
    if (scrollable == null || box is! RenderBox || !box.hasSize) return;
    final y = box.globalToLocal(global).dy;
    final dir = y < _edge ? -1.0 : (y > box.size.height - _edge ? 1.0 : 0.0);
    if (dir == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final pos = scrollable.position;
      final yNow = box.globalToLocal(_finger).dy;
      final d = yNow < _edge ? -1.0 : (yNow > box.size.height - _edge ? 1.0 : 0.0);
      final target = (pos.pixels + d * _scrollStep).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      if (d == 0 || target == pos.pixels || _dragId == null) {
        _autoScroll?.cancel();
        _autoScroll = null;
        return;
      }
      pos.jumpTo(target);
      _dragTo(_finger); // the grid moved under the finger
    });
  }

  void _endDrag({bool report = true}) {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (_dragId == null) return;
    setState(() => _dragId = null);
    if (report) widget.onOrderChanged(List.of(_order));
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final i in widget.items) i.id: i};
    return LayoutBuilder(
      builder: (context, constraints) {
        _geo = GridGeometry(width: constraints.maxWidth);
        final tile = _geo.tile;
        // The lifted photo is painted last (on top of the others).
        final ids = [..._order.where((id) => id != _dragId), if (_dragId != null) _dragId!];
        return SizedBox(
          key: _stackKey,
          height: _geo.heightFor(_lead + _order.length),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.leading != null)
                Positioned(left: 0, top: 0, width: tile, height: tile, child: widget.leading!),
              for (final id in ids)
                if (byId[id] != null)
                  _tile(byId[id]!, tile, dragged: id == _dragId),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(CatalogItem item, double size, {required bool dragged}) {
    final slot = _geo.slotOffset(_order.indexOf(item.id) + _lead);
    final pos = dragged ? _dragLocal - _grab : slot;
    return AnimatedPositioned(
      key: ValueKey(item.id),
      duration: dragged ? Duration.zero : _move,
      curve: Curves.easeOutCubic,
      left: pos.dx,
      top: pos.dy,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpen(item),
        onLongPressStart: (d) => _startDrag(item.id, d),
        onLongPressMoveUpdate: (d) => _dragTo(d.globalPosition),
        onLongPressEnd: (_) => _endDrag(),
        onLongPressCancel: _endDrag,
        child: AnimatedScale(
          scale: dragged ? _lift : 1,
          duration: const Duration(milliseconds: 120),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: dragged ? const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))] : null,
            ),
            child: RepaintBoundary(child: widget.tileBuilder(item)),
          ),
        ),
      ),
    );
  }
}

bool listEqualsIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

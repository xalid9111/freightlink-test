import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../auth/data/activities_repository.dart';
import '../../auth/domain/activities.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/constants/countries.dart';
import '../../../core/widgets/status_stepper.dart';
import '../../../repositories/shipment_repository.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../../core/router/safe_navigation.dart';

/// Bottom-nav "Shipments" tab — real data via
/// ShipmentRepository.fetchMineWithCargo(). RLS (migration 0002) scopes
/// "mine" to shipments where the signed-in user is the carrier or the
/// cargo owner, so this list is correct for either role automatically.
class ShipmentsScreen extends ConsumerWidget {
  const ShipmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final shipmentsAsync = ref.watch(myShipmentsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('shipments_placeholder_title'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myShipmentsProvider),
        child: shipmentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: Text(strings.t('home_error_loading'))),
          data: (items) {
            if (items.isEmpty) {
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 44, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(strings.t('shipments_empty_title')),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _ShipmentTile(item: items[i], strings: strings),
            );
          },
        ),
      ),
    );
  }
}

class _ShipmentTile extends ConsumerStatefulWidget {
  final ShipmentWithCargo item;
  final AppStrings strings;
  const _ShipmentTile({required this.item, required this.strings});

  @override
  ConsumerState<_ShipmentTile> createState() => _ShipmentTileState();
}

class _ShipmentTileState extends ConsumerState<_ShipmentTile> {
  bool _busy = false;
  String? _error;

  /// The single next step the signed-in user may take on this shipment,
  /// or null if it isn't their turn. Carrier moves the load forward
  /// (→ loading → in_transit → delivered); the cargo owner confirms
  /// receipt (delivered → completed). RLS (shipments_participants_update,
  /// migration 0002) allows either participant to update the row.
  String? _nextStatus({required bool isOwner, required bool isCarrier, required String status}) {
    if (isCarrier) {
      switch (status) {
        case 'new':
        case 'carrier_found':
        case 'agreed':
          return 'loading';
        case 'loading':
          return 'in_transit';
        case 'in_transit':
          return 'delivered';
      }
    }
    if (isOwner && status == 'delivered') return 'completed';
    return null;
  }

  Future<void> _advance(String next) async {
    final strings = widget.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('shipment_action_confirm_title')),
        content: Text(strings.t('shipment_action_confirm_body', {'status': strings.t('shipment_status_$next')})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(strings.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(strings.t('shipment_action_$next'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(shipmentRepositoryProvider);
      await repo.advanceStatus(shipmentId: widget.item.shipment.id, newStatus: next);
      // Only the cargo owner may write the cargo row (RLS
      // cargo_owner_write), so the cargo mirrors the final state when
      // the owner confirms delivery.
      if (next == 'completed' && widget.item.cargo != null) {
        await repo.setCargoStatus(cargoId: widget.item.cargo!.id, status: 'completed');
      }
      ref.invalidate(myShipmentsProvider);
    } catch (_) {
      if (mounted) setState(() => _error = strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final cargo = widget.item.cargo;
    final shipment = widget.item.shipment;
    final statusKey = 'shipment_status_${shipment.status}';
    final statusLabel = strings.t(statusKey);
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final dateFmt = DateFormat('d MMM yyyy', localeCode);

    final user = ref.watch(currentUserProvider);
    final isOwner = user != null && cargo != null && cargo.ownerId == user.id;
    // The other side of a shipment is its carrier — old role "carrier" or
    // any account with the "Daşıyıcı" activity (0039).
    final carrierOn = (ref.watch(myActivitiesProvider).valueOrNull ?? const <Activity>{}).contains(Activity.carrier);
    final isCarrier = user != null && !isOwner && (user.role == 'carrier' || carrierOn);
    final next = _nextStatus(isOwner: isOwner, isCarrier: isCarrier, status: shipment.status);

    return Card(
      child: Column(
        children: [
          ListTile(
            onTap: cargo == null ? null : () => context.pushOnce('/cargo/${cargo.id}'),
            title: cargo == null
                ? Text(shipment.id)
                : Text('${Countries.label(cargo.pickupCountry, localeCode)} → ${Countries.label(cargo.destinationCountry, localeCode)}', style: const TextStyle(fontWeight: FontWeight.w400)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${strings.t('shipment_agreed_price_label')}: ${shipment.agreedPrice.toStringAsFixed(0)} ${shipment.currency}'),
                if (shipment.pickupTime != null) Text(dateFmt.format(shipment.pickupTime!)),
              ],
            ),
            trailing: Chip(label: Text(statusLabel == statusKey ? shipment.status : statusLabel), visualDensity: VisualDensity.compact),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: StatusStepper(status: shipment.status, strings: strings, includeNew: false),
          ),
          if (next != null || _error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  if (next != null)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _advance(next),
                      icon: _busy
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_forward),
                      label: Text(strings.t('shipment_action_$next')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

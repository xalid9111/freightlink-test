import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/presence/online_users.dart';
import '../../../repositories/profile_repository.dart';
import '../../chat/presentation/widgets/call_options.dart';
import '../../../models/cargo_model.dart';
import '../../../models/offer_model.dart';
import '../../../repositories/credits_repository.dart';
import '../../../repositories/offer_repository.dart';
import '../../../repositories/shipment_repository.dart';
import '../../../services/navigation_service.dart';
import '../../auth/data/activities_repository.dart';
import '../../auth/domain/activities.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../carrier/presentation/providers/carrier_providers.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import 'providers/cargo_media_providers.dart';
import 'providers/cargo_providers.dart';
import '../domain/truck_types.dart';
import 'widgets/cargo_picture.dart';
import 'widgets/cargo_picture_field.dart';
import '../domain/cargo_pictures.dart';
import 'widgets/cargo_route_map.dart';
import '../../../core/router/safe_navigation.dart';

class CargoDetailScreen extends ConsumerWidget {
  final String cargoId;
  const CargoDetailScreen({super.key, required this.cargoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final cargoAsync = ref.watch(cargoDetailProvider(cargoId));

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('detail_title')), actions: [
        // "Seçilmiş yüklər" (0058).
        CargoFavoriteHeart(cargoId: cargoId, size: 24),
        const SizedBox(width: 8),
      ]),
      body: cargoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(strings.t('detail_not_found'))),
        data: (cargo) => _DetailBody(cargo: cargo),
      ),
    );
  }
}

class _RouteEnd extends StatelessWidget {
  final String value;
  final String city;
  final String localeCode;
  final bool alignEnd;
  const _RouteEnd({required this.value, required this.city, required this.localeCode, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    final c = Countries.find(value);
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        if (c != null) Text(c.flag, style: const TextStyle(fontSize: 26, height: 1)),
        const SizedBox(height: 4),
        Text(
          (c?.name(localeCode) ?? value).toUpperCase(),
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: AppFonts.display(size: 24, color: AppColors.text, height: 1.05),
        ),
        Text(Cities.label(city, localeCode), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
      ],
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final CargoModel cargo;
  const _DetailBody({required this.cargo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final user = ref.watch(currentUserProvider);
    final isOwner = user != null && user.id == cargo.ownerId;
    final localeCode = ref.watch(currentLocaleProvider).languageCode;
    final dateFmt = DateFormat('d MMM yyyy', localeCode);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Owner tools first, so editing is easy to find.
        if (isOwner) ...[
          _OwnerActions(cargo: cargo, strings: strings),
          const SizedBox(height: 12),
          // No picture yet: add one straight from here (owner, 23.10.2026).
          if ((cargo.imageUrl ?? '').isEmpty) ...[
            OutlinedButton.icon(
              key: const ValueKey('cargo-add-picture'),
              onPressed: () => _addPicture(context, ref, cargo, strings),
              icon: Icon(Icons.add_photo_alternate_outlined, color: AppColors.accent),
              label: Text(strings.t('cargo_pic_add')),
            ),
            const SizedBox(height: 12),
          ],
        ],
        // Card picture (0058), only when the load has one.
        if ((cargo.imageUrl ?? '').isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CargoPicture(imageUrl: cargo.imageUrl, truckType: cargo.truckType, groupage: cargo.groupage),
            ),
          ),
          if (user?.role == AppConstants.roleAdmin)
            Align(
              alignment: Alignment.centerRight,
              child: _AdminClearPicture(cargo: cargo, strings: strings),
            ),
          const SizedBox(height: 12),
        ],
        // Route + price card — same visual language as the marketplace card.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _RouteEnd(value: cargo.pickupCountry, city: cargo.pickupCity, localeCode: localeCode, alignEnd: false)),
                    Column(
                      children: [
                        if (cargo.distanceKm != null)
                          Text('${cargo.distanceKm!.toStringAsFixed(0)} km', style: AppFonts.mono(color: AppColors.route)),
                        const SizedBox(height: 4),
                        Icon(Icons.arrow_forward, color: AppColors.route, size: 22),
                      ],
                    ),
                    Expanded(child: _RouteEnd(value: cargo.destinationCountry, city: cargo.destinationCity, localeCode: localeCode, alignEnd: true)),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(cargo.offeredPrice.toStringAsFixed(0), style: AppFonts.display(size: 36, color: AppColors.text, height: 1)),
                    const SizedBox(width: 6),
                    Text(cargo.currency, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                    const Spacer(),
                    Text(strings.t('detail_offered_price'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(strings.t('detail_weight_label'), '${cargo.weightKg.toStringAsFixed(0)} kg'),
                if (cargo.volumeM3 != null) _InfoRow(strings.t('detail_volume_label'), '${cargo.volumeM3} m³'),
                if (cargo.palletCount != null) _InfoRow(strings.t('detail_pallets_label'), '${cargo.palletCount}'),
                if (cargo.truckType != null) _InfoRow(strings.t('detail_truck_type_label'), truckTypeLabel(strings, cargo.truckType!)),
                _InfoRow(strings.t('detail_pickup_date_label'), dateFmt.format(cargo.pickupDate)),
                if (cargo.deliveryDeadline != null)
                  _InfoRow(strings.t('detail_delivery_deadline_label'), dateFmt.format(cargo.deliveryDeadline!)),
                _InfoRow(strings.t('detail_status_label'), _statusLabel(strings, cargo.status)),
                if (cargo.description != null && cargo.description!.isNotEmpty)
                  _InfoRow(strings.t('detail_description_label'), cargo.description!),
              ],
            ),
          ),
        ),
        // Payment terms and free waiting time (0046); only what the owner filled.
        if (cargo.hasTerms) ...[
          const SizedBox(height: 16),
          Card(
            key: const ValueKey('cargo-terms'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.t('cargo_terms_title'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  for (final (key, amount) in cargo.paymentTerms)
                    // Only the advance has an amount; the others are just ticked.
                    _InfoRow(strings.t(key), amount == null ? '✓' : '${_amount(amount)} ${cargo.currency}'),
                  if (cargo.freeWaitHours != null)
                    _InfoRow(strings.t('cargo_wait_short'), strings.t('cargo_wait_hours', {'n': '${cargo.freeWaitHours}'})),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        // Route map (A loading → B unloading) with road distance; the
        // owner can fine-tune the points. (The delivery-stage stepper
        // lives on the Shipments tab.)
        CargoRouteMap(cargo: cargo, strings: strings, isOwner: isOwner),
        const SizedBox(height: 16),
        _NavigationButtons(cargo: cargo, strings: strings),

        if (!isOwner) ...[
          const SizedBox(height: 16),
          _OwnerContactSection(cargo: cargo, strings: strings),
          const SizedBox(height: 16),
          _MessageOwnerButton(cargo: cargo, strings: strings),
          const SizedBox(height: 16),
          _CarrierOfferSection(cargo: cargo, strings: strings),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: _ReportCargoButton(cargo: cargo, strings: strings)),
        ],

        if (isOwner) ...[
          const SizedBox(height: 16),
          _OffersReceivedSection(cargo: cargo, strings: strings),
        ],
      ],
    );
  }

  static String _amount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  String _statusLabel(AppStrings strings, String status) {
    // cargo.status uses the same vocabulary as shipments
    // (new/carrier_found/.../completed/cancelled — see migration
    // 0001), hence shipment_status_* keys here, not offer_status_*
    // (which is a different, offer-specific vocabulary).
    final key = 'shipment_status_$status';
    final label = strings.t(key);
    return label == key ? status : label;
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// External maps hand-off (brief §10) — the one real, wired use of
/// NavigationService. Only shown when the cargo actually has
/// coordinates (optional fields on the create form); otherwise an
/// honest "not available" note instead of a dead button.
class _NavigationButtons extends ConsumerWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _NavigationButtons({required this.cargo, required this.strings});

  Future<void> _showAppPicker(BuildContext context, WidgetRef ref, {required double lat, required double lng, required String label}) async {
    final apps = navigationService.availableApps();
    final chosen = await showModalBottomSheet<NavApp>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(strings.t('nav_sheet_title'), style: Theme.of(context).textTheme.titleMedium)),
            for (final app in apps)
              ListTile(
                title: Text(_appLabel(app)),
                onTap: () => Navigator.of(context).pop(app),
              ),
            ListTile(title: Text(strings.t('nav_sheet_cancel')), onTap: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await navigationService.startNavigation(chosen, lat: lat, lng: lng, label: label);
  }

  String _appLabel(NavApp app) => switch (app) {
        NavApp.googleMaps => strings.t('nav_sheet_google'),
        NavApp.appleMaps => strings.t('nav_sheet_apple'),
        NavApp.waze => strings.t('nav_sheet_waze'),
        NavApp.sygic => 'Sygic',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPickup = cargo.pickupLatitude != null && cargo.pickupLongitude != null;
    final hasDest = cargo.destinationLatitude != null && cargo.destinationLongitude != null;
    // No exact points yet: the route map above already shows the
    // approximate (city) locations, so no extra note here.
    if (!hasPickup && !hasDest) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      children: [
        if (hasPickup)
          OutlinedButton.icon(
            icon: const Icon(Icons.navigation_outlined),
            label: Text('${strings.t('detail_start_navigation')} — ${cargo.pickupCity}'),
            onPressed: () => _showAppPicker(context, ref, lat: cargo.pickupLatitude!, lng: cargo.pickupLongitude!, label: cargo.pickupCity),
          ),
        if (hasDest)
          OutlinedButton.icon(
            icon: const Icon(Icons.navigation_outlined),
            label: Text('${strings.t('detail_start_navigation')} — ${cargo.destinationCity}'),
            onPressed: () => _showAppPicker(context, ref, lat: cargo.destinationLatitude!, lng: cargo.destinationLongitude!, label: cargo.destinationCity),
          ),
      ],
    );
  }
}

/// The cargo owner's contact details, shown FREE to anyone viewing a
/// cargo they don't own. Credits/payments are switched off for the
/// launch period (product decision): the old unlock_contact() credit
/// gate in the database (migration 0006) is left untouched and simply
/// not used. The data comes from the server function get_cargo_contact()
/// (migration 0019), which releases the poster's contact only for a load
/// the viewer can see — see CreditsRepository.fetchCargoContact.
class _OwnerContactSection extends ConsumerWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _OwnerContactSection({required this.cargo, required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactAsync = ref.watch(ownerContactProvider((cargoId: cargo.id, ownerId: cargo.ownerId)));
    final profile = ref.watch(publicProfileProvider(cargo.ownerId)).valueOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.t('detail_owner_contact_title'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            contactAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, __) => Text(strings.t('error_generic')),
              data: (contact) {
                final name = contact['full_name'];
                final phone = contact['phone'];
                final email = contact['email'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (name != null && name.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        // Tap the photo / name → the owner's profile page.
                        child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.pushOnce('/user/${cargo.ownerId}'),
                        child: Row(
                          children: [
                            UserAvatar(
                              imageUrl: profile?.avatarUrl,
                              initials: profile?.initials ?? name[0].toUpperCase(),
                              radius: 20,
                              online: ref.watch(isUserOnlineProvider(cargo.ownerId)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      ),
                                      if (profile?.isVerified == true) ...[
                                        const SizedBox(width: 4),
                                        const VerifiedTick(),
                                      ],
                                    ],
                                  ),
                                  if (profile?.isEarlyMember == true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: EarlyMemberChip(label: strings.t('badge_early_member')),
                                    ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: AppColors.textSoft),
                          ],
                        ),
                        ),
                      ),
                    if (phone != null && phone.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => showCallOptions(context, strings, phone),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Row(
                            children: [
                              Icon(Icons.phone_outlined, size: 20, color: AppColors.accent),
                              const SizedBox(width: 10),
                              Expanded(child: Text(phone, style: TextStyle(fontSize: 15, color: AppColors.text))),
                            ],
                          ),
                        ),
                      ),
                    if (email != null && email.isNotEmpty)
                      _ContactLine(icon: Icons.mail_outline, value: email, uri: Uri(scheme: 'mailto', path: email)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One tappable contact line (opens the phone dialer / mail app).
class _ContactLine extends StatelessWidget {
  final IconData icon;
  final String value;
  final Uri uri;
  const _ContactLine({required this.icon, required this.value, required this.uri});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => launchUrl(uri),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(value, style: TextStyle(fontSize: 15, color: AppColors.text))),
          ],
        ),
      ),
    );
  }
}

/// Poster contact details for one load (cached; re-fetched on account
/// switch like every other user-scoped provider). Keyed by the load, not
/// the owner: the server releases contact data per visible load (0019).
final ownerContactProvider = FutureProvider.family<Map<String, String?>, ({String cargoId, String ownerId})>((ref, key) {
  ref.watch(currentUserIdProvider);
  return ref.watch(creditsRepositoryProvider).fetchCargoContact(key.cargoId, key.ownerId);
});

/// Opens (or creates, exactly once) the chat between the signed-in
/// carrier and THIS cargo's owner. The server derives the owner from the
/// cargo (RPC get_or_create_conversation, migration 0011), so a chat can
/// never be opened with the wrong person. Busy-guarded against double
/// taps; errors are shown, never swallowed. Free — no credit/contact
/// unlock check (monetization is off).
class _MessageOwnerButton extends ConsumerStatefulWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _MessageOwnerButton({required this.cargo, required this.strings});

  @override
  ConsumerState<_MessageOwnerButton> createState() => _MessageOwnerButtonState();
}

class _MessageOwnerButtonState extends ConsumerState<_MessageOwnerButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final conversation = await ref.read(messageRepositoryProvider).getOrCreateConversation(
            cargoId: widget.cargo.id,
            cargoOwnerId: widget.cargo.ownerId,
            carrierUserId: user.id,
          );
      ref.invalidate(conversationByIdProvider(conversation.id));
      ref.invalidate(myConversationsProvider);
      if (mounted) context.pushOnce('/chat/${conversation.id}');
    } catch (e) {
      if (mounted) {
        final key = e.toString().contains('only_carriers_can_contact') ? 'chat_only_carriers' : 'chat_open_failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.t(key))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chat_bubble_outline),
      label: Text(widget.strings.t('detail_message_button')),
      onPressed: _busy ? null : _open,
    );
  }
}

/// Carrier's own offer on this cargo — submit / update / withdraw.
/// Enforces the one-active-pending-offer rule (migration 0004) by
/// finding the current pending offer (if any) and showing "update /
/// withdraw" instead of a second submit form.
class _CarrierOfferSection extends ConsumerStatefulWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _CarrierOfferSection({required this.cargo, required this.strings});

  @override
  ConsumerState<_CarrierOfferSection> createState() => _CarrierOfferSectionState();
}

class _CarrierOfferSectionState extends ConsumerState<_CarrierOfferSection> {
  final _priceCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitNew(String carrierId) async {
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null) {
      setState(() => _error = widget.strings.t('field_invalid_number'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(offerRepositoryProvider).submit(OfferModel(
            id: '',
            cargoId: widget.cargo.id,
            carrierId: carrierId,
            offeredPrice: price,
            currency: widget.cargo.currency,
            message: _messageCtrl.text.trim().isEmpty ? null : _messageCtrl.text.trim(),
          ));
      _invalidateOffers(carrierId);
    } on AppException catch (e) {
      setState(() => _error = widget.strings.error(e.code));
    } catch (_) {
      setState(() => _error = widget.strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update(String offerId, String carrierId) async {
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null) {
      setState(() => _error = widget.strings.t('field_invalid_number'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(offerRepositoryProvider).updatePendingOffer(
            offerId: offerId,
            newOfferedPrice: price,
            newMessage: _messageCtrl.text.trim().isEmpty ? null : _messageCtrl.text.trim(),
          );
      _invalidateOffers(carrierId);
    } on AppException catch (e) {
      setState(() => _error = widget.strings.error(e.code));
    } catch (_) {
      setState(() => _error = widget.strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(String offerId, String carrierId) async {
    setState(() => _busy = true);
    try {
      await ref.read(offerRepositoryProvider).withdraw(offerId);
      _invalidateOffers(carrierId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidateOffers(String carrierId) {
    ref.invalidate(myOfferHistoryProvider(CarrierCargoKey(widget.cargo.id, carrierId)));
    ref.invalidate(offersForCargoProvider(widget.cargo.id));
  }

  @override
  Widget build(BuildContext context) {
    final carrierIdAsync = ref.watch(myCarrierIdProvider);
    // "Daşıyıcı" in Profil (0039) turns the offer form on; any account can.
    final activities = ref.watch(myActivitiesProvider);
    final carrierOn = (activities.valueOrNull ?? const <Activity>{}).contains(Activity.carrier);
    return carrierIdAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (carrierId) {
        if (!activities.hasValue) return const SizedBox.shrink();
        // Not a carrier (yet): one tap turns "Daşıyıcı" on.
        if (carrierId == null) return _BecomeCarrier(strings: widget.strings);
        if (!carrierOn) {
          // Turned off: earlier offers on this load stay visible.
          final past = ref.watch(myOfferHistoryProvider(CarrierCargoKey(widget.cargo.id, carrierId))).valueOrNull ?? const [];
          if (past.isEmpty) return _BecomeCarrier(strings: widget.strings);
        }
        final historyAsync = ref.watch(myOfferHistoryProvider(CarrierCargoKey(widget.cargo.id, carrierId)));

        return historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
          data: (history) {
            final pending = history.where((o) => o.status == 'pending').toList();
            final hasPending = pending.isNotEmpty;
            if (hasPending && _priceCtrl.text.isEmpty) {
              _priceCtrl.text = pending.first.offeredPrice.toStringAsFixed(0);
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.strings.t('detail_your_offer_title'), style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: widget.strings.t('detail_offer_price_label'), border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _messageCtrl,
                      decoration: InputDecoration(labelText: widget.strings.t('detail_offer_message_label'), border: const OutlineInputBorder()),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => hasPending ? _update(pending.first.id, carrierId) : _submitNew(carrierId),
                          child: Text(hasPending ? widget.strings.t('detail_update_offer') : widget.strings.t('detail_submit_offer')),
                        ),
                        if (hasPending)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _withdraw(pending.first.id, carrierId),
                            child: Text(widget.strings.t('detail_withdraw_offer')),
                          ),
                      ],
                    ),
                    if (history.isNotEmpty) ...[
                      const Divider(height: 24),
                      ...history.map((o) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${o.offeredPrice.toStringAsFixed(0)} ${o.currency} — ${widget.strings.t('offer_status_${o.status}')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Cargo owner's view: every offer received, with accept/reject.
/// Accepting an offer also creates the shipment (ShipmentRepository) —
/// the acceptance test's "owner responds" step needs the offer to
/// actually move the workflow forward, not just flip a status flag.
/// "Təklif vermək üçün Daşıyıcı fəaliyyətini aktiv edin" — one tap turns
/// it on (Profil, 0039) and the offer form appears.
class _BecomeCarrier extends ConsumerStatefulWidget {
  final AppStrings strings;
  const _BecomeCarrier({required this.strings});

  @override
  ConsumerState<_BecomeCarrier> createState() => _BecomeCarrierState();
}

class _BecomeCarrierState extends ConsumerState<_BecomeCarrier> {
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      await ref.read(myActivitiesProvider.notifier).enable(Activity.carrier);
      ref.invalidate(myCarrierIdProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.t('act_save_failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.local_shipping_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t('act_offer_need_carrier'), style: const TextStyle(fontSize: 13.5))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _enable,
              child: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(s.t('act_enable')),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersReceivedSection extends ConsumerStatefulWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _OffersReceivedSection({required this.cargo, required this.strings});

  @override
  ConsumerState<_OffersReceivedSection> createState() => _OffersReceivedSectionState();
}

class _OffersReceivedSectionState extends ConsumerState<_OffersReceivedSection> {
  bool _openingChat = false;

  /// Owner → carrier chat from an offer (owner can start the conversation).
  Future<void> _messageCarrier(String carrierId) async {
    setState(() => _openingChat = true);
    try {
      final conv = await ref
          .read(messageRepositoryProvider)
          .openConversationAsOwner(cargoId: widget.cargo.id, carrierId: carrierId);
      ref.invalidate(conversationByIdProvider(conv.id));
      ref.invalidate(myConversationsProvider);
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.strings.t('chat_open_failed'))));
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  final Set<String> _busyOfferIds = {};
  String? _error;

  Future<void> _respond(OfferModel offer, String status) async {
    setState(() {
      _busyOfferIds.add(offer.id);
      _error = null;
    });
    try {
      await ref.read(offerRepositoryProvider).respond(offerId: offer.id, status: status);
      if (status == 'accepted') {
        await ref.read(shipmentRepositoryProvider).createFromAcceptedOffer(
              cargoId: widget.cargo.id,
              carrierId: offer.carrierId,
              acceptedOfferId: offer.id,
              agreedPrice: offer.offeredPrice,
            );
        // Close the deal on this cargo: competing pending offers are
        // rejected and the cargo leaves the open marketplace
        // ('agreed' — the marketplace lists status 'new' only).
        await ref.read(offerRepositoryProvider).rejectOtherPending(
              cargoId: widget.cargo.id,
              acceptedOfferId: offer.id,
            );
        await ref.read(shipmentRepositoryProvider).setCargoStatus(cargoId: widget.cargo.id, status: 'agreed');
        ref.invalidate(marketplaceProvider);
        ref.invalidate(myShipmentsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.strings.t('detail_offer_accepted_note'))),
          );
        }
      }
      ref.invalidate(offersForCargoProvider(widget.cargo.id));
      ref.invalidate(cargoDetailProvider(widget.cargo.id));
    } on AppException catch (e) {
      setState(() => _error = widget.strings.error(e.code));
    } catch (_) {
      setState(() => _error = widget.strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _busyOfferIds.remove(offer.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final offersAsync = ref.watch(offersForCargoProvider(widget.cargo.id));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.strings.t('detail_offers_received_title'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            offersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
              data: (offers) {
                if (offers.isEmpty) return Text(widget.strings.t('detail_no_offers_yet'));
                return Column(
                  children: offers.map((o) {
                    final busy = _busyOfferIds.contains(o.id);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${o.offeredPrice.toStringAsFixed(0)} ${o.currency}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(widget.strings.t('offer_status_${o.status}'), style: Theme.of(context).textTheme.bodySmall),
                                if (o.message != null) Text(o.message!, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: widget.strings.t('detail_message_carrier'),
                            icon: Icon(Icons.chat_bubble_outline, color: AppColors.accent),
                            onPressed: _openingChat ? null : () => _messageCarrier(o.carrierId),
                          ),
                          if (o.status == 'pending') ...[
                            IconButton(
                              tooltip: widget.strings.t('detail_accept_offer'),
                              icon: const Icon(Icons.check_circle_outline, color: Colors.teal),
                              onPressed: busy ? null : () => _respond(o, 'accepted'),
                            ),
                            IconButton(
                              tooltip: widget.strings.t('detail_reject_offer'),
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: busy ? null : () => _respond(o, 'rejected'),
                            ),
                          ],
                          if (busy) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


/// Owner tools on their own open load: edit it (same quick form) or
/// delete the listing (migration 0016: chats are kept as direct chats;
/// refused once a shipment exists).
class _OwnerActions extends ConsumerStatefulWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _OwnerActions({required this.cargo, required this.strings});

  @override
  ConsumerState<_OwnerActions> createState() => _OwnerActionsState();
}

class _OwnerActionsState extends ConsumerState<_OwnerActions> {
  bool _busy = false;

  Future<void> _delete() async {
    final s = widget.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('cargo_delete_title')),
        content: Text(s.t('cargo_delete_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.t('common_cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.t('cargo_delete')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Server function (migration 0016): owner only, refused once a
      // shipment exists; chats about the load are kept.
      await SupabaseConfig.client.rpc('delete_my_cargo', params: {'p_id': widget.cargo.id}).timeout(const Duration(seconds: 20));
      ref.invalidate(marketplaceProvider);
      ref.invalidate(myCargoProvider);
      messenger.showSnackBar(SnackBar(content: Text(s.t('cargo_deleted'))));
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/cargo');
        }
      }
    } catch (e) {
      final key = e.toString().contains('cargo_has_shipment') ? 'cargo_delete_has_shipment' : 'error_generic';
      messenger.showSnackBar(SnackBar(content: Text(s.t(key))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return Row(
      children: [
        if (const ['new', 'carrier_found', 'agreed'].contains(widget.cargo.status)) ...[
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => context.pushOnce('/cargo-edit/${widget.cargo.id}'),
              icon: const Icon(Icons.edit_outlined),
              label: Text(s.t('cargo_edit')),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.danger)),
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(s.t('cargo_delete')),
          ),
        ),
      ],
    );
  }
}

/// "Report" link for loads that look fake or abusive. Inserts a row into
/// public.reports (migration 0012, RLS: only your own report, status
/// 'new'); admins handle it in the Admin Panel.
class _ReportCargoButton extends StatelessWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _ReportCargoButton({required this.cargo, required this.strings});

  Future<void> _open(BuildContext context) async {
    const reasons = ['fake', 'spam', 'fraud', 'other'];
    var reason = 'fake';
    final details = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(strings.t('report_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in reasons)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(r == reason ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: r == reason ? AppColors.accent : AppColors.textSoft),
                    title: Text(strings.t('report_reason_$r')),
                    onTap: () => setState(() => reason = r),
                  ),
                TextField(
                  controller: details,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(hintText: strings.t('report_details_hint')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.t('common_cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(strings.t('report_send'))),
          ],
        ),
      ),
    );
    final text = details.text.trim();
    details.dispose();
    if (send != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseConfig.client.from('reports').insert({
        'target_type': 'cargo',
        'target_id': cargo.id,
        'reason': strings.t('report_reason_$reason'),
        'details': text.isEmpty ? null : text,
      });
      messenger.showSnackBar(SnackBar(content: Text(strings.t('report_sent'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(strings.t('report_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _open(context),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSoft),
      icon: const Icon(Icons.flag_outlined, size: 18),
      label: Text(strings.t('report_button')),
    );
  }
}

/// Admin: take an unsuitable picture off the load (checked on the server,
/// logged; nothing else on the load changes).
class _AdminClearPicture extends ConsumerWidget {
  final CargoModel cargo;
  final AppStrings strings;
  const _AdminClearPicture({required this.cargo, required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      key: const ValueKey('admin-clear-cargo-picture'),
      icon: Icon(Icons.hide_image_outlined, size: 18, color: AppColors.danger),
      label: Text(strings.t('cargo_pic_admin_remove'), style: TextStyle(color: AppColors.danger)),
      onPressed: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(strings.t('cargo_pic_admin_remove_q')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.t('common_cancel'))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(strings.t('cargo_pic_admin_remove')),
              ),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await ref.read(cargoMediaRepositoryProvider).adminClearImage(cargo.id);
          ref.invalidate(cargoDetailProvider(cargo.id));
          ref.invalidate(marketplaceProvider);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('error_generic'))));
          }
        }
      },
    );
  }
}

/// "Şəkil əlavə et" on my own load: the template pictures of its load type
/// or my own photo; only the picture is saved.
Future<void> _addPicture(BuildContext context, WidgetRef ref, CargoModel cargo, AppStrings strings) async {
  final media = ref.read(cargoMediaRepositoryProvider);
  final uploaded = <String>[];
  String? picked;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(strings.t('cargo_pic_label'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 12),
          CargoPictureField(
            strings: strings,
            category: cargoPictureCategory(truckType: cargo.truckType, groupage: cargo.groupage),
            value: picked,
            onChanged: (url) => setState(() => picked = url),
            onUploaded: uploaded.add,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('cargo-add-picture-save'),
            onPressed: picked == null ? null : () => Navigator.pop(ctx, true),
            child: Text(strings.t('quick_save')),
          ),
        ]),
      ),
    ),
  );
  // Photos uploaded but not kept are deleted again.
  for (final url in uploaded) {
    if (ok != true || url != picked) media.removeOwn(url);
  }
  if (ok != true || picked == null) return;
  try {
    await media.setCargoImage(cargo.id, picked);
    ref.invalidate(cargoDetailProvider(cargo.id));
    ref.invalidate(marketplaceProvider);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('cargo_pic_upload_failed'))));
    }
  }
}

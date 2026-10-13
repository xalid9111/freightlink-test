/// App-wide constants that are not secrets and not environment-specific.
class AppConstants {
  AppConstants._();

  static const String appName = 'FreightLink';

  // User roles — mirrors the `role` check constraint on public.users.
  static const String roleCargoOwner = 'cargo_owner';
  static const String roleCarrier = 'carrier';
  static const String roleDriver = 'driver';
  static const String roleAdmin = 'admin';

  // Shipment status flow — mirrors public.shipments.current_status.
  // 'cancelled' is included as a valid terminal state (any status can
  // transition to it), not as a step in the normal flow order.
  static const List<String> shipmentStatusFlow = [
    'new',
    'carrier_found',
    'agreed',
    'loading',
    'in_transit',
    'delivered',
    'completed',
    'cancelled',
  ];

  static const List<String> supportedLocales = ['az', 'tr', 'ru', 'en', 'ka', 'zh'];
  static const String defaultLocale = 'az';
}

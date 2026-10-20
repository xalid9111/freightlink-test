import '../../../core/localization/app_strings.dart';

/// Truck types offered on the load form (owner, 21.10.2026: Tent, Ref,
/// Samosval, Konteyner first; any other type can be typed under "Digər").
/// Stored as these codes in public.cargo.truck_type; a typed type is
/// stored as its text.
const kTruckTypes = ['tent', 'ref', 'dump', 'container', 'open', 'tanker'];

/// Label for a stored truck type: the translated name for a known code,
/// otherwise the text exactly as the owner typed it.
String truckTypeLabel(AppStrings s, String value) {
  final key = 'truck_${value.trim().toLowerCase()}';
  final label = s.t(key);
  return label == key ? value : label;
}

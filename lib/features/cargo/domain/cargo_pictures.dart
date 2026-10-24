/// Load pictures (owner, 22.10.2026, migration 0058).
///
/// * A picture is not required. The load owner picks one of the admin's
///   templates for the load type or uploads his own photo, and can change
///   or remove it later.
/// * Templates are kept per load type (the 7 choices of the Loads page);
///   at most [kMaxCargoTemplates] per type.
/// * A load without a picture shows its load type icon — never a guessed
///   picture.
library;

import 'cargo_categories.dart';

const kMaxCargoTemplates = 10;

/// Storage bucket of load pictures (public read, 5 MB).
const kCargoPhotoBucket = 'cargo-photos';

/// Template group of a load: QRUPAJ first (a load category on its own),
/// otherwise its truck type when it is one of the 7 choices; null = no
/// templates (a typed "Digər" truck type) — own photo only.
String? cargoPictureCategory({String? truckType, bool groupage = false}) {
  if (groupage) return 'groupage';
  final t = (truckType ?? '').trim().toLowerCase();
  return kCategoryChoices.contains(t) ? t : null;
}

/// Storage path of a new picture: own folder = user id (checked by the
/// bucket policy); admin templates go under "templates/<type>/".
String cargoPhotoPath({required String userId, required String ext, String? templateCategory, required int stamp}) {
  final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
  return templateCategory == null ? '$userId/$stamp.$e' : 'templates/$templateCategory/$stamp.$e';
}

/// The public address of an uploaded picture with any doubled "/" in its
/// path removed. A server address saved with a trailing "/" gives
/// ".../co//storage/v1/...", which the database check (0058 / 0060:
/// "https://<host>/storage/v1/object/public/cargo-photos/...") refuses —
/// the load then could not keep its picture.
String cleanStorageUrl(String url) {
  final i = url.indexOf('://');
  if (i < 0) return url;
  final head = url.substring(0, i + 3);
  return head + url.substring(i + 3).replaceAll(RegExp(r'/{2,}'), '/');
}

/// Only an own-folder picture is deleted from storage when a load drops
/// it; templates are shared by many loads and stay.
bool isOwnCargoPhoto(String url, String userId) => url.contains('/$kCargoPhotoBucket/$userId/');

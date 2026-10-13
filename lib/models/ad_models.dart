/// Advertising (migration 0015).
class AdPackage {
  final String id;
  final String name;
  final int days;
  final double price;
  final String currency;
  final bool isActive;
  final int sort;

  const AdPackage({
    required this.id,
    required this.name,
    required this.days,
    required this.price,
    required this.currency,
    required this.isActive,
    required this.sort,
  });

  factory AdPackage.fromJson(Map<String, dynamic> j) => AdPackage(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        days: (j['days'] as num?)?.toInt() ?? 0,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currency: (j['currency'] as String?) ?? 'USD',
        isActive: j['is_active'] == true,
        sort: (j['sort'] as num?)?.toInt() ?? 0,
      );
}

class AdOrder {
  final String id;
  final String advertiserId;
  final String? packageId;
  final String packageName;
  final int days;
  final double price;
  final String currency;
  /// unpaid | submitted | paid | refunded
  final String paymentStatus;
  /// pending_payment | awaiting_approval | approved | rejected | active | expired | cancelled
  final String status;
  final String? customerNote;
  final String? paymentReference;
  final String? adminNote;
  final String? title;
  final String? imageUrl;
  final String destinationType;
  final String? destinationUrl;
  final List<String> targetCountries;
  final String? routeFrom;
  final String? routeTo;
  final DateTime createdAt;
  // 0021: template orders + receipts
  final int? orderNo;
  final String? templateId;
  final AdCreative? creative;
  final DateTime? startsOn;
  final String? receiptPath;
  final DateTime? receiptUploadedAt;
  final DateTime? adStartsAt;
  final DateTime? adEndsAt;
  /// Customer changed the banner after sending the receipt (0023).
  final DateTime? editedAfterReceiptAt;

  const AdOrder({
    required this.id,
    required this.advertiserId,
    required this.packageId,
    required this.packageName,
    required this.days,
    required this.price,
    required this.currency,
    required this.paymentStatus,
    required this.status,
    this.customerNote,
    this.paymentReference,
    this.adminNote,
    this.title,
    this.imageUrl,
    this.destinationType = 'profile',
    this.destinationUrl,
    this.targetCountries = const [],
    this.routeFrom,
    this.routeTo,
    required this.createdAt,
    this.orderNo,
    this.templateId,
    this.creative,
    this.startsOn,
    this.receiptPath,
    this.receiptUploadedAt,
    this.adStartsAt,
    this.adEndsAt,
    this.editedAfterReceiptAt,
  });

  factory AdOrder.fromJson(Map<String, dynamic> j) => AdOrder(
        id: j['id'] as String,
        advertiserId: j['advertiser_id'] as String,
        packageId: j['package_id'] as String?,
        packageName: (j['package_name'] as String?) ?? '',
        days: (j['days'] as num?)?.toInt() ?? 0,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        currency: (j['currency'] as String?) ?? 'USD',
        paymentStatus: (j['payment_status'] as String?) ?? 'unpaid',
        status: (j['status'] as String?) ?? 'pending_payment',
        customerNote: j['customer_note'] as String?,
        paymentReference: j['payment_reference'] as String?,
        adminNote: j['admin_note'] as String?,
        title: j['title'] as String?,
        imageUrl: j['image_url'] as String?,
        destinationType: (j['destination_type'] as String?) ?? 'profile',
        destinationUrl: j['destination_url'] as String?,
        targetCountries: (j['target_countries'] as List? ?? const []).map((v) => '$v').toList(),
        routeFrom: j['route_from'] as String?,
        routeTo: j['route_to'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
        orderNo: (j['order_no'] as num?)?.toInt(),
        templateId: j['template_id'] as String?,
        creative: AdCreative.tryParse(j['creative']),
        startsOn: DateTime.tryParse('${j['starts_on'] ?? ''}'),
        receiptPath: j['receipt_path'] as String?,
        receiptUploadedAt: DateTime.tryParse('${j['receipt_uploaded_at'] ?? ''}')?.toLocal(),
        adStartsAt: DateTime.tryParse('${j['ad_starts_at'] ?? ''}')?.toLocal(),
        adEndsAt: DateTime.tryParse('${j['ad_ends_at'] ?? ''}')?.toLocal(),
        editedAfterReceiptAt: DateTime.tryParse('${j['edited_after_receipt_at'] ?? ''}')?.toLocal(),
      );

  /// Short human order number, e.g. "R-1024".
  String get number => orderNo == null ? id.substring(0, 8).toUpperCase() : 'R-$orderNo';

  /// What the customer sees: awaiting_payment → reviewing → approved /
  /// rejected → scheduled → live → ended (or cancelled).
  AdStage get stage {
    switch (status) {
      case 'cancelled':
        return AdStage.cancelled;
      case 'rejected':
        return AdStage.rejected;
      case 'pending_payment':
        return AdStage.awaitingPayment;
      case 'awaiting_approval':
        return AdStage.reviewing;
      case 'approved':
        return AdStage.approved;
      case 'expired':
        return AdStage.ended;
      case 'active':
        final now = DateTime.now();
        if (adStartsAt != null && now.isBefore(adStartsAt!)) return AdStage.scheduled;
        if (adEndsAt != null && !now.isBefore(adEndsAt!)) return AdStage.ended;
        return AdStage.live;
      default:
        return AdStage.reviewing;
    }
  }
}

class Ad {
  final String id;
  final String? orderId;
  final String advertiserId;
  final String? title;
  final String imageUrl;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;
  final String destinationType;
  final String? destinationUrl;
  final List<String> targetCountries;
  final String? routeFrom;
  final String? routeTo;
  /// Template banner (0021); null for uploaded-image ads.
  final AdCreative? creative;
  /// Admin order in the loads list (0026): smaller = shown first.
  final int priority;

  const Ad({
    required this.id,
    this.orderId,
    required this.advertiserId,
    this.title,
    required this.imageUrl,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
    this.destinationType = 'profile',
    this.destinationUrl,
    this.targetCountries = const [],
    this.routeFrom,
    this.routeTo,
    this.creative,
    this.priority = 100,
  });

  bool get isLive {
    final now = DateTime.now();
    return isActive && !now.isBefore(startsAt) && now.isBefore(endsAt);
  }

  factory Ad.fromJson(Map<String, dynamic> j) => Ad(
        id: j['id'] as String,
        orderId: j['order_id'] as String?,
        advertiserId: j['advertiser_id'] as String,
        title: j['title'] as String?,
        imageUrl: (j['image_url'] as String?) ?? '',
        startsAt: DateTime.tryParse('${j['starts_at']}')?.toLocal() ?? DateTime.now(),
        endsAt: DateTime.tryParse('${j['ends_at']}')?.toLocal() ?? DateTime.now(),
        isActive: j['is_active'] == true,
        destinationType: (j['destination_type'] as String?) ?? 'profile',
        destinationUrl: j['destination_url'] as String?,
        targetCountries: (j['target_countries'] as List? ?? const []).map((v) => '$v').toList(),
        routeFrom: j['route_from'] as String?,
        routeTo: j['route_to'] as String?,
        creative: AdCreative.tryParse(j['creative']),
        priority: j['priority'] is num ? (j['priority'] as num).toInt() : 100,
      );
}

enum AdStage { awaitingPayment, reviewing, approved, rejected, scheduled, live, ended, cancelled }

/// One editable text on a template, positioned in banner fractions.
class AdTemplateField {
  final String key;
  final String label;
  final String defaultText;
  final double x; // left edge, 0..1 of the banner width
  final double y; // top edge, 0..1 of the banner height
  final double w; // box width, 0..1
  final double size; // font size in px at 1350 px banner width
  final int max; // max characters
  final String align; // left | center | right
  final bool bold;

  const AdTemplateField({
    required this.key,
    required this.label,
    this.defaultText = '',
    required this.x,
    required this.y,
    required this.w,
    required this.size,
    required this.max,
    this.align = 'left',
    this.bold = false,
  });

  static double _d(Object? v, double def) => v is num ? v.toDouble() : (double.tryParse('$v') ?? def);

  factory AdTemplateField.fromJson(Map<String, dynamic> j) => AdTemplateField(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        defaultText: '${j['default'] ?? ''}',
        x: _d(j['x'], 0.05),
        y: _d(j['y'], 0.2),
        w: _d(j['w'], 0.6),
        size: _d(j['size'], 48),
        max: (j['max'] is num) ? (j['max'] as num).toInt() : int.tryParse('${j['max']}') ?? 40,
        align: (j['align'] as String?) ?? 'left',
        bold: j['bold'] == true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'default': defaultText,
        'x': double.parse(x.toStringAsFixed(3)),
        'y': double.parse(y.toStringAsFixed(3)),
        'w': double.parse(w.toStringAsFixed(3)),
        'size': size.round(),
        'max': max,
        'align': align,
        'bold': bold,
      };

  AdTemplateField copyWith({
    String? label,
    String? defaultText,
    double? x,
    double? y,
    double? w,
    double? size,
    int? max,
    String? align,
    bool? bold,
  }) =>
      AdTemplateField(
        key: key,
        label: label ?? this.label,
        defaultText: defaultText ?? this.defaultText,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        size: size ?? this.size,
        max: max ?? this.max,
        align: align ?? this.align,
        bold: bold ?? this.bold,
      );
}

/// Where the customer's logo goes on a template (parts of the banner).
class AdLogoSlot {
  final double x;
  final double y;
  final double w;
  final double h;
  const AdLogoSlot({required this.x, required this.y, required this.w, required this.h});

  static AdLogoSlot? tryParse(Object? v) {
    if (v is! Map) return null;
    double d(Object? o, double def) => o is num ? o.toDouble() : (double.tryParse('$o') ?? def);
    return AdLogoSlot(x: d(v['x'], 0.02), y: d(v['y'], 0.1), w: d(v['w'], 0.2), h: d(v['h'], 0.8));
  }

  Map<String, dynamic> toJson() => {
        'x': double.parse(x.toStringAsFixed(3)),
        'y': double.parse(y.toStringAsFixed(3)),
        'w': double.parse(w.toStringAsFixed(3)),
        'h': double.parse(h.toStringAsFixed(3)),
      };

  AdLogoSlot copyWith({double? x, double? y, double? w, double? h}) =>
      AdLogoSlot(x: x ?? this.x, y: y ?? this.y, w: w ?? this.w, h: h ?? this.h);
}

/// Admin-made banner template (1350×300 background + text fields + colours).
class AdTemplate {
  final String id;
  final String name;
  final String imageUrl;
  final List<AdTemplateField> fields;
  final List<String> colors; // '#RRGGBB'
  final AdLogoSlot? logo; // null = no logo on this template
  /// 'standard_v2' = fixed 1200×400 layout (0023); older ones are 'custom'.
  final String layout;
  /// Who may use it (0029): 'cargo' (load ads), 'service' or 'all'.
  final String audience;
  final bool isActive;
  final int sort;
  /// 0032: null = admin template; a user id = that user's own picture.
  final String? ownerId;

  const AdTemplate({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.fields,
    required this.colors,
    this.logo,
    this.layout = 'custom',
    this.audience = 'cargo',
    required this.isActive,
    required this.sort,
    this.ownerId,
  });

  bool get isOwn => ownerId != null;
  bool get isStandard => layout == 'standard_v2';
  bool get forCargo => audience == 'cargo' || audience == 'all';
  bool get forService => audience == 'service' || audience == 'all';

  /// Sample banner shown in the template list.
  AdCreative sample({Map<String, String>? texts}) => AdCreative(
        version: 2,
        imageUrl: imageUrl,
        texts: texts ?? const {'company': 'ŞİRKƏT ADI', 'activity': 'Fəaliyyət sahəsi', 'phone': '+994 00 000 00 00'},
      );

  factory AdTemplate.fromJson(Map<String, dynamic> j) => AdTemplate(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        imageUrl: (j['image_url'] as String?) ?? '',
        fields: (j['fields'] is List ? j['fields'] as List : const [])
            .whereType<Map>()
            .map((m) => AdTemplateField.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        colors: (j['colors'] is List ? j['colors'] as List : const []).map((c) => '$c').toList(),
        logo: AdLogoSlot.tryParse(j['logo']),
        layout: (j['layout'] as String?) ?? 'custom',
        audience: (j['audience'] as String?) ?? 'cargo',
        isActive: j['is_active'] == true,
        sort: (j['sort'] as num?)?.toInt() ?? 100,
        ownerId: j['owner_id'] as String?,
      );

  /// Preview creative with the template's default texts and first colour.
  AdCreative preview({Map<String, String>? texts, String? color, String? logoUrl}) => AdCreative(
        imageUrl: imageUrl,
        fields: fields,
        texts: texts ?? {for (final f in fields) f.key: f.defaultText.isEmpty ? f.label : f.defaultText},
        color: color ?? (colors.isEmpty ? '#FFFFFF' : colors.first),
        logo: logo,
        logoUrl: logoUrl,
      );
}

/// A finished template banner: background + texts + chosen colour.
class AdCreative {
  /// 1 = free layout (0021/0022, 1350×300, no longer published);
  /// 2 = standard 1200×400 layout (0023).
  final int version;
  final String imageUrl;
  final List<AdTemplateField> fields;
  final Map<String, String> texts;
  final String color;
  final AdLogoSlot? logo;
  final String? logoUrl;
  /// v2: per text line (company / activity / phone) font, size, colour.
  final Map<String, AdTextStyle> style;
  /// v2: logo circle background: dark | light | none.
  final String logoBg;

  const AdCreative({
    this.version = 1,
    required this.imageUrl,
    this.fields = const [],
    required this.texts,
    this.color = '#FFFFFF',
    this.logo,
    this.logoUrl,
    this.style = const {},
    this.logoBg = 'dark',
  });

  bool get isStandard => version == 2;

  AdTextStyle styleOf(String key) => style[key] ?? AdTextStyle.defaults(key);

  static AdCreative? tryParse(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final fields = (j['fields'] is List ? j['fields'] as List : const [])
        .whereType<Map>()
        .map((m) => AdTemplateField.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final texts = j['texts'] is Map
        ? (j['texts'] as Map).map((k, val) => MapEntry('$k', '${val ?? ''}'))
        : <String, String>{};
    final version = (j['version'] is num) ? (j['version'] as num).toInt() : int.tryParse('${j['version'] ?? ''}') ?? 1;
    final style = <String, AdTextStyle>{};
    if (j['style'] is Map) {
      (j['style'] as Map).forEach((k, val) {
        if (val is Map) style['$k'] = AdTextStyle.fromJson('$k', Map<String, dynamic>.from(val));
      });
    }
    return AdCreative(
      version: version,
      style: style,
      logoBg: (j['logo_bg'] as String?) ?? 'dark',
      imageUrl: (j['image_url'] as String?) ?? '',
      fields: fields,
      texts: texts,
      color: (j['color'] as String?) ?? '#FFFFFF',
      logo: AdLogoSlot.tryParse(j['logo']),
      logoUrl: (j['logo_url'] as String?)?.trim().isEmpty == true ? null : j['logo_url'] as String?,
    );
  }
}

/// Font / size / colour of one text line on a standard banner.
class AdTextStyle {
  final String font;
  final double size; // 0.6–1.0 of the largest size that fits the box
  final String color; // #RRGGBB

  const AdTextStyle({required this.font, required this.size, required this.color});

  factory AdTextStyle.defaults(String key) => AdTextStyle(
        font: 'Arial',
        size: 1,
        color: key == 'activity' ? '#FFCC00' : '#FFFFFF',
      );

  factory AdTextStyle.fromJson(String key, Map<String, dynamic> j) {
    final d = AdTextStyle.defaults(key);
    final size = j['size'] is num ? (j['size'] as num).toDouble() : double.tryParse('${j['size']}');
    return AdTextStyle(
      font: (j['font'] as String?) ?? d.font,
      size: (size ?? d.size).clamp(0.6, 1.0).toDouble(),
      color: (j['color'] as String?) ?? d.color,
    );
  }

  Map<String, dynamic> toJson() => {'font': font, 'size': double.parse(size.toStringAsFixed(2)), 'color': color};

  AdTextStyle copyWith({String? font, double? size, String? color}) =>
      AdTextStyle(font: font ?? this.font, size: size ?? this.size, color: color ?? this.color);
}

/// The fixed 1200×400 layout every standard template uses (the admin's
/// coordinate sheet). Only these numbers decide where things go.
class AdStandardLayout {
  AdStandardLayout._();
  static const double width = 1200;
  static const double height = 400;
  // logo circle
  static const double logoX = 30, logoY = 120, logoSize = 160;
  // text boxes: x, y, w, h, max lines, base font px (at 1200 wide)
  static const company = (x: 220.0, y: 45.0, w: 440.0, h: 85.0, lines: 2, base: 64.0);
  static const activity = (x: 220.0, y: 150.0, w: 440.0, h: 75.0, lines: 2, base: 46.0);
  static const phone = (x: 220.0, y: 250.0, w: 440.0, h: 70.0, lines: 1, base: 48.0);
  /// Text never enters the visual zone (690,20)–(1180,380).
  static const double visualZoneX = 690;
  /// The app uses only Arial, so ads do too (no font choice).
  static const fonts = ['Arial'];
  static const maxLen = {'company': 40, 'activity': 60, 'phone': 25};
}

/// '#RRGGBB' → Color value (white when invalid).
int adColorValue(String hex) {
  final h = hex.replaceAll('#', '').trim();
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v ?? 0xFFFFFFFF;
}

/// Banner format of the home-feed ads: 1200×400 (3 : 1), never cropped. A
/// feed slot no taller than a cargo card.
class AdBannerSpec {
  AdBannerSpec._();
  static const int width = 1200;
  static const int height = 400;
  static const double ratio = width / height;
  static const int minWidth = 900;
  /// Allowed deviation from the exact ratio (5 %).
  static const double tolerance = 0.05;
}

/// Where ads appear in the loads list and how long one ad stays in a slot
/// (Admin → Reklamlar → "Reklamın yeri və müddəti", migration 0025).
class AdFeedLayout {
  /// The first ad comes after this many loads.
  final int firstAfter;
  /// Then one ad after every [every] loads.
  final int every;
  /// With several live ads: minutes one ad stays in a slot before the next
  /// one takes its place. 0 = no change (each slot keeps its own ad).
  final int rotateMinutes;
  /// false (default) = one ad appears in only one place; extra places stay
  /// empty. true = ads repeat to fill every place.
  final bool repeat;

  const AdFeedLayout({this.firstAfter = 6, this.every = 6, this.rotateMinutes = 0, this.repeat = false});

  static const defaults = AdFeedLayout();

  static int _i(Object? v, int def, int lo, int hi) {
    final n = v is num ? v.toInt() : (int.tryParse('$v') ?? def);
    return n < lo ? lo : (n > hi ? hi : n);
  }

  factory AdFeedLayout.fromJson(Map<String, dynamic> j) => AdFeedLayout(
        firstAfter: _i(j['first_after'], 6, 1, 50),
        every: _i(j['every'], 6, 2, 50),
        rotateMinutes: _i(j['rotate_minutes'], 0, 0, 1440),
        repeat: j['repeat'] == true,
      );
}

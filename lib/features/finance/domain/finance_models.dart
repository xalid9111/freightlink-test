// Finance & payments (migration 0037) — models and pure logic, no Flutter
// widgets and no Supabase, so everything here is unit-tested in
// test/finance_logic_test.dart.
import 'dart:math';

enum PayMethod { card, applePay, googlePay }

extension PayMethodX on PayMethod {
  String get wire => switch (this) { PayMethod.card => 'card', PayMethod.applePay => 'apple_pay', PayMethod.googlePay => 'google_pay' };
  static PayMethod? parse(String? s) => switch (s) { 'card' => PayMethod.card, 'apple_pay' => PayMethod.applePay, 'google_pay' => PayMethod.googlePay, _ => null };
}

/// Device → which wallets to offer (the card is always offered).
/// Apple Pay on iPhone / iPad / Mac (Safari, Home Screen app);
/// Google Pay on Android and on computers (Chrome). The provider's SDK
/// makes the final availability check when a real provider is connected.
enum DeviceKind { apple, android, desktop }

List<PayMethod> methodsForDevice(DeviceKind device, List<PayMethod> enabled) {
  final wallet = switch (device) { DeviceKind.apple => PayMethod.applePay, _ => PayMethod.googlePay };
  return [
    if (enabled.contains(wallet)) wallet,
    if (enabled.contains(PayMethod.card)) PayMethod.card,
  ];
}

/// Random checkout key: created once when the checkout opens, sent with
/// every attempt, so a double tap / retry can never create a second
/// payment (the server returns the same one).
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return 'chk_${List.generate(24, (_) => chars[r.nextInt(chars.length)]).join()}';
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String money(double v, [String currency = 'AZN']) {
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final int0 = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  return '$int0.${parts[1]} $currency';
}

class CheckoutAvailability {
  final bool available;
  final String mode; // off | test | live
  final List<PayMethod> methods;
  const CheckoutAvailability({required this.available, required this.mode, this.methods = const []});
  bool get isTest => mode == 'test';

  factory CheckoutAvailability.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return CheckoutAvailability(
      available: m['available'] == true,
      mode: '${m['mode'] ?? 'off'}',
      methods: (m['methods'] is List ? m['methods'] as List : const []).map((x) => PayMethodX.parse('$x')).whereType<PayMethod>().toList(),
    );
  }
}

class CheckoutPayment {
  final String id;
  final String orderId;
  final double amount;
  final String currency;
  final String status; // created | pending | succeeded | failed | cancelled | refunded
  final String mode;
  final String? failureReason;
  const CheckoutPayment({required this.id, required this.orderId, required this.amount, required this.currency,
      required this.status, required this.mode, this.failureReason});

  bool get isFinal => const {'succeeded', 'failed', 'cancelled', 'refunded'}.contains(status);

  factory CheckoutPayment.fromJson(Map j) => CheckoutPayment(
        id: '${j['id']}',
        orderId: '${j['order_id'] ?? ''}',
        amount: _d(j['amount']),
        currency: '${j['currency'] ?? 'AZN'}',
        status: '${j['status'] ?? 'created'}',
        mode: '${j['mode'] ?? 'test'}',
        failureReason: j['failure_reason'] as String?,
      );
}

class FinanceSummary {
  final String mode;
  final String currency;
  final double gross, commission, confirmedBalance, pending, withdrawable, transferred, payoutsInProgress;
  final int pendingCount, succeededCount;
  final bool hasVerifiedAccount;
  const FinanceSummary({
    required this.mode,
    this.currency = 'AZN',
    this.gross = 0,
    this.commission = 0,
    this.confirmedBalance = 0,
    this.pending = 0,
    this.withdrawable = 0,
    this.transferred = 0,
    this.payoutsInProgress = 0,
    this.pendingCount = 0,
    this.succeededCount = 0,
    this.hasVerifiedAccount = false,
  });

  factory FinanceSummary.fromJson(Map j) => FinanceSummary(
        mode: '${j['mode'] ?? 'live'}',
        currency: '${j['currency'] ?? 'AZN'}',
        gross: _d(j['gross']),
        commission: _d(j['commission']),
        confirmedBalance: _d(j['confirmed_balance']),
        pending: _d(j['pending']),
        withdrawable: _d(j['withdrawable']),
        transferred: _d(j['transferred']),
        payoutsInProgress: _d(j['payouts_in_progress']),
        pendingCount: (j['pending_count'] as num?)?.toInt() ?? 0,
        succeededCount: (j['succeeded_count'] as num?)?.toInt() ?? 0,
        hasVerifiedAccount: j['has_verified_account'] == true,
      );
}

class FinancePayment {
  final String id, orderId, status, method, mode, provider, currency;
  final int? orderNo;
  final String? orderTitle, customer, failureReason, orderStatus;
  final double amount, commission;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  const FinancePayment({
    required this.id,
    required this.orderId,
    required this.status,
    required this.method,
    required this.mode,
    required this.provider,
    required this.currency,
    required this.amount,
    required this.commission,
    required this.createdAt,
    this.orderNo,
    this.orderTitle,
    this.customer,
    this.failureReason,
    this.orderStatus,
    this.confirmedAt,
  });

  /// "R-1024" like the order screens, or the start of the order id.
  String get orderLabel => orderNo != null ? 'R-$orderNo' : orderId.substring(0, min(8, orderId.length)).toUpperCase();

  factory FinancePayment.fromJson(Map j) => FinancePayment(
        id: '${j['id']}',
        orderId: '${j['order_id'] ?? ''}',
        status: '${j['status'] ?? ''}',
        method: '${j['method'] ?? ''}',
        mode: '${j['mode'] ?? ''}',
        provider: '${j['provider'] ?? ''}',
        currency: '${j['currency'] ?? 'AZN'}',
        amount: _d(j['amount']),
        commission: _d(j['commission']),
        createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        confirmedAt: DateTime.tryParse('${j['confirmed_at'] ?? ''}')?.toLocal(),
        orderNo: (j['order_no'] as num?)?.toInt(),
        orderTitle: j['order_title'] as String?,
        customer: j['customer'] as String?,
        failureReason: j['failure_reason'] as String?,
        orderStatus: j['order_status'] as String?,
      );
}

class PayoutAccount {
  final String id, kind, holderName, status;
  final String? bankName, cardLast4, cardBrand, companyName, voen, ibanMasked;
  final bool isPrimary;
  const PayoutAccount({
    required this.id,
    required this.kind,
    required this.holderName,
    required this.status,
    required this.isPrimary,
    this.bankName,
    this.cardLast4,
    this.cardBrand,
    this.companyName,
    this.voen,
    this.ibanMasked,
  });

  bool get isCard => kind == 'card';
  bool get isDisabled => status == 'disabled';
  bool get isVerified => status == 'verified';

  /// "Visa •••• 1234" / "FreightLink MMC · AZ21 •••• 1944"
  String get title => isCard
      ? '${switch (cardBrand) { 'visa' => 'Visa', 'mastercard' => 'Mastercard', _ => 'Kart' }} •••• ${cardLast4 ?? ''}'
      : '${companyName ?? holderName} · ${ibanMasked ?? ''}';

  factory PayoutAccount.fromJson(Map j) => PayoutAccount(
        id: '${j['id']}',
        kind: '${j['kind']}',
        holderName: '${j['holder_name'] ?? ''}',
        status: '${j['status'] ?? 'pending_verification'}',
        isPrimary: j['is_primary'] == true,
        bankName: j['bank_name'] as String?,
        cardLast4: j['card_last4'] as String?,
        cardBrand: j['card_brand'] as String?,
        companyName: j['company_name'] as String?,
        voen: j['voen'] as String?,
        ibanMasked: j['iban_masked'] as String?,
      );
}

class PaymentSettingsData {
  final String mode, provider;
  final double commissionPct;
  final List<PayMethod> methods;
  const PaymentSettingsData({required this.mode, required this.provider, required this.commissionPct, required this.methods});

  factory PaymentSettingsData.fromJson(Map j) => PaymentSettingsData(
        mode: '${j['mode'] ?? 'off'}',
        provider: '${j['provider'] ?? 'test'}',
        commissionPct: _d(j['commission_pct']),
        methods: (j['methods'] is List ? j['methods'] as List : const []).map((x) => PayMethodX.parse('$x')).whereType<PayMethod>().toList(),
      );
}

// ---- validation (same rules as the database) ---------------------------------

/// VÖEN: 10 digits.
bool isValidVoen(String s) => RegExp(r'^[0-9]{10}$').hasMatch(s.trim());

/// Azerbaijani IBAN: AZ + 2 check digits + 4-letter bank code + 20
/// characters (spaces allowed while typing), with the ISO 13616 mod-97 check.
String normalizeIban(String s) => s.replaceAll(RegExp(r'\s'), '').toUpperCase();

bool isValidAzIban(String s) {
  final iban = normalizeIban(s);
  if (!RegExp(r'^AZ[0-9]{2}[A-Z]{4}[A-Z0-9]{20}$').hasMatch(iban)) return false;
  final moved = iban.substring(4) + iban.substring(0, 4);
  var rem = 0;
  for (final ch in moved.split('')) {
    final code = ch.codeUnitAt(0);
    final digits = code >= 65 ? '${code - 55}' : ch;
    for (final d in digits.split('')) {
      rem = (rem * 10 + int.parse(d)) % 97;
    }
  }
  return rem == 1;
}

/// Only the last 4 digits of a card are ever entered / stored.
bool isValidLast4(String s) => RegExp(r'^[0-9]{4}$').hasMatch(s.trim());

/// Server error → Azerbaijani text for the finance screens (admin only).
String financeErrorText(Object e) {
  final raw = e.toString();
  const map = {
    'reauth_required': 'Təhlükəsizlik üçün parolu yenidən daxil edin.',
    'not_authorized': 'Bu bölmə yalnız maliyyə admininə açıqdır.',
    'live_not_enabled': 'Canlı ödənişlər bu versiyada aktivləşdirilmir.',
    'provider_not_configured': 'Ödəniş provayderi hələ qoşulmayıb.',
    'provider_not_implemented': 'Bu provayder hələ inteqrasiya olunmayıb.',
    'payouts_need_live_provider': 'Banka köçürmə yalnız real provayder qoşulandan sonra mümkündür.',
    'invalid_account': 'Hesab məlumatları düzgün deyil.',
    'too_many_accounts': 'Ən çox 10 aktiv hesab ola bilər.',
    'account_not_found': 'Hesab tapılmadı.',
    'invalid_commission': 'Komissiya 0–50% arasında olmalıdır.',
    'invalid_methods': 'Ən azı bir ödəniş üsulu seçin.',
  };
  for (final e in map.entries) {
    if (raw.contains(e.key)) return e.value;
  }
  final code = RegExp(r'\b[a-z]+(?:_[a-z]+)+\b').firstMatch(raw)?.group(0);
  return 'Əməliyyat alınmadı${code == null ? '' : ' ($code)'}.';
}

/// Server error code for the customer checkout (texts are translated).
String checkoutErrorKey(Object e) {
  final raw = e.toString();
  for (final k in const ['already_paid', 'order_not_payable', 'payments_disabled', 'provider_not_configured', 'provider_not_implemented']) {
    if (raw.contains(k)) return 'pay_err_$k';
  }
  return 'pay_err_generic';
}

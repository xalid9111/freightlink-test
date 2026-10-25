// Every user can make his own load VIP (owner, 24.10.2026, migration 0062):
// like TIR Bazarı — prices 7 / 14 / 30 days, card checkout (test mode for
// now), VIP only after a verified payment. Server rules:
// supabase/tests/local/99_cargo_vip_buy.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/cargo_vip.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('plan and order from the server', () {
    final p = CargoVipPlan.fromJson({'days': 7, 'price': 5, 'currency': 'AZN', 'is_active': true});
    expect([p.days, p.price, p.currency, p.isActive], [7, 5.0, 'AZN', true]);
    final o = CargoVipOrder.fromJson({'id': 'o1', 'cargo_id': 'c1', 'days': 14, 'amount': 9, 'currency': 'AZN', 'status': 'pending_payment'});
    expect([o.id, o.cargoId, o.days, o.amount], ['o1', 'c1', 14, 9.0]);
  });

  // 0067: "VIP et" is now "Önə çıxar" (İrəli çək · VIP · Premium).
  test('"Önə çıxar" in Yüklərim and on my own load page (not on other people\'s loads)', () {
    final my = src('lib/features/cargo/presentation/my_cargo_screen.dart');
    expect(my, contains("ValueKey('my-cargo-promo-\${c.id}')"));
    expect(my, contains('showPromoChooser(context, strings, CargoPromoTarget(c))'));
    final detail = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
    final i = detail.indexOf("ValueKey('cargo-promo-open')");
    expect(i, greaterThan(0));
    // Inside the owner's tools only.
    expect(detail.lastIndexOf('if (isOwner) ...[', i), greaterThan(detail.lastIndexOf('final ownerTools', i)));
  });

  test('the app never sends a price; checkout goes to the load VIP order', () {
    final repo = src('lib/features/cargo/data/cargo_media_repository.dart');
    final start = repo.indexOf('Future<CargoVipOrder> createVipOrder');
    expect(repo.substring(start, repo.indexOf('}', start)).contains('price'), isFalse);
    expect(src('lib/features/finance/data/finance_repository.dart'), contains("'cargo_vip_order_id': vipOrderId"));
    expect(src('lib/features/cargo/presentation/widgets/cargo_promo.dart'), contains('currency: o.currency, cargo: true)'));
    final fn = src('supabase/functions/payments-checkout/index.ts');
    expect(fn, contains("rpc/cargo_vip_payment_create"));
    expect(fn, contains('targets !== 1'));
    expect(src('docs/payments/payments-checkout.dashboard.ts'), contains('rpc/cargo_vip_payment_create'));
  });

  test('admin changes the prices in the panel (Yüklər)', () {
    final admin = src('lib/features/admin/presentation/admin_pages.dart');
    expect(admin, contains('const CargoVipPricesCard()'));
    expect(admin, contains('adminSetVipPlan(p.days, v'));
  });

  test('0062 is safe: start prices as TIR Bazarı, VIP only via a verified payment, nothing dropped', () {
    final sql = src('supabase/migrations/0062_cargo_vip_buy.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('values (7, 5), (14, 9), (30, 15)'));
    expect(sql, contains("revoke all on function public._cargo_vip_apply(uuid) from public, anon, authenticated;"));
    expect(sql, contains("if v_new = 'succeeded' and v_pay.cargo_vip_order_id is not null then"));
    final run = src('supabase/tests/local/run_local.sh');
    expect(run, contains('0062_cargo_vip_buy.sql'));
    expect(run, contains('99_cargo_vip_buy.sql'));
  });
}

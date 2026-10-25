-- TIR BAZARI — 0054: a successful TEST payment makes the ad VIP. Rolled back.
\set seller  '''a0000000-0000-4000-8000-000000000012'''
\set l1 '''aa540000-0000-4000-8000-000000000001'''
\set l2 '''aa540000-0000-4000-8000-000000000002'''
\set ad '''e0540000-0000-4000-8000-000000000001'''

begin;
-- 0066 changed the VIP packs (1 / 5 / 15 / 30 days); this suite checks
-- 0044's rules with 0044's own packs (rolled back with everything else).
delete from public.market_vip_plans where days not in (7, 14, 30);
update public.market_vip_plans set is_active = true, price = case days when 7 then 5 when 14 then 9 else 15 end;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 0, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}';
set role authenticated;
select tests.login(:seller);
insert into public.market_listings (id, category, brand, model, price, currency, status, is_vip, vip_until)
values (:l1, 'truck', 'DAF', 'XF', 100, 'AZN', 'active', false, null),
       (:l2, 'truck', 'MAN', 'TGX', 100, 'AZN', 'active', false, null);
create temp table t_o1 as select * from public.market_vip_order_create(:l1, 7);
create temp table t_o2 as select * from public.market_vip_order_create(:l2, 7);
grant select on t_o1, t_o2 to service_role;
reset role;
insert into public.ad_payments (market_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'vip54-ok-0001' from t_o1;
insert into public.ad_payments (market_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'vip54-no-0001' from t_o2;
insert into public.ad_orders (id, advertiser_id, package_name, days, price, currency, title)
values (:ad, :seller, '5 gün', 5, 20.00, 'AZN', 'TEST AD 54');
insert into public.ad_payments (order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
values (:ad, :seller, 20.00, 'AZN', 'card', 'test', 'test', 'ad54-ok-0001');

set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt54_ok', (select id from public.ad_payments where idempotency_key = 'vip54-ok-0001'),
  'payment.succeeded', (select amount from t_o1), 'AZN', null) = 'applied', 'A1 test payment succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt54_no', (select id from public.ad_payments where idempotency_key = 'vip54-no-0001'),
  'payment.failed', (select amount from t_o2), 'AZN', null) = 'applied', 'A2 test payment failed');
select tests.check(public.finance_apply_provider_event('test', 'evt54_ad', (select id from public.ad_payments where idempotency_key = 'ad54-ok-0001'),
  'payment.succeeded', 20.00, 'AZN', null) = 'applied', 'A3 test payment for a banner ad succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt54_ok', (select id from public.ad_payments where idempotency_key = 'vip54-ok-0001'),
  'payment.succeeded', (select amount from t_o1), 'AZN', null) = 'duplicate', 'A4 the same event twice is ignored');
reset role;

select tests.check((select is_vip and vip_since is not null and vip_until between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
                      from public.market_listings where id = :l1), 'B1 successful test payment: the ad is VIP for 7 days');
select tests.check((select status = 'paid' and paid_at is not null from public.market_vip_orders where id = (select id from t_o1)),
  'B2 …and its VIP order is paid');
select tests.check((select (array_agg(x.id order by x.ordinality))[1] = :l1 from public.market_vip_latest(null, 6) with ordinality x),
  'B3 …and it is first in the newest VIP list');
select tests.check((select not is_vip and vip_since is null from public.market_listings where id = :l2), 'B4 failed test payment: no VIP');
select tests.check((select status = 'pending_payment' from public.market_vip_orders where id = (select id from t_o2)), 'B5 …and the order stays unpaid');
select tests.check((select payment_status is distinct from 'paid' and paid_at is null from public.ad_orders where id = :ad),
  'B6 a TEST payment still never marks a banner ad order paid');
select tests.check((select count(*) = 1 from public.ad_payments where idempotency_key = 'vip54-ok-0001' and mode = 'test' and status = 'succeeded'),
  'B7 the payment stays marked as TEST (not counted as real income)');
select tests.summary('TIR BAZARI TEST PAYMENT MAKES VIP (0054)');
rollback;

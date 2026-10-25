-- LOADS — 0067: İrəli çək, VIP daily lift, Premium (as TIR Bazarı 0066). Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c6700000-0000-4000-8000-000000000001'''
\set c2 '''c6700000-0000-4000-8000-000000000002'''
\set c3 '''c6700000-0000-4000-8000-000000000003'''
\set c4 '''c6700000-0000-4000-8000-000000000004'''

begin;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 0, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}';

-- ---- prices ---------------------------------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check((select string_agg(kind || qty || ':' || price::numeric(12,0), ',' order by kind, qty) from public.cargo_promo_plans)
  = 'bump1:3,bump3:6,bump5:9,bump10:15,premium1:7,premium5:20,premium15:45,premium30:60', 'P1 İrəli çək and Premium prices');
select tests.check((select string_agg(days || ':' || price::numeric(12,0), ',' order by days) from public.cargo_vip_plans where is_active)
  = '1:5,5:15,15:25,30:40', 'P2 VIP packs 1 / 5 / 15 / 30 days = 5 / 15 / 25 / 40 AZN');
select tests.check(tests.err($$ select public.admin_cargo_set_promo_plan('bump', 1, 1) $$) like '%admin_only%', 'P3 a user cannot change prices');
select tests.check(tests.err($$ update public.cargo_promo_plans set price = 1 $$) like '%permission denied%', 'P4 no direct writes');
select tests.login(:admin);
select tests.check((select price = 4 from public.admin_cargo_set_promo_plan('bump', 1, 4)), 'P5 admin changes a price');
select tests.check(tests.err($$ select public.admin_cargo_set_promo_plan('gold', 1, 4) $$) like '%invalid_kind%', 'P6 unknown kind refused');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'cargo.promo_plan'), 'P7 price changes are logged');
update public.cargo_promo_plans set price = 3 where kind = 'bump' and qty = 1;

-- ---- loads ------------------------------------------------------------------
set role authenticated;
select tests.login(:owner);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price,
                          pickup_date, premium_until, bump_total, bump_start)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date + 3, now() + interval '9 days', 9, now());
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c2, :owner, 'Azerbaijan', 'Baku', 'Russia', 'Moscow', 20000, 1500, current_date + 3),
       (:c3, :owner, 'Azerbaijan', 'Ganja', 'Turkey', 'Istanbul', 20000, 1500, current_date + 3);
select tests.check((select premium_until is null and bump_total is null and bump_start is null from public.cargo where id = :c1),
  'G1 a new load cannot carry Premium or lifts');
update public.cargo set premium_until = now() + interval '9 days', bump_total = 9, bump_start = now(), offered_price = 1600 where id = :c1;
select tests.check((select premium_until is null and bump_total is null and offered_price = 1600 from public.cargo where id = :c1),
  'G2 an owner cannot give himself Premium or lifts (other edits still work)');
update public.cargo set status = 'cancelled' where id = :c3;
reset role;
-- Test set-up as trusted server code: the loads are a few days old.
set local app.cargo_trusted = '1';
update public.cargo set created_at = now() - interval '3 days' where id = :c1;
update public.cargo set created_at = now() - interval '1 day' where id = :c2;
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price,
                          pickup_date, created_at)
values (:c4, :other, 'Azerbaijan', 'Baku', 'Iran', 'Tabriz', 20000, 1500, current_date + 3, now() - interval '2 days');
set local app.cargo_trusted = '';

-- ---- VIP lift time ------------------------------------------------------------
select pg_temp.as_service();
update public.cargo set is_featured = true, featured_until = now() + interval '10 days' where id = :c4;
select tests.check((select featured_since > now() - interval '1 minute' from public.cargo where id = :c4), 'F1 VIP switched on: lifted now');
update public.cargo set is_featured = false, featured_until = null where id = :c4;
select tests.check((select featured_since is null from public.cargo where id = :c4), 'F2 VIP off: no VIP lift');
select tests.login(:owner);
reset role;

-- ---- orders -------------------------------------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'bump', 1) $$, :c1)) like '%cargo_not_found%',
  'O1 only for my own load');
select tests.login(:owner);
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'bump', 1) $$, :c3)) like '%cargo_not_open%',
  'O2 only for an open load');
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'bump', 2) $$, :c1)) like '%invalid_plan%',
  'O3 only a listed pack');
create temp table t_b as select * from public.cargo_promo_order_create(:c1, 'bump', 3);
create temp table t_pr as select * from public.cargo_promo_order_create(:c2, 'premium', 5);
create temp table t_fail as select * from public.cargo_promo_order_create(:c2, 'bump', 1);
select tests.check((select id from public.cargo_promo_order_create(:c1, 'bump', 3)) = (select id from t_b), 'O4 double tap = one order');
select tests.check((select amount = 6 and currency = 'AZN' from t_b), 'O5 the price comes from the server');
select tests.check(tests.err(format($$ select public.cargo_promo_payment_create(%L, 'card', 'cpromo67-x-0009') $$, (select id from t_b)))
  like '%payments_disabled%', 'O6 test mode: checkout closed for normal users (as VIP)');
grant select on t_b, t_pr, t_fail to service_role;
reset role;
update public.payment_settings set mode = 'live' where id = 1;
set role authenticated;
select tests.login(:owner);
create temp table t_live as select * from public.cargo_promo_payment_create((select id from t_pr), 'card', 'cpromo67-live-01');
select tests.check((select amount = 20 and mode = 'live' and cargo_promo_order_id = (select id from t_pr) from t_live),
  'O6b live checkout: amount from the order, linked to it');
reset role;
delete from public.ad_payments where idempotency_key = 'cpromo67-live-01';  -- test row only (rolled back)
update public.payment_settings set mode = 'test' where id = 1;
insert into public.ad_payments (cargo_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cpromo67-b-0001' from t_b;
insert into public.ad_payments (cargo_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cpromo67-p-0001' from t_pr;
insert into public.ad_payments (cargo_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cpromo67-f-0001' from t_fail;
create temp table t_pay as select * from public.ad_payments where idempotency_key = 'cpromo67-b-0001';
create temp table t_pay2 as select * from public.ad_payments where idempotency_key = 'cpromo67-p-0001';
create temp table t_pay3 as select * from public.ad_payments where idempotency_key = 'cpromo67-f-0001';
grant select on t_pay, t_pay2, t_pay3 to service_role;
select tests.check(tests.err($$ insert into public.ad_payments (market_promo_order_id, cargo_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
  select m.id, (select id from t_b), m.user_id, 1, 'AZN', 'card', 'test', 'test', 'cpromo67-x-0001' from public.market_promo_orders m limit 1 $$)
  like '%ad_payments_one_target5%' or not exists (select 1 from public.market_promo_orders), 'O7 a payment belongs to exactly one thing');

set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt67_b', (select id from t_pay), 'payment.succeeded', 6, 'AZN', null) = 'applied',
  'A1 İrəli çək payment succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt67_p', (select id from t_pay2), 'payment.succeeded', 20, 'AZN', null) = 'applied',
  'A2 Premium payment succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt67_f', (select id from t_pay3), 'payment.failed', 3, 'AZN', null) = 'applied',
  'A3 a failed payment');
reset role;

select tests.check((select bump_total = 3 and bump_start > now() - interval '1 minute' from public.cargo where id = :c1),
  'B1 İrəli çək: 3 lifts, the first at once');
select tests.check((select public.cargo_lifted_at(c) > now() - interval '1 minute' from public.cargo c where id = :c1),
  'B2 …so the load counts as just lifted');
select tests.check((select status = 'paid' from public.cargo_promo_orders where id = (select id from t_b)), 'B3 …and its order is paid');
select tests.check((select premium_until between now() + interval '4 days 23 hours' and now() + interval '5 days 1 hour'
                      and is_featured and featured_until >= premium_until and premium_since is not null and featured_since is not null
                      from public.cargo where id = :c2), 'B4 Premium for 5 days, VIP at least as long');
select tests.check((select status = 'pending_payment' from public.cargo_promo_orders where id = (select id from t_fail)),
  'B5 failed payment: the order stays unpaid');
select tests.check((select coalesce(bump_total, 0) = 0 from public.cargo where id = :c2), 'B6 …and gives no lift');

-- ---- lifts over time ----------------------------------------------------------
set local app.cargo_trusted = '1';
update public.cargo set bump_start = now() - interval '2 days 1 hour', bump_total = 5 where id = :c1;
select tests.check((select public.cargo_lifted_at(c) = c.bump_start + interval '2 days' from public.cargo c where id = :c1),
  'T1 a 5-lift pack, 2 days in: lifted 24 h apart (third lift)');
update public.cargo set bump_total = 2 where id = :c1;
select tests.check((select public.cargo_lifted_at(c) = c.bump_start + interval '1 day' from public.cargo c where id = :c1),
  'T2 a used-up pack lifts no more');
set local app.cargo_trusted = '';
select pg_temp.as_service();
update public.cargo set is_featured = true, featured_until = now() + interval '10 days' where id = :c4;
alter table public.cargo disable trigger zz_cargo_featured_since;
update public.cargo set featured_since = now() - interval '3 days 12 hours' where id = :c4;
select tests.check((select public.cargo_lifted_at(c) = c.featured_since + interval '3 days' from public.cargo c where id = :c4),
  'T3 VIP lifts once a day');
update public.cargo set featured_since = null where id = :c4;
alter table public.cargo enable trigger zz_cargo_featured_since;
select tests.check((select public.cargo_lifted_at(c) = c.created_at + interval '2 days' from public.cargo c where id = :c4),
  'T3b a VIP from before 0067 lifts daily from the time it was posted');

-- a running pack: the lifts left are kept when a new pack is bought
set local app.cargo_trusted = '1';
update public.cargo set bump_start = now() - interval '1 day 1 hour', bump_total = 5 where id = :c1;
set local app.cargo_trusted = '';
set role authenticated;
select tests.login(:owner);
create temp table t_b2 as select * from public.cargo_promo_order_create(:c1, 'bump', 1);
grant select on t_b2 to service_role;
reset role;
insert into public.ad_payments (cargo_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cpromo67-b-0002' from t_b2;
create temp table t_pay4 as select * from public.ad_payments where idempotency_key = 'cpromo67-b-0002';
grant select on t_pay4 to service_role;
set role service_role;
select pg_temp.as_service();
select public.finance_apply_provider_event('test', 'evt67_b2', (select id from t_pay4), 'payment.succeeded', 3, 'AZN', null);
reset role;
select tests.check((select bump_total = 4 from public.cargo where id = :c1),
  'T4 2 of 5 lifts used, 3 left + 1 bought = 4 (first at once)');

-- ---- reading ------------------------------------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check((select premium_until is not null from public.cargo where id = :c2), 'R1 everyone sees which load is Premium');
reset role;
set role anon;
select tests.check(tests.err($$ select public.cargo_promo_order_create('c6700000-0000-4000-8000-000000000001', 'bump', 1) $$)
  like '%permission denied%', 'R2 not for anon');
reset role;
select tests.summary('LOAD PROMOTIONS (0067)');
rollback;

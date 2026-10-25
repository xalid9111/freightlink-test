-- TIR BAZARI — 0066: İrəli çək, VIP daily lift, Premium. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set seller  '''a0000000-0000-4000-8000-000000000012'''
\set buyer   '''a0000000-0000-4000-8000-000000000021'''
\set p1 '''aa660000-0000-4000-8000-000000000001'''
\set p2 '''aa660000-0000-4000-8000-000000000002'''
\set p3 '''aa660000-0000-4000-8000-000000000003'''
\set p4 '''aa660000-0000-4000-8000-000000000004'''

begin;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 0, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}';

-- ---- prices ---------------------------------------------------------------
set role authenticated;
select tests.login(:buyer);
select tests.check((select string_agg(kind || qty || ':' || price::numeric(12,0), ',' order by kind, qty) from public.market_promo_plans)
  = 'bump1:3,bump3:6,bump5:9,bump10:15,premium1:7,premium5:20,premium15:45,premium30:60', 'P1 İrəli çək and Premium prices');
select tests.check((select string_agg(days || ':' || price::numeric(12,0), ',' order by days) from public.market_vip_plans where is_active)
  = '1:5,5:15,15:25,30:40', 'P2 VIP packs 1 / 5 / 15 / 30 days = 5 / 15 / 25 / 40 AZN');
select tests.check(tests.err($$ select public.admin_market_set_promo_plan('bump', 1, 1) $$) like '%admin_only%', 'P3 a user cannot change prices');
select tests.check(tests.err($$ update public.market_promo_plans set price = 1 $$) like '%permission denied%', 'P4 no direct writes');
select tests.login(:admin);
select tests.check((select price = 4 from public.admin_market_set_promo_plan('bump', 1, 4)), 'P5 admin changes a price');
select tests.check(tests.err($$ select public.admin_market_set_promo_plan('gold', 1, 4) $$) like '%invalid_kind%', 'P6 unknown kind refused');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'market.promo_plan'), 'P7 price changes are logged');
update public.market_promo_plans set price = 3 where kind = 'bump' and qty = 1;

-- ---- ads --------------------------------------------------------------------
set role authenticated;
select tests.login(:seller);
insert into public.market_listings (id, category, brand, model, price, currency, status)
values (:p1, 'truck', 'DAF', 'XF', 100, 'AZN', 'pending'),
       (:p2, 'truck', 'MAN', 'TGX', 100, 'AZN', 'pending'),
       (:p3, 'truck', 'Volvo', 'FH', 100, 'AZN', 'draft');
update public.market_listings set status = 'active' where id in (:p1, :p2);
update public.market_listings set premium_until = now() + interval '9 days', bump_total = 9, bump_start = now() where id = :p1;
select tests.check((select premium_until is null and bump_total is null from public.market_listings where id = :p1),
  'G1 an owner cannot give himself Premium or lifts');
reset role;
-- Test set-up as trusted server code (the owner guard keeps published_at).
set local app.market_trusted = '1';
update public.market_listings set published_at = now() - interval '3 days' where id = :p1;
update public.market_listings set published_at = now() - interval '1 day' where id = :p2;
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status, published_at)
values (:p4, :buyer, 'truck', 'Scania', 'R', 100, 'AZN', 'active', now() - interval '2 days');
set local app.market_trusted = '';

set role authenticated;
select tests.login(:buyer);
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'bump', 1) $$, :p1)) like '%listing_not_found%',
  'O1 only for my own ad');
select tests.login(:seller);
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'bump', 1) $$, :p3)) like '%listing_not_active%',
  'O2 only for an active ad');
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'bump', 2) $$, :p1)) like '%invalid_plan%',
  'O3 only a listed pack');
create temp table t_b as select * from public.market_promo_order_create(:p1, 'bump', 3);
create temp table t_pr as select * from public.market_promo_order_create(:p2, 'premium', 5);
create temp table t_fail as select * from public.market_promo_order_create(:p2, 'bump', 1);
select tests.check((select id from public.market_promo_order_create(:p1, 'bump', 3)) = (select id from t_b), 'O4 double tap = one order');
select tests.check((select amount = 6 and currency = 'AZN' from t_b), 'O5 the price comes from the server');
-- TEST mode: the checkout is open only to the finance owner (as VIP).
select tests.check(tests.err(format($$ select public.market_promo_payment_create(%L, 'card', 'promo66-x-0009') $$, (select id from t_b)))
  like '%payments_disabled%', 'O6 test mode: checkout closed for normal users (as VIP)');
grant select on t_b, t_pr, t_fail to service_role;
reset role;
-- LIVE mode: the owner's checkout works; the amount comes from the order.
update public.payment_settings set mode = 'live' where id = 1;
set role authenticated;
select tests.login(:seller);
create temp table t_live as select * from public.market_promo_payment_create((select id from t_pr), 'card', 'promo66-live-001');
select tests.check((select amount = 20 and mode = 'live' and market_promo_order_id = (select id from t_pr) from t_live),
  'O6b live checkout: amount from the order, linked to it');
reset role;
delete from public.ad_payments where idempotency_key = 'promo66-live-001';
update public.payment_settings set mode = 'test' where id = 1;
-- Test payments as the test provider makes them.
insert into public.ad_payments (market_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'promo66-b-0001' from t_b;
insert into public.ad_payments (market_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'promo66-p-0001' from t_pr;
insert into public.ad_payments (market_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'promo66-f-0001' from t_fail;
create temp table t_pay as select * from public.ad_payments where idempotency_key = 'promo66-b-0001';
create temp table t_pay2 as select * from public.ad_payments where idempotency_key = 'promo66-p-0001';
create temp table t_pay3 as select * from public.ad_payments where idempotency_key = 'promo66-f-0001';
grant select on t_pay, t_pay2, t_pay3 to service_role;
select tests.check(tests.err($$ insert into public.ad_payments (market_vip_order_id, market_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
  select v.id, (select id from t_b), v.user_id, 1, 'AZN', 'card', 'test', 'test', 'promo66-x-0001' from public.market_vip_orders v limit 1 $$)
  like '%ad_payments_one_target%' or not exists (select 1 from public.market_vip_orders), 'O7 a payment belongs to exactly one thing');

set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt66_b', (select id from t_pay), 'payment.succeeded', 6, 'AZN', null) = 'applied',
  'A1 İrəli çək payment succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt66_p', (select id from t_pay2), 'payment.succeeded', 20, 'AZN', null) = 'applied',
  'A2 Premium payment succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt66_f', (select id from t_pay3), 'payment.failed', 3, 'AZN', null) = 'applied',
  'A3 a failed payment');
reset role;

select tests.check((select bump_total = 3 and bump_start > now() - interval '1 minute' from public.market_listings where id = :p1),
  'B1 İrəli çək: 3 lifts, the first at once');
select tests.check((select public.market_lifted_at(l) > now() - interval '1 minute' from public.market_listings l where id = :p1),
  'B2 …so the ad counts as just lifted');
select tests.check((select status = 'paid' from public.market_promo_orders where id = (select id from t_b)), 'B3 …and its order is paid');
select tests.check((select premium_until between now() + interval '4 days 23 hours' and now() + interval '5 days 1 hour'
                      and is_vip and vip_until >= premium_until and premium_since is not null
                      from public.market_listings where id = :p2), 'B4 Premium for 5 days, VIP at least as long');
select tests.check((select status = 'pending_payment' from public.market_promo_orders where id = (select id from t_fail)),
  'B5 failed payment: the order stays unpaid');
select tests.check((select coalesce(bump_total, 0) = 0 from public.market_listings where id = :p2), 'B6 …and gives no lift');

-- ---- lifts over time ----------------------------------------------------------
set local app.market_trusted = '1';
update public.market_listings set bump_start = now() - interval '2 days 1 hour', bump_total = 5 where id = :p1;
select tests.check((select public.market_lifted_at(l) = l.bump_start + interval '2 days' from public.market_listings l where id = :p1),
  'T1 a 5-lift pack, 2 days in: lifted 24 h apart (third lift)');
update public.market_listings set bump_total = 2 where id = :p1;
select tests.check((select public.market_lifted_at(l) = l.bump_start + interval '1 day' from public.market_listings l where id = :p1),
  'T2 a used-up pack lifts no more');
set local app.market_trusted = '1';
update public.market_listings set is_vip = true, vip_until = now() + interval '10 days' where id = :p4;
alter table public.market_listings disable trigger zz_market_vip_since;
update public.market_listings set vip_since = now() - interval '3 days 12 hours' where id = :p4;
alter table public.market_listings enable trigger zz_market_vip_since;
set local app.market_trusted = '';
select tests.check((select public.market_lifted_at(l) = l.vip_since + interval '3 days' from public.market_listings l where id = :p4),
  'T3 VIP lifts once a day');

-- a running pack: the lifts left are kept when a new pack is bought
set local app.market_trusted = '1';
update public.market_listings set bump_start = now() - interval '1 day 1 hour', bump_total = 5 where id = :p1;
set local app.market_trusted = '';
set role authenticated;
select tests.login(:seller);
create temp table t_b2 as select * from public.market_promo_order_create(:p1, 'bump', 1);
grant select on t_b2 to service_role;
reset role;
insert into public.ad_payments (market_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'promo66-b-0002' from t_b2;
create temp table t_pay4 as select * from public.ad_payments where idempotency_key = 'promo66-b-0002';
grant select on t_pay4 to service_role;
set role service_role;
select pg_temp.as_service();
select public.finance_apply_provider_event('test', 'evt66_b2', (select id from t_pay4), 'payment.succeeded', 3, 'AZN', null);
reset role;
select tests.check((select bump_total = 4 from public.market_listings where id = :p1),
  'T4 2 of 5 lifts used, 3 left + 1 bought = 4 (first at once)');

-- ---- feed order ----------------------------------------------------------------
set role authenticated;
select tests.login(:buyer);
select tests.check((select array_agg(id order by ord) = array[:p1]::uuid[]
                      from (select id, row_number() over () ord from public.market_search(p_limit => 60)
                             where id in (:p1, :p2, :p4) and not public.market_vip_active(is_vip, vip_until)) x),
  'S1 the lifted ad is in the normal list');
select tests.check((select (array_agg(id))[1] = :p1 from public.market_search(p_limit => 60) where id in (:p1, :p3)),
  'S2 a lifted older ad comes before newer ones');
select tests.check((select array_agg(id) = array[:p2]::uuid[] from public.market_premium_latest(null, 12) where id in (:p1, :p2, :p4)),
  'S3 Premium list = the Premium ad');
select tests.check((select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'market_search'), 'S4 still one market_search');
select tests.check((select count(*) >= 1 from public.market_search(null, null, null, null, null, null, null, null, null, null, false, 20, 0)),
  'S5 the old 13-parameter call still works');
reset role;
set role anon;
select tests.check(tests.err($$ select * from public.market_premium_latest() $$) like '%permission denied%', 'S6 not for anon');
reset role;
select tests.summary('TIR BAZARI PROMOTIONS (0066)');
rollback;

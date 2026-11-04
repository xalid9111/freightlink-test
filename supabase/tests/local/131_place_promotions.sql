-- SERVİS / TIRPARK — 0093: İrəli çək · VIP · Premium (the Loads system). Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set svcown  '''a0000000-0000-4000-8000-000000000011'''
\set parkown '''a0000000-0000-4000-8000-000000000013'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set svc     '''5e000000-0000-4000-8000-000000000001'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
create or replace function pg_temp.state(p_target text, p_id uuid) returns jsonb language sql as $$
  select coalesce((select e from jsonb_array_elements(public.place_promo_state(p_target, array[p_id])) e limit 1), '{}'::jsonb);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 0, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}';
create temp table loads_before as
  select (select string_agg(kind || qty || ':' || price, ',' order by kind, qty) from public.cargo_promo_plans) promo,
         (select string_agg(days || ':' || price, ',' order by days) from public.cargo_vip_plans) vip,
         (select count(*) from public.ads) ads;

-- ---- prices: the same packs and prices as Loads -------------------------------
set role authenticated;
select tests.login(:other);
select tests.check((select string_agg(kind || qty || ':' || price, ',' order by kind, qty) from public.place_promo_plans where target = 'service' and kind <> 'vip')
  = (select string_agg(kind || qty || ':' || price, ',' order by kind, qty) from public.cargo_promo_plans),
  'P1 Servis: İrəli çək / Premium start from the Loads prices');
select tests.check((select string_agg(qty || ':' || price || ':' || is_active, ',' order by qty) from public.place_promo_plans where target = 'tirpark' and kind = 'vip')
  = (select string_agg(days || ':' || price || ':' || is_active, ',' order by days) from public.cargo_vip_plans),
  'P2 TIRPark: VIP packs (and their on / off) from the Loads VIP prices');
select tests.check((select currency from public.place_promo_plans where target = 'service' and kind = 'premium' and qty = 30) = 'AZN', 'P3 same currency');
select tests.check(tests.err($$ select public.admin_place_set_promo_plan('service', 'bump', 1, 1) $$) like '%admin_only%', 'P4 a user cannot change prices');
select tests.check(tests.err($$ update public.place_promo_plans set price = 1 $$) like '%permission denied%', 'P5 no direct writes');
select tests.login(:admin);
select tests.check((select price = 4 from public.admin_place_set_promo_plan('service', 'bump', 1, 4)), 'P6 the admin changes a Servis price');
select tests.check((select price from public.place_promo_plans where target = 'tirpark' and kind = 'bump' and qty = 1)
  = (select price from public.cargo_promo_plans where kind = 'bump' and qty = 1), 'P7 …TIRPark keeps its own price');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'place.promo_plan'), 'P8 price changes are logged');
select tests.check((select promo from loads_before) = (select string_agg(kind || qty || ':' || price, ',' order by kind, qty) from public.cargo_promo_plans)
               and (select vip from loads_before) = (select string_agg(days || ':' || price, ',' order by days) from public.cargo_vip_plans),
  'P9 the Loads prices are not touched');
update public.place_promo_plans set price = 3 where target = 'service' and kind = 'bump' and qty = 1;

-- ---- a park with an approved manager ----------------------------------------------
set role authenticated;
select tests.login(:parkown);
insert into ids values ('r', public.tir_park_owner_apply('Reklam Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:parkown);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.95, 46.75, null, 10, 3, '+994501112233'));

-- ---- owners cannot give themselves a promotion ---------------------------------------
select tests.login(:svcown);
update public.service_providers set promo_premium_until = now() + interval '9 days', promo_vip_until = now() + interval '9 days',
       name = 'Approved Garage 2' where id = :svc;
reset role;
select tests.check((select promo_premium_until is null and promo_vip_until is null and name = 'Approved Garage 2' from public.service_providers where id = :svc),
  'G1 a service owner cannot set his own promotion (other edits still work)');
update public.service_providers set name = 'Approved Garage' where id = :svc;

-- ---- orders -------------------------------------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'vip', 30) $$, :svc)) like '%not_found%',
  'O1 only for my own service');
select tests.check(tests.err(format($$ select public.place_promo_order_create('tirpark', %L, 'vip', 30) $$, (select id from ids where k='p'))) like '%not_found%',
  'O2 only for the park I manage');
select tests.login(:svcown);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'vip', 2) $$, :svc)) like '%invalid_plan%',
  'O3 only a listed pack');
reset role;
select lat as svc_lat, lng as svc_lng from public.service_providers where id = :svc \gset
set role authenticated;
select tests.login('a0000000-0000-4000-8000-000000000012');
select tests.check(tests.err($$ select public.place_promo_order_create('service', '5e000000-0000-4000-8000-000000000002', 'premium', 5) $$) like '%not_open%',
  'O4 a service not approved yet cannot be promoted');
reset role;
update public.service_providers set lat = 0, lng = 0 where id = :svc;
set role authenticated;
select tests.login(:svcown);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'bump', 3) $$, :svc)) like '%no_area%',
  'O4b a service without a real place on the map (0, 0) cannot be promoted');
reset role;
update public.service_providers set lat = :svc_lat, lng = :svc_lng where id = :svc;
set role authenticated;
select tests.login(:svcown);
create temp table t_sb as select * from public.place_promo_order_create('service', :svc, 'bump', 3);
create temp table t_sp as select * from public.place_promo_order_create('service', :svc, 'premium', 5);
select tests.check((select id from public.place_promo_order_create('service', :svc, 'bump', 3)) = (select id from t_sb), 'O5 double tap = one order');
select tests.check((select amount = 6 and currency = 'AZN' and target = 'service' and service_id = :svc from t_sb), 'O6 the price comes from the server');
select tests.check(tests.err(format($$ select public.place_promo_payment_create(%L, 'card', 'place93-x-0001') $$, (select id from t_sb)))
  like '%payments_disabled%', 'O7 test mode: checkout closed for normal users (as Loads)');
select tests.login(:parkown);
create temp table t_pv as select * from public.place_promo_order_create('tirpark', (select id from ids where k='p'), 'vip', 5);
select tests.check((select target = 'tirpark' and park_id = (select id from ids where k='p') and service_id is null from t_pv), 'O8 a park order');
grant select on t_sb, t_sp, t_pv to service_role;
reset role;
-- live checkout makes a payment linked to the order
update public.payment_settings set mode = 'live' where id = 1;
set role authenticated;
select tests.login(:svcown);
create temp table t_live as select * from public.place_promo_payment_create((select id from t_sp), 'card', 'place93-live-01');
select tests.check((select amount = 20 and mode = 'live' and place_promo_order_id = (select id from t_sp) from t_live),
  'O9 live checkout: amount from the order, linked to it');
reset role;
delete from public.ad_payments where idempotency_key = 'place93-live-01';  -- test row only (rolled back)
update public.payment_settings set mode = 'test' where id = 1;
insert into public.ad_payments (place_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :svcown, amount, currency, 'card', 'test', 'test', 'place93-sb-0001' from t_sb;
insert into public.ad_payments (place_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :svcown, amount, currency, 'card', 'test', 'test', 'place93-sp-0001' from t_sp;
insert into public.ad_payments (place_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :parkown, amount, currency, 'card', 'test', 'test', 'place93-pv-0001' from t_pv;
select tests.check(tests.err($$ insert into public.ad_payments (cargo_promo_order_id, place_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
  select c.id, (select id from t_sb), c.user_id, 1, 'AZN', 'card', 'test', 'test', 'place93-x-0002' from public.cargo_promo_orders c limit 1 $$)
  like '%ad_payments_one_target7%' or not exists (select 1 from public.cargo_promo_orders), 'O10 a payment belongs to exactly one thing');
create temp table t_pay as select id, idempotency_key, amount from public.ad_payments where idempotency_key like 'place93-%-0001';
grant select on t_pay to service_role;

-- ---- payments apply the orders ------------------------------------------------------
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt93_sb', (select id from t_pay where idempotency_key = 'place93-sb-0001'),
  'payment.succeeded', 6, 'AZN', null) = 'applied', 'A1 Servis İrəli çək paid');
select tests.check(public.finance_apply_provider_event('test', 'evt93_pv', (select id from t_pay where idempotency_key = 'place93-pv-0001'),
  'payment.failed', (select amount from t_pay where idempotency_key = 'place93-pv-0001'), 'AZN', null) = 'applied', 'A2 a failed park payment');
reset role;
select tests.check((select status = 'pending_payment' from public.place_promo_orders where id = (select id from t_pv)), 'A3 failed: the order stays unpaid');
set role authenticated;
select tests.login(:other);
select tests.check(pg_temp.state('tirpark', (select id from ids where k='p')) = '{}'::jsonb, 'A4 …and the park shows no promotion');
select tests.check((pg_temp.state('service', :svc) ->> 'bump_left')::int = 2 and (pg_temp.state('service', :svc) ->> 'lifted_at')::timestamptz > now() - interval '1 minute',
  'A5 İrəli çək: lifted now, 2 lifts left (map and list show it first)');
reset role;
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt93_sp', (select id from t_pay where idempotency_key = 'place93-sp-0001'),
  'payment.succeeded', 20, 'AZN', null) = 'applied', 'A6 Servis Premium paid');
reset role;
set role authenticated;
select tests.login(:other);
select tests.check((pg_temp.state('service', :svc) ->> 'premium_until')::timestamptz between now() + interval '4 days 23 hours' and now() + interval '5 days 1 hour'
               and (pg_temp.state('service', :svc) ->> 'vip_until')::timestamptz >= (pg_temp.state('service', :svc) ->> 'premium_until')::timestamptz,
  'A7 Premium 5 days, VIP at least as long (any signed-in viewer sees the marks)');
-- a park VIP (paid this time)
select tests.login(:parkown);
create temp table t_pv2 as select * from public.place_promo_order_create('tirpark', (select id from ids where k='p'), 'vip', 1);
grant select on t_pv2 to service_role;
reset role;
insert into public.ad_payments (place_promo_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :parkown, amount, currency, 'card', 'test', 'test', 'place93-pv-0002' from t_pv2;
create temp table t_pay2 as select id, amount from public.ad_payments where idempotency_key = 'place93-pv-0002';
grant select on t_pay2 to service_role;
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt93_pv2', (select id from t_pay2), 'payment.succeeded',
  (select amount from t_pay2), 'AZN', null) = 'applied', 'A8 TIRPark VIP paid');
reset role;
set role authenticated;
select tests.login(:parkown);
select tests.check((pg_temp.state('tirpark', (select id from ids where k='p')) ->> 'vip_until')::timestamptz between now() + interval '23 hours' and now() + interval '25 hours',
  'A9 the park owner sees his own VIP for 1 day');
select tests.check((select count(*) = 2 from public.place_promo_orders where user_id = :parkown and target = 'tirpark'), 'A10 …and his own orders');
select tests.login(:svcown);
select tests.check((select count(*) = 0 from public.place_promo_orders where target = 'tirpark'), 'A11 nobody reads another owner''s orders');
reset role;

-- ---- expiry (no job: from the time) ---------------------------------------------------
set local app.place_promo_trusted = '1';
update public.tir_parks set promo_vip_until = now() - interval '1 minute' where id = (select id from ids where k='p');
update public.service_providers set promo_premium_until = now() - interval '1 minute', promo_vip_until = now() - interval '1 minute',
       promo_bump_start = now() - interval '5 days', promo_bump_total = 3 where id = :svc;
set local app.place_promo_trusted = '';
set role authenticated;
select tests.login(:other);
select tests.check(pg_temp.state('tirpark', (select id from ids where k='p')) = '{}'::jsonb, 'E1 an ended VIP: the park is an ordinary park again');
select tests.check(pg_temp.state('service', :svc) = '{}'::jsonb, 'E2 ended Premium / VIP / a used-up pack: the service is ordinary again');
select tests.login(null);
select tests.check(tests.err($$ select public.place_promo_state('service', array['5e000000-0000-4000-8000-000000000001'::uuid]) $$) is not null,
  'E3 only for signed-in users');
reset role;

-- ---- never among the loads ---------------------------------------------------------------
select tests.check((select count(*) from public.ads) = (select ads from loads_before), 'L1 no banner is made: nothing shows among the loads');
select tests.summary('SERVİS / TIRPARK ÖNƏ ÇIXAR (0093)');

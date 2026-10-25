-- TIR BAZARI — 0044: admin banner, VIP prices, newest VIP, paid VIP.
-- Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set seller  '''a0000000-0000-4000-8000-000000000012'''
\set buyer   '''a0000000-0000-4000-8000-000000000021'''
\set l1 '''aa440000-0000-4000-8000-000000000001'''
\set l2 '''aa440000-0000-4000-8000-000000000002'''
\set l3 '''aa440000-0000-4000-8000-000000000003'''

begin;
-- 0066 changed the VIP packs (1 / 5 / 15 / 30 days); this suite checks
-- 0044's rules with 0044's own packs (rolled back with everything else).
delete from public.market_vip_plans where days not in (7, 14, 30);
update public.market_vip_plans set is_active = true, price = case days when 7 then 5 when 14 then 9 else 15 end;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---- banner ------------------------------------------------------------------
set role authenticated;
select tests.login(:buyer);
select tests.check(tests.err($$ select public.admin_market_set_hero('x', 'a', 'b', 'c') $$) like '%admin_only%',
  'H1 a normal user cannot change the banner');
select tests.check(tests.err($$ insert into public.market_hero (id, title) values (1, 'hack') $$) like '%permission denied%',
  'H2 nobody writes the banner table directly');
select tests.login(:admin);
select tests.check((select title = 'Etibarlı TIR-lar' and subtitle is null
                      from public.admin_market_set_hero('https://x/h.jpg', ' Etibarlı TIR-lar ', 'hər zaman yolunuzda', '  ')),
  'H3 admin saves picture and texts (trimmed, empty = default)');
select public.admin_market_set_hero('https://x/h2.jpg', 'A', 'B', 'C');
select tests.check((select count(*) = 1 and min(image_url) = 'https://x/h2.jpg' from public.market_hero), 'H4 one banner row, updated in place');
select tests.login(:buyer);
select tests.check((select title = 'A' from public.market_hero), 'H5 everybody signed in reads it');
reset role;
select tests.check((select count(*) >= 2 from public.admin_audit_log where action = 'market.hero'), 'H6 banner changes are logged');

-- ---- VIP prices ---------------------------------------------------------------
set role authenticated;
select tests.login(:buyer);
select tests.check((select string_agg(days || ':' || price::numeric(12,0), ',' order by days) = '7:5,14:9,30:15' from public.market_vip_plans),
  'V1 default prices 7 days 5, 14 days 9, 30 days 15 AZN');
select tests.check(tests.err($$ select public.admin_market_set_vip_plan(7, 1) $$) like '%admin_only%', 'V2 a normal user cannot change prices');
select tests.check(tests.err($$ update public.market_vip_plans set price = 1 $$) like '%permission denied%', 'V3 no direct writes');
select tests.login(:admin);
select tests.check((select price = 6 from public.admin_market_set_vip_plan(7, 6)), 'V4 admin changes the 7-day price');
select tests.check(tests.err($$ select public.admin_market_set_vip_plan(7, 0) $$) like '%invalid_price%', 'V5 price must be above 0');

-- ---- ads + newest VIP ---------------------------------------------------------------
select tests.login(:seller);
insert into public.market_listings (id, category, brand, model, price, currency, status, is_vip, vip_until)
values (:l1, 'truck', 'DAF', 'XF', 100, 'AZN', 'active', true, now() + interval '30 days'),
       (:l2, 'truck', 'MAN', 'TGX', 100, 'AZN', 'active', false, null),
       (:l3, 'truck', 'Volvo', 'FH', 100, 'AZN', 'draft', false, null);
select tests.check((select count(*) = 0 from public.market_listings where id in (:l1, :l2) and (is_vip or vip_since is not null)),
  'N1 a seller cannot make an ad VIP');
update public.market_listings set vip_since = now() where id = :l1;
select tests.check((select vip_since is null from public.market_listings where id = :l1), 'N2 nor set vip_since');
select tests.login(:admin);
select public.admin_market_set_vip(:l1, true, 7);
select pg_sleep(0.01);
select public.admin_market_set_vip(:l2, true, 7);
select tests.check((select array_agg(x.id order by x.ordinality) = array[:l2, :l1]::uuid[]
                      from public.market_vip_latest(null, 6) with ordinality x),
  'N3 newest VIP first');
select public.admin_market_set_vip(:l2, false);
select tests.check((select vip_since is null from public.market_listings where id = :l2), 'N4 VIP off clears vip_since');

-- ---- VIP order + payment ----------------------------------------------------
select tests.login(:buyer);
select tests.check(tests.err(format($$ select public.market_vip_order_create(%L, 7) $$, :l2)) like '%listing_not_found%',
  'O1 nobody can order VIP for someone else''s ad');
select tests.login(:seller);
select tests.check(tests.err(format($$ select public.market_vip_order_create(%L, 7) $$, :l3)) like '%listing_not_active%',
  'O2 only an active ad');
select tests.check(tests.err(format($$ select public.market_vip_order_create(%L, 10) $$, :l2)) like '%invalid_plan%',
  'O3 only an existing plan');
create temp table t_o1 as select * from public.market_vip_order_create(:l2, 14);
select tests.check((select amount = 9 and currency = 'AZN' and status = 'pending_payment' and days = 14 from t_o1),
  'O4 price comes from the plan on the server (14 days = 9 AZN)');
select tests.check((select id from public.market_vip_order_create(:l2, 14)) = (select id from t_o1),
  'O5 the same unpaid order is re-used (double click)');
select tests.check(tests.err(format($$ select public.market_vip_payment_create(%L, 'card', 'vip-key-0001') $$, (select id from t_o1))) like '%payments_disabled%',
  'O6 no checkout while payments are off');
select tests.check(tests.err($$ insert into public.market_vip_orders (listing_id, user_id, days, amount, currency) values ('aa440000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000012', 30, 0.01, 'AZN') $$) like '%permission denied%',
  'O7 orders are made only by the server function');
grant select on t_o1 to service_role;

-- LIVE (future): the provider's verified event makes the ad VIP.
reset role;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'live', 'payriff', 2.5, '{card}')
  on conflict (id) do update set mode = 'live', provider = 'payriff', methods = '{card}';
set role authenticated;
select tests.login(:seller);
create temp table t_p1 as select * from public.market_vip_payment_create((select id from t_o1), 'card', 'vip-key-0001');
grant select on t_p1 to service_role;
select tests.check((select amount = 9 and order_id is null and market_vip_order_id = (select id from t_o1) and status = 'created' from t_p1),
  'P1 VIP checkout for 9 AZN');
select tests.check((select id from public.market_vip_payment_create((select id from t_o1), 'card', 'vip-key-0002')) = (select id from t_p1),
  'P2 one open payment per VIP order');
select tests.login(:buyer);
select tests.check(tests.err(format($$ select public.market_vip_payment_create(%L, 'card', 'vip-key-0003') $$, (select id from t_o1))) like '%order_not_found%',
  'P3 nobody pays someone else''s VIP order');
reset role;
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('payriff', 'evt_vip_0', (select id from t_p1), 'payment.succeeded', 1, 'AZN', 'pr_v') = 'amount_mismatch',
  'P4 wrong amount refused');
select tests.check(public.finance_apply_provider_event('payriff', 'evt_vip_1', (select id from t_p1), 'payment.succeeded', 9, 'AZN', 'pr_v') = 'applied',
  'P5 verified LIVE event');
select tests.check(public.finance_apply_provider_event('payriff', 'evt_vip_1', (select id from t_p1), 'payment.succeeded', 9, 'AZN', 'pr_v') = 'duplicate',
  'P6 the same event twice changes nothing');
reset role;
select tests.check((select status = 'paid' and paid_at is not null from public.market_vip_orders where id = (select id from t_o1)),
  'P7 the VIP order is paid');
select tests.check((select is_vip and vip_since is not null and vip_until between now() + interval '13 days 23 hours' and now() + interval '14 days 1 hour'
                      from public.market_listings where id = :l2),
  'P8 the ad is VIP for 14 days, at the front of the VIP list');
select tests.check((select (array_agg(x.id order by x.ordinality))[1] = :l2 from public.market_vip_latest(null, 6) with ordinality x),
  'P9 newest VIP shown first');
select tests.check((select count(*) = 0 from public.ad_orders where payment_status = 'paid' and paid_at > now() - interval '1 minute'),
  'P10 no ad order was touched');

-- TEST mode payment: since 0054 it makes the ad VIP too (more in 92_*).
update public.payment_settings set mode = 'test', provider = 'test', methods = '{card}' where id = 1;
update public.market_listings set is_vip = false, vip_until = null where id = :l1;
set role authenticated;
select tests.login(:seller);
create temp table t_o2 as select * from public.market_vip_order_create(:l1, 7);
reset role;
select tests.check((select status = 'pending_payment' and amount = 6 from t_o2), 'T1 new 7-day order uses the new price (6)');
insert into public.ad_payments (market_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :seller, amount, currency, 'card', 'test', 'test', 'vip-test-0001' from t_o2;
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt_vip_t1',
  (select id from public.ad_payments where idempotency_key = 'vip-test-0001'), 'payment.succeeded', 6, 'AZN', null) = 'applied',
  'T2 test payment succeeded');
reset role;
select tests.check((select is_vip from public.market_listings where id = :l1), 'T3 (0054) a TEST payment makes the ad VIP too');
select tests.check(tests.err($$ insert into public.ad_payments (user_id, amount, currency, method, provider, mode, idempotency_key)
  values ('a0000000-0000-4000-8000-000000000012', 1, 'AZN', 'card', 'test', 'test', 'no-target-001') $$) like '%ad_payments_one_target%',
  'T4 a payment always belongs to exactly one order');

reset role;
select tests.summary('TIR BAZARI BANNER + PAID VIP (0044)');
rollback;

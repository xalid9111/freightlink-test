-- LOAD VIP BOUGHT BY ITS OWNER — 0062. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set c1 '''c6200000-0000-4000-8000-000000000001'''
\set c2 '''c6200000-0000-4000-8000-000000000002'''

begin;
-- 0067 changed the VIP packs (1 / 5 / 15 / 30 days); this suite checks
-- 0062's rules with 0062's own packs (rolled back with everything else).
delete from public.cargo_vip_plans where days not in (7, 14, 30);
update public.cargo_vip_plans set is_active = true, price = case days when 7 then 5 when 14 then 9 else 15 end;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 0, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}';

select tests.check((select count(*) = 3 and min(price) = 5 and max(price) = 15 from public.cargo_vip_plans), 'P1 prices 7 / 14 / 30 days = 5 / 9 / 15 AZN');

set role authenticated;
select tests.login(:owner);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date + 3),
       (:c2, :owner, 'Azerbaijan', 'Baku', 'Russia', 'Moscow', 20000, 1500, current_date + 3);
select tests.check(tests.err($$ update public.cargo_vip_plans set price = 1 $$) like '%permission denied%', 'P2 nobody changes a price directly');
select tests.check(tests.err($$ select public.admin_cargo_set_vip_plan(7, 1) $$) like '%admin_only%', 'P3 only an admin changes prices');
select tests.check(tests.err($$ update public.cargo set is_featured = true where id = 'c6200000-0000-4000-8000-000000000001' $$)
  like '%can only be changed by an admin%', 'P4 the owner still cannot switch VIP on himself (0006)');

create temp table t_o1 as select * from public.cargo_vip_order_create(:c1, 7);
create temp table t_o2 as select * from public.cargo_vip_order_create(:c2, 14);
grant select on t_o1, t_o2 to service_role;
select tests.check((select amount = 5 and currency = 'AZN' and status = 'pending_payment' from t_o1), 'O1 the order takes the plan price (5 AZN for 7 days)');
select tests.check((select id from public.cargo_vip_order_create(:c1, 7)) = (select id from t_o1), 'O2 a double tap re-uses the open order');
select tests.check(tests.err($$ select public.cargo_vip_order_create('c6200000-0000-4000-8000-000000000001', 3) $$) like '%invalid_plan%', 'O3 only offered plans');
-- TEST mode: the checkout is open only to the finance owner (0037), as in
-- TIR Bazarı — a normal user cannot make test VIP for free.
select tests.check(tests.err($$ select public.cargo_vip_payment_create((select id from t_o1), 'card', 'cvip62-x-0002') $$) like '%payments_disabled%',
  'O4 test mode: checkout closed for normal users (as TIR Bazarı)');

select tests.login(:other);
select tests.check(tests.err($$ select public.cargo_vip_order_create('c6200000-0000-4000-8000-000000000001', 7) $$) like '%cargo_not_found%', 'O5 nobody orders VIP for another user''s load');
select tests.check(tests.err($$ select public.cargo_vip_payment_create((select id from t_o1), 'card', 'cvip62-x-0001') $$) similar to '%(order_not_found|payments_disabled)%',
  'O6 …nor pays his order');
reset role;
-- LIVE mode: the owner's checkout works; amount comes from the order.
update public.payment_settings set mode = 'live' where id = 1;
set role authenticated;
select tests.login(:owner);
create temp table t_live as select * from public.cargo_vip_payment_create((select id from t_o1), 'card', 'cvip62-live-001');
select tests.check((select amount = 5 and mode = 'live' and cargo_vip_order_id = (select id from t_o1) and order_id is null from t_live),
  'O4b live checkout: amount from the order, linked to the load VIP order');
reset role;
delete from public.ad_payments where idempotency_key = 'cvip62-live-001';  -- test row only (rolled back)
update public.payment_settings set mode = 'test' where id = 1;
create temp table t_p1 as select * from public.ad_payments where false;
insert into public.ad_payments (cargo_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cvip62-ok-0001' from t_o1;
insert into t_p1 select * from public.ad_payments where idempotency_key = 'cvip62-ok-0001';
grant select on t_p1 to service_role;
insert into public.ad_payments (cargo_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cvip62-no-0001' from t_o2;
insert into public.ad_orders (id, advertiser_id, package_name, days, price, currency, title)
values ('e0620000-0000-4000-8000-000000000001', :owner, '5 gün', 5, 20.00, 'AZN', 'TEST AD 62');
select tests.check(tests.err($$ insert into public.ad_payments (order_id, cargo_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
  select 'e0620000-0000-4000-8000-000000000001', id, 'a0000000-0000-4000-8000-000000000012', amount, currency, 'card', 'test', 'test', 'cvip62-two-001' from t_o2 $$)
  like '%ad_payments_one_target%', 'O7 a payment belongs to exactly one thing');

set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt62_ok', (select id from t_p1), 'payment.succeeded', 5, 'AZN', null) = 'applied',
  'A1 test payment succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt62_no', (select id from public.ad_payments where idempotency_key = 'cvip62-no-0001'),
  'payment.failed', 9, 'AZN', null) = 'applied', 'A2 test payment failed');
select tests.check(public.finance_apply_provider_event('test', 'evt62_ok', (select id from t_p1), 'payment.succeeded', 5, 'AZN', null) = 'duplicate',
  'A3 the same event twice is ignored');
reset role;

select tests.check((select is_featured and featured_until between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
                      from public.cargo where id = :c1), 'B1 successful payment: the load is VIP for 7 days');
select tests.check((select status = 'paid' and paid_at is not null from public.cargo_vip_orders where id = (select id from t_o1)), 'B2 …and its order is paid');
select tests.check((select not is_featured and featured_until is null from public.cargo where id = :c2), 'B3 failed payment: no VIP');
select tests.check((select status = 'pending_payment' from public.cargo_vip_orders where id = (select id from t_o2)), 'B4 …and the order stays unpaid');
select tests.check((select count(*) = 1 from public.ad_payments where id = (select id from t_p1) and mode = 'test' and status = 'succeeded'),
  'B5 the payment stays marked TEST (not income)');

-- A second 7 days are added to a VIP that is still running.
set role authenticated;
select tests.login(:owner);
create temp table t_o3 as select * from public.cargo_vip_order_create(:c1, 7);
reset role;
create temp table t_p3 as select * from public.ad_payments where false;
insert into public.ad_payments (cargo_vip_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :owner, amount, currency, 'card', 'test', 'test', 'cvip62-ok-0002' from t_o3;
insert into t_p3 select * from public.ad_payments where idempotency_key = 'cvip62-ok-0002';
grant select on t_o3, t_p3 to service_role;
set role service_role;
select pg_temp.as_service();
select public.finance_apply_provider_event('test', 'evt62_ok2', (select id from t_p3), 'payment.succeeded', 5, 'AZN', null);
reset role;
select tests.check((select featured_until between now() + interval '13 days 23 hours' and now() + interval '14 days 1 hour' from public.cargo where id = :c1),
  'B6 buying again adds the days to the running VIP');

select tests.login(:admin);
select tests.check((select price = 6 from public.admin_cargo_set_vip_plan(7, 6)), 'C1 the admin changes a price (logged)');
select tests.summary('LOAD VIP BOUGHT BY ITS OWNER (0062)');
rollback;

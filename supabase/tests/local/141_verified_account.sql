-- TƏSDİQLƏNMİŞ HESAB — 0104: the paid subscription (LIVE only) and the Baş
-- admin's own grant, kept apart; nobody else gives the badge. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set user1   '''a0000000-0000-4000-8000-000000000011'''
\set user2   '''a0000000-0000-4000-8000-000000000012'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set chief   '''a0000000-0000-4000-8000-0000000000f1'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder","role":"cargo_owner"}')
  on conflict (id) do nothing;
update public.users set role = 'admin' where id = :chief;
select public.founder_sync();
update public.users set is_verified = false where id in (:user1, :user2, :other);
create temp table t (k text primary key, id uuid) on commit drop;
grant all on t to authenticated, service_role;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 0, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}';

-- ---- passive offer -------------------------------------------------------------
set role authenticated;
select tests.login(:user1);
select tests.check((select price = 20 and currency = 'AZN' and is_active from public.verified_plans where months = 1), 'P1 the plan: 20 AZN a month');
select tests.check((public.account_verification() ->> 'verified')::boolean = false
                   and (public.account_verification() ->> 'granted')::boolean = false
                   and (public.account_verification() ->> 'paid')::boolean = false, 'P2 not verified yet: the offer is shown');
insert into t select 'o1', id from public.verified_order_create();
select tests.check((select amount = 20 and currency = 'AZN' and status = 'pending_payment' and user_id = :user1 from public.verified_orders where id = (select id from t where k = 'o1')),
  'P3 the order: the server''s price');
select tests.check((select id from public.verified_order_create(1)) = (select id from t where k = 'o1'), 'P4 a double tap = one order');
select tests.check(tests.err($$ select public.verified_order_create(7) $$) like '%invalid_plan%', 'P5 only a listed plan');
select tests.check(tests.err(format($$ select public.verified_payment_create(%L, 'card', 'verif-test-0001') $$, (select id from t where k = 'o1')))
  similar to '%(payments_disabled|payments_not_live)%', 'P6 no checkout while the shop is not live');
select tests.check(tests.err($$ insert into public.verified_subscriptions (user_id, paid_until) values (auth.uid(), now() + interval '1 year') $$)
  like '%permission denied%', 'P7 nobody writes his own subscription');

-- A TEST payment never activates it (no made-up activation).
reset role;
insert into public.ad_payments (verified_order_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :user1, 20, 'AZN', 'card', 'test', 'test', 'verif-test-0002' from t where k = 'o1';
insert into t select 'p-test', id from public.ad_payments where idempotency_key = 'verif-test-0002';
select pg_temp.as_service();
set role service_role;
select tests.check(public.finance_apply_provider_event('test', 'evt104_test', (select id from t where k = 'p-test'), 'payment.succeeded', 20, 'AZN', null) = 'applied',
  'T1 the test payment itself is recorded');
reset role;
select tests.check(not exists (select 1 from public.verified_subscriptions where user_id = :user1)
                   and (select status = 'pending_payment' from public.verified_orders where id = (select id from t where k = 'o1')),
  'T2 …but the badge is NOT activated by a test payment');

-- ---- paid, active (a verified LIVE payment) ----------------------------------------
update public.payment_settings set mode = 'live', provider = 'epoint' where id = 1;
set role authenticated;
select tests.login(:user1);
insert into t select 'p-live', id from public.verified_payment_create((select id from t where k = 'o1'), 'card', 'verif-live-0001');
select tests.check((select amount = 20 and mode = 'live' and verified_order_id = (select id from t where k = 'o1') from public.ad_payments where id = (select id from t where k = 'p-live')),
  'L1 live checkout: the amount from the order, linked to it');
reset role;
select pg_temp.as_service();
set role service_role;
select tests.check(public.finance_apply_provider_event('epoint', 'evt104_live', (select id from t where k = 'p-live'), 'payment.succeeded', 20, 'AZN', null) = 'applied',
  'L2 a verified live payment');
reset role;
select tests.check((select paid_until > now() + interval '27 days' and paid_until < now() + interval '32 days' from public.verified_subscriptions where user_id = :user1),
  'L3 subscribed for one month');
select tests.check((select is_verified = false from public.users where id = :user1), 'L4 the paid status is kept apart from the Baş admin''s grant');
set role authenticated;
select tests.login(:user1);
select tests.check((public.account_verification() ->> 'verified')::boolean and (public.account_verification() ->> 'paid')::boolean
                   and not (public.account_verification() ->> 'granted')::boolean
                   and (public.account_verification() ->> 'paid_until') is not null, 'L5 active: verified by the subscription');
select tests.login(:other);
select tests.check((public.account_verification(:user1) ->> 'verified')::boolean and (public.account_verification(:user1) ->> 'paid_until') is null,
  'L6 others see the badge, not the end date');
reset role;
update public.payment_settings set mode = 'test', provider = 'test' where id = 1;

-- ---- unauthorised attempts ------------------------------------------------------------
set role authenticated;
select tests.login(:admin);
select tests.check(not public.is_chief_admin(), 'U1 an ordinary admin is not the Baş admin');
select tests.check(tests.err(format($$ select public.admin_set_account_verified(%L, true) $$, :user2)) like '%chief_admin_only%',
  'U2 an ordinary admin cannot give the badge (RPC)');
select tests.check(tests.err(format($$ select public.admin_update_user(%L, '{"is_verified": true}'::jsonb) $$, :user2)) like '%chief_admin_only%',
  'U3 …nor through the old "edit user" call');
select tests.check(tests.err(format($$ update public.users set is_verified = true where id = %L $$, :user2)) like '%chief_admin_only%',
  'U4 …nor with a direct API update');
select tests.check((select count(*) = 1 from public.admin_update_user(:user2, '{"full_name": "Renamed by admin"}'::jsonb)), 'U5 other admin edits still work');
select tests.login(:user2);
update public.users set is_verified = true where id = :user2;
select tests.check(tests.err($$ select public.admin_set_account_verified(auth.uid(), true) $$) like '%chief_admin_only%', 'U6 the user cannot give it to himself (RPC)');
reset role;
select tests.check((select is_verified = false and full_name = 'Renamed by admin' from public.users where id = :user2), 'U7 …nor by updating his row: still not verified');

-- ---- the Baş admin's own grant ------------------------------------------------------------
set role authenticated;
select tests.login(:chief);
select tests.check(public.is_chief_admin(), 'G1 the Founder (admin) is the Baş admin');
select public.admin_set_account_verified(:user2, true);
select tests.check((public.account_verification(:user2) ->> 'granted')::boolean and not (public.account_verification(:user2) ->> 'paid')::boolean
                   and (public.account_verification(:user2) ->> 'verified')::boolean, 'G2 granted without payment, shown apart from a subscription');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'user.verified_grant' and entity_id = :user2::text), 'G3 the grant is in the Audit Log');
set role authenticated;
select tests.login(:chief);
select public.admin_set_account_verified(:user2, false);
select tests.check(not (public.account_verification(:user2) ->> 'verified')::boolean, 'G4 the Baş admin takes it back');
reset role;
update public.users set is_verified = true where id = :other;
select tests.check((select is_verified from public.users where id = :other), 'G5 the SQL editor (no signed-in user) stays trusted');
select tests.summary('TƏSDİQLƏNMİŞ HESAB (0104)');
rollback;

-- FINANCE & PAYMENTS — 0037. Rolled back at the end.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set owner  '''a0000000-0000-4000-8000-0000000000f1'''
\set fake   '''a0000000-0000-4000-8000-0000000000f2'''

begin;
reset role;
-- The finance owner signs up (signup trigger builds public.users), becomes
-- admin; a second account with a look-alike e-mail stays a normal user.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :owner, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Finance Owner","role":"cargo_owner"}'),
  ('00000000-0000-0000-0000-000000000000', :fake,  'authenticated', 'authenticated', 'xelilov.1881@gmail.co',  '{"full_name":"Look alike","role":"cargo_owner"}');
select tests.check(public.finance_sync_owner() = 0, 'F0 not an admin yet → not bound');
update public.users set role = 'admin' where id in (:owner, :fake);
select tests.check(public.finance_sync_owner() = 1, 'F1 owner bound by e-mail + admin role (only the exact e-mail)');
select tests.check(public.finance_sync_owner() = 0, 'F1b re-run binds nothing twice');

-- orders: one for the owner, one for another customer
insert into public.ad_orders (id, advertiser_id, package_name, days, price, currency, title) values
  ('e0000000-0000-4000-8000-000000000001', :owner, '5 gün', 5, 20.00, 'AZN', 'OWNER AD'),
  ('e0000000-0000-4000-8000-000000000002', :other, '5 gün', 5, 50.00, 'AZN', 'OTHER AD'),
  ('e0000000-0000-4000-8000-000000000003', :owner, '15 gün', 15, 45.50, 'AZN', 'OWNER AD 2');

create or replace function pg_temp.fresh() returns void language sql as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated',
                       'amr', jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint)))::text, false);
$$;
create or replace function pg_temp.stale() returns void language sql as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', current_setting('request.jwt.claim.sub'), 'role', 'authenticated',
                       'amr', jsonb_build_array(jsonb_build_object('method', 'password', 'timestamp', extract(epoch from now())::bigint - 3600)))::text, false);
$$;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

set role authenticated;
-- ---- access ----------------------------------------------------------
select tests.login(:owner);
select tests.check(public.is_finance_admin(), 'A1 owner is the finance admin');
select tests.login(:admin);
select tests.check(not public.is_finance_admin(), 'A2 another admin is NOT');
select tests.check(tests.err($$ select public.finance_summary('test') $$) like '%not_authorized%', 'A3 another admin cannot read the dashboard');
select tests.check(tests.err($$ select * from public.payout_accounts $$) like '%permission denied%', 'A4 nobody reads payout accounts directly');
select tests.check(tests.err($$ select * from public.payment_settings $$) like '%permission denied%', 'A5 settings table closed');
select tests.login(:fake);
select tests.check(not public.is_finance_admin(), 'A6 look-alike e-mail admin is NOT the finance admin');
select tests.login(:other);
select tests.check(tests.err($$ select public.finance_payments('test') $$) like '%not_authorized%', 'A7 customer cannot list ad_payments');
select tests.check((public.payment_checkout_available() ->> 'available')::boolean = false, 'A8 checkout is OFF by default');
reset role;
set role anon;
select tests.login(null);
select tests.check(tests.err($$ select public.finance_summary('test') $$) like '%permission denied%', 'A9 anonymous: no access');
reset role;

-- ---- settings + extra authentication --------------------------------------
set role authenticated;
select tests.login(:owner);
select pg_temp.stale();
select tests.check(tests.err($$ select public.finance_set_settings('test', 'test', 2.5, '{card,apple_pay,google_pay}') $$) like '%reauth_required%',
  'S1 settings need a fresh sign-in');
select pg_temp.fresh();
select tests.check(tests.err($$ select public.finance_set_settings('live', 'payriff', 2.5, '{card}') $$) like '%live_not_enabled%',
  'S2 LIVE cannot be switched on in this version');
select tests.check(tests.err($$ select public.finance_set_settings('test', 'payriff', 2.5, '{card}') $$) like '%provider_not_configured%',
  'S3 test mode only with the built-in test provider');
select tests.check(tests.err($$ select public.finance_set_settings('test', 'test', 2.5, '{card,bitcoin}') $$) like '%invalid_methods%',
  'S4 unknown method refused');
select tests.check((public.finance_set_settings('test', 'test', 2.5, '{card,apple_pay,google_pay}') ->> 'mode') = 'test',
  'S5 owner switches TEST mode on (2.5% commission)');

-- ---- checkout --------------------------------------------------------------
select tests.check((public.payment_checkout_available() ->> 'available')::boolean, 'C1 TEST checkout open for the owner');
select tests.login(:other);
select tests.check((public.payment_checkout_available() ->> 'available')::boolean = false, 'C2 customers never see TEST checkout');
select tests.check(tests.err($$ select public.payment_create('e0000000-0000-4000-8000-000000000002', 'card', 'key-other-0001') $$) like '%payments_disabled%',
  'C3 customer cannot start a TEST payment');
select tests.login(:owner);
create temp table t_p1 as select * from public.payment_create('e0000000-0000-4000-8000-000000000001', 'apple_pay', 'key-owner-0001');
select tests.check((select amount = 20.00 and currency = 'AZN' and mode = 'test' and provider = 'test' and status = 'created'
                           and commission = 0.50 from t_p1), 'C4 amount from the order on the server (20 AZN, 2.5% = 0.50)');
select tests.check((select id from public.payment_create('e0000000-0000-4000-8000-000000000001', 'apple_pay', 'key-owner-0001')) = (select id from t_p1),
  'C5 double click (same key) → same payment');
select tests.check((select id from public.payment_create('e0000000-0000-4000-8000-000000000001', 'card', 'key-owner-0002')) = (select id from t_p1),
  'C6 second checkout for the same order re-uses the open one');
select tests.check((select count(*) = 1 from public.ad_payments where order_id = 'e0000000-0000-4000-8000-000000000001'),
  'C7 still exactly one payment row');
select tests.check(tests.err($$ select public.payment_create('e0000000-0000-4000-8000-000000000002', 'card', 'key-owner-0003') $$) like '%order_not_found%',
  'C8 cannot pay someone else''s order');
select tests.check(tests.err($$ select public.payment_create('e0000000-0000-4000-8000-000000000003', 'card', 'x') $$) like '%invalid_idempotency_key%',
  'C9 idempotency key required');
select tests.check(tests.err($$ update public.ad_payments set status = 'succeeded' $$) like '%permission denied%',
  'C10 the app cannot mark a payment paid');
select tests.check(tests.err($$ select public.finance_apply_provider_event('test', 'evt_x', (select id from t_p1), 'payment.succeeded', 20, 'AZN', null) $$) like '%permission denied%',
  'C11 the app cannot call the provider-event function');
grant select on t_p1 to service_role;
reset role;

-- ---- provider events (Edge Function = service role) -----------------------
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt_1', (select id from t_p1), 'payment.succeeded', 25, 'AZN', 'test_ref') = 'amount_mismatch',
  'W1 wrong amount is rejected');
select tests.check((select status = 'created' from public.ad_payments where id = (select id from t_p1)), 'W2 …payment unchanged');
select tests.check(public.finance_apply_provider_event('payriff', 'evt_2', (select id from t_p1), 'payment.succeeded', 20, 'AZN', 'x') = 'provider_mismatch',
  'W3 another provider cannot confirm it');
select tests.check(public.finance_apply_provider_event('test', 'evt_3', (select id from t_p1), 'payment.succeeded', 20.00, 'azn', 'test_ref') = 'applied',
  'W4 verified event confirms the TEST payment');
select tests.check(public.finance_apply_provider_event('test', 'evt_3', (select id from t_p1), 'payment.succeeded', 20.00, 'AZN', 'test_ref') = 'duplicate',
  'W5 same event again → duplicate (idempotent)');
select tests.check(public.finance_apply_provider_event('test', 'evt_4', (select id from t_p1), 'payment.failed', 20.00, 'AZN', 'test_ref') = 'already_final',
  'W6 a later event cannot change a final payment');
select tests.check((select status = 'succeeded' and confirmed_at is not null from public.ad_payments where id = (select id from t_p1)), 'W7 payment succeeded');
select tests.check((select payment_status = 'unpaid' and status = 'pending_payment' from public.ad_orders where id = 'e0000000-0000-4000-8000-000000000001'),
  'W8 TEST payment never marks the order as paid');
reset role;

set role authenticated;
select tests.login(:owner);
select pg_temp.fresh();
select tests.check(tests.err($$ select public.payment_create('e0000000-0000-4000-8000-000000000001', 'card', 'key-owner-0004') $$) like '%already_paid%',
  'W9 an order paid in this mode cannot be paid again');
create temp table t_p2 as select * from public.payment_create('e0000000-0000-4000-8000-000000000003', 'card', 'key-owner-0005');
select tests.check((select status = 'cancelled' from public.payment_cancel((select id from t_p2))), 'W10 checkout can be cancelled');
select tests.check((select id from public.payment_create('e0000000-0000-4000-8000-000000000003', 'google_pay', 'key-owner-0006')) <> (select id from t_p2),
  'W11 after cancelling a new checkout can start');

-- ---- dashboard ----------------------------------------------------------------
create temp table t_s as select public.finance_summary('test') s;
select tests.check((select (s ->> 'gross')::numeric = 20 and (s ->> 'commission')::numeric = 0.5
                           and (s ->> 'confirmed_balance')::numeric = 19.5 and (s ->> 'pending')::numeric = 45.5
                           and (s ->> 'withdrawable')::numeric = 19.5 and (s ->> 'transferred')::numeric = 0 from t_s),
  'D1 totals: gross 20, commission 0.5, balance 19.5, pending 45.5');
select tests.check((select (public.finance_summary('live') ->> 'gross')::numeric = 0), 'D2 LIVE totals are separate from TEST');
select tests.check((select jsonb_array_length(public.finance_payments('test')) = 3), 'D3 history lists all TEST ad_payments');
select tests.check((select jsonb_array_length(public.finance_payments('test', 'succeeded')) = 1
                       and public.finance_payments('test', 'succeeded') -> 0 ->> 'order_title' = 'OWNER AD'), 'D4 filter by status + order shown');
select tests.check((select jsonb_array_length(public.finance_payments('test', null, null, null, 'OWNER AD 2')) = 2), 'D5 search by order title');

-- ---- payout accounts ----------------------------------------------------------
select pg_temp.stale();
select tests.check(tests.err($$ select public.finance_add_payout_account('card', 'Owner', 'Kapital', '1234', 'visa') $$) like '%reauth_required%',
  'B1 adding an account needs a fresh sign-in');
select pg_temp.fresh();
select tests.check(jsonb_array_length(public.finance_list_payout_accounts()) = 0, 'B2 no account yet is a normal state');
create temp table t_a1 as select public.finance_add_payout_account('card', 'Owner Name', 'Kapital Bank', '1234', 'visa') j;
select tests.check((select j ->> 'status' = 'pending_verification' and (j ->> 'is_primary')::boolean from t_a1),
  'B3 card added as PENDING verification (not activated), first one is primary');
select tests.check(tests.err($$ select public.finance_add_payout_account('card', 'Owner', null, '4111111111111111', 'visa') $$) like '%invalid_account%',
  'B4 a full card number is never accepted/stored');
select tests.check(tests.err($$ select public.finance_add_payout_account('business', 'Owner', 'PASHA', null, null, 'FL MMC', '12345', 'AZ21NABZ00000000137010001944') $$) like '%invalid_account%',
  'B5 VÖEN must be 10 digits');
create temp table t_a2 as select public.finance_add_payout_account('business', 'Owner', 'PASHA Bank', null, null, 'FreightLink MMC', '1234567890', 'az21 nabz 0000 0000 1370 1000 1944') j;
select tests.check((select j ->> 'iban_masked' = 'AZ21 •••• 1944' and not (j ->> 'is_primary')::boolean and j ->> 'status' = 'pending_verification' from t_a2),
  'B6 business account: IBAN shown masked, not primary');
select tests.check((select public.finance_list_payout_accounts()::text not like '%AZ21NABZ00000000137010001944%'), 'B7 full IBAN never returned');
select tests.check((select bool_and((x ->> 'is_primary')::boolean = (x ->> 'id' = (select j ->> 'id' from t_a2)))
                      from jsonb_array_elements(public.finance_set_primary_payout_account((select (j ->> 'id')::uuid from t_a2))) x),
  'B8 switch the primary account');
select tests.check((select (x ->> 'status') = 'disabled' and not (x ->> 'is_primary')::boolean
                      from jsonb_array_elements(public.finance_disable_payout_account((select (j ->> 'id')::uuid from t_a2))) x
                     where x ->> 'id' = (select j ->> 'id' from t_a2)), 'B9 old account can be deactivated');
select tests.check(tests.err($$ select public.finance_request_payout(10) $$) like '%payouts_need_live_provider%',
  'B10 no withdrawal without a live provider (nothing faked)');
select tests.login(:admin);
select pg_temp.fresh();
select tests.check(tests.err($$ select public.finance_add_payout_account('card', 'X', null, '9999', 'visa') $$) like '%not_authorized%',
  'B11 another admin cannot add accounts');

-- ---- audit -----------------------------------------------------------------------
select tests.login(:owner);
select tests.check((select count(*) >= 8 from public.finance_audit), 'L1 finance actions are in the audit log');
select tests.login(:admin);
select tests.check((select count(*) = 0 from public.finance_audit), 'L2 others see no audit rows');
reset role;
select tests.check(tests.err($$ update public.finance_audit set action = 'x' $$) like '%append_only%', 'L3 audit log cannot be changed');
select tests.check(tests.err($$ delete from public.finance_audit $$) like '%append_only%', 'L4 audit log cannot be deleted');

-- ---- LIVE path (future): only a verified provider event marks the order paid ----
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'live', 'payriff', 2.5, '{card}')
  on conflict (id) do update set mode = 'live', provider = 'payriff', methods = '{card}';
set role authenticated;
select tests.login(:other);
select tests.check((public.payment_checkout_available() ->> 'available')::boolean, 'P1 LIVE: customers can pay');
create temp table t_p3 as select * from public.payment_create('e0000000-0000-4000-8000-000000000002', 'card', 'key-other-0002');
grant select on t_p3 to service_role;
select tests.check((select mode = 'live' and provider = 'payriff' and amount = 50 from t_p3), 'P2 LIVE payment for 50 AZN');
select tests.check((select count(*) = 1 from public.ad_payments), 'P3 customer sees only own ad_payments');
reset role;
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt_live_fake', (select id from t_p3), 'payment.succeeded', 50, 'AZN', null) = 'provider_mismatch',
  'P4 the TEST provider can never confirm a LIVE payment');
select tests.check(public.finance_apply_provider_event('payriff', 'evt_live_1', (select id from t_p3), 'payment.succeeded', 50, 'AZN', 'pr_123') = 'applied',
  'P5 verified LIVE event');
reset role;
select tests.check((select payment_status = 'paid' and status = 'awaiting_approval' and paid_at is not null from public.ad_orders where id = 'e0000000-0000-4000-8000-000000000002'),
  'P6 LIVE success → order paid, waiting for the admin''s content review');
update public.ad_orders set creative = '{"version":2,"image_url":"https://x/a.png"}'::jsonb where id in ('e0000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-000000000003');
set role authenticated;
select tests.login(:admin);
select tests.check((select status = 'active' from public.admin_review_ad_order('e0000000-0000-4000-8000-000000000002', true)),
  'P7 admin can approve a card-paid order without a receipt');
select tests.check(tests.err($$ select public.admin_review_ad_order('e0000000-0000-4000-8000-000000000003', true) $$) like '%invalid_order_state%',
  'P8 an unpaid order without a receipt still cannot be approved');
reset role;

select tests.summary('FINANCE & PAYMENTS (0037)');
rollback;

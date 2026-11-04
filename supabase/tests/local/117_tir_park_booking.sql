-- TIR park management and paid booking — 0079. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set manager '''a0000000-0000-4000-8000-000000000012'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''

begin;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'test', 'test', 10, '{card}')
  on conflict (id) do update set mode = 'test', provider = 'test', methods = '{card}', commission_pct = 10;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;

-- ---- applying to manage a park ---------------------------------------------
set role authenticated;
select tests.login(:manager);
insert into ids values ('p', public.tir_park_manage_apply(null, 'Utep TIR Parkı', 40.4560, 49.7300, 'Xırdalan', 'M1 yolu 12',
  '+994501234567', array['secure', '24_7'], 20, 2, 5, 'hour', '24/7', null));
select tests.check((select status = 'pending' and manager_status = 'pending' and manager_id = :manager and capacity = 20 and bookable = 2
                    from public.tir_parks where id = (select id from ids where k='p')), 'M1 the application is a pending park with its data');
select tests.check(tests.err($$ select public.tir_park_manage_apply(null, 'X', 40.4560, 49.7300, null, null, '+994501234567', '{}', 20, 30, 5, 'hour', null) $$)
  like '%invalid_argument%', 'M2 free places cannot be more than the capacity');
update public.tir_parks set manager_status = 'approved', bookable = 999, price = 0.01 where id = (select id from ids where k='p');
select tests.check((select manager_status = 'pending' and bookable = 2 and price = 5 from public.tir_parks where id = (select id from ids where k='p')),
  'M3 nobody approves himself or changes the booking fields by hand');
select tests.check(tests.err($$ select public.tir_park_manager_update((select id from ids where k='p'), 20, 3, 5, 'hour', null, '+994501234567', true) $$)
  like '%not_allowed%', 'M4 no managing before the admin approves');
select tests.check(tests.err($$ select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved') $$) like '%admin_only%',
  'M5 only an admin approves');

select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now() + interval '1 hour', now() + interval '3 hours', 1) $$)
  like '%not_bookable%', 'B0 an unapproved park cannot be booked');

select tests.login(:admin);
select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved');
select tests.check((select status = 'approved' and manager_status = 'approved' from public.tir_parks where id = (select id from ids where k='p')),
  'M6 the admin approves the manager (and the new park)');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'tir_park.manager_approved'), 'M7 logged');
-- Since 0080 a park opens for booking only with its payment details.
set role authenticated;
select tests.login(:manager);
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Utep MMC', 'Kapital Bank', 'AZ21NABZ00000000137010001944', null, null);
reset role;

-- ---- booking: price and the last space ---------------------------------------
set role authenticated;
select tests.login(:driver);
insert into ids select 'b1', (public.tir_park_booking_create((select id from ids where k='p'), now() + interval '1 hour', now() + interval '3 hours 10 minutes', 1) ->> 'id')::uuid;
select tests.check((select status = 'pending_payment' and units = 3 and amount = 15 and hold_until > now() and code is null
                    from public.tir_park_bookings where id = (select id from ids where k='b1')),
  'B1 2 h 10 min at 5 AZN / hour = 3 hours = 15 AZN; space held; no code before payment');
select tests.check((select (public.tir_park_availability((select id from ids where k='p'), now() + interval '2 hours', now() + interval '4 hours') ->> 'free')::int = 1),
  'B2 a payment hold takes its space (1 of 2 left)');
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now() + interval '2 hours', now() + interval '4 hours', 2) $$)
  like '%no_space%', 'B3 more TIRs than free places are refused');
insert into ids select 'b2', (public.tir_park_booking_create((select id from ids where k='p'), now() + interval '2 hours', now() + interval '4 hours', 1) ->> 'id')::uuid;
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now() + interval '2 hours', now() + interval '3 hours', 1) $$)
  like '%no_space%', 'B4 the last space goes to one booking only');
select tests.check((select (public.tir_park_availability((select id from ids where k='p'), now() + interval '5 hours', now() + interval '6 hours') ->> 'free')::int = 2),
  'B5 another time is still free');
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now() - interval '2 hours', now() + interval '1 hour', 1) $$)
  like '%invalid_time%', 'B6 no booking in the past');
select tests.login(:manager);
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now() + interval '8 hours', now() + interval '9 hours', 1) $$)
  like '%own_park%', 'B7 a manager does not book his own park');
select tests.check((select count(*) = 0 from public.tir_park_bookings), 'B8 RLS: the manager does not read the bookings table (codes stay hidden)');
select tests.check((select jsonb_array_length(public.tir_park_manager_bookings((select id from ids where k='p'))) = 2
                     and not (public.tir_park_manager_bookings((select id from ids where k='p')) -> 0 ? 'code')),
  'B9 …he sees his park''s bookings without codes');
select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_manager_bookings((select id from ids where k='p')) $$) like '%not_allowed%',
  'B10 a driver does not see the park''s list');
select tests.check(tests.err($$ update public.tir_park_bookings set status = 'confirmed' $$) like '%permission denied%'
                   or tests.err($$ insert into public.tir_park_bookings (booking_no, park_id, trucks, start_at, end_at, units, unit, price, amount)
                                   values ('X', (select id from ids where k='p'), 1, now(), now() + interval '1 hour', 1, 'hour', 1, 1) $$) like '%permission denied%',
  'B11 no direct writes (server functions only)');

-- ---- payment ------------------------------------------------------------------
select tests.check(tests.err($$ select public.tir_park_booking_payment_create((select id from ids where k='b1'), 'card', 'tpbook-0001') $$)
  like '%payments_disabled%', 'P1 test mode: the checkout stays closed for normal users');
reset role;
update public.payment_settings set mode = 'live' where id = 1;
set role authenticated;
select tests.login(:driver);
-- 0080: FreightLink takes no money for parks — the card checkout stays closed even in LIVE.
select tests.check(tests.err($$ select public.tir_park_booking_payment_create((select id from ids where k='b1'), 'card', 'tpbook-live-01') $$)
  like '%payments_disabled%', 'P2 no card checkout for bookings, even in live mode (0080)');
select tests.check((select count(*) = 0 from public.ad_payments where idempotency_key = 'tpbook-live-01'), 'P3 …no payment row made');
reset role;
update public.payment_settings set mode = 'test' where id = 1;
insert into public.ad_payments (tir_park_booking_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :driver, amount, currency, 'card', 'test', 'test', 'tpbook-b1-001' from public.tir_park_bookings where id = (select id from ids where k='b1');
insert into public.ad_payments (tir_park_booking_id, user_id, amount, currency, method, provider, mode, idempotency_key)
select id, :driver, amount, currency, 'card', 'test', 'test', 'tpbook-b2-001' from public.tir_park_bookings where id = (select id from ids where k='b2');
select tests.check(tests.err($$ insert into public.ad_payments (cargo_promo_order_id, tir_park_booking_id, user_id, amount, currency, method, provider, mode, idempotency_key)
  select gen_random_uuid(), (select id from ids where k='b1'), 'a0000000-0000-4000-8000-000000000021', 1, 'AZN', 'card', 'test', 'test', 'tpbook-x-001' $$)
  like '%ad_payments_one_target%' or tests.err($$ insert into public.ad_payments (cargo_promo_order_id, tir_park_booking_id, user_id, amount, currency, method, provider, mode, idempotency_key)
  select gen_random_uuid(), (select id from ids where k='b1'), 'a0000000-0000-4000-8000-000000000021', 1, 'AZN', 'card', 'test', 'test', 'tpbook-x-001' $$) like '%foreign key%',
  'P4 a payment belongs to exactly one thing');
create temp table t_pay as select * from public.ad_payments where idempotency_key in ('tpbook-b1-001', 'tpbook-b2-001');
grant select on t_pay to service_role;

set role authenticated;
select tests.login(:driver);
select tests.check(tests.err($$ select public.finance_apply_provider_event('test', 'evt79_x', (select id from t_pay where idempotency_key = 'tpbook-b1-001'), 'payment.succeeded', 15, 'AZN', null) $$)
  similar to '%(not_authorized|permission denied)%', 'P5 the client cannot confirm a payment itself');
reset role;
set role service_role;
select pg_temp.as_service();
select tests.check(public.finance_apply_provider_event('test', 'evt79_ok', (select id from t_pay where idempotency_key = 'tpbook-b1-001'), 'payment.succeeded', 15, 'AZN', null) = 'applied',
  'P6 a verified provider event: succeeded');
select tests.check(public.finance_apply_provider_event('test', 'evt79_ok', (select id from t_pay where idempotency_key = 'tpbook-b1-001'), 'payment.succeeded', 15, 'AZN', null) = 'duplicate',
  'P7 the same event twice changes nothing');
select tests.check(public.finance_apply_provider_event('test', 'evt79_fail', (select id from t_pay where idempotency_key = 'tpbook-b2-001'), 'payment.failed', 10, 'AZN', null) = 'applied',
  'P8 a failed payment (2 hours = 10 AZN)');
reset role;
select tests.check((select status = 'confirmed' and paid_mode = 'test' and code ~ '^[A-Z2-9]{8}$' and hold_until is null
                    from public.tir_park_bookings where id = (select id from ids where k='b1')),
  'P9 success: confirmed, marked TEST, with an 8-character code');
select tests.check((select status = 'cancelled' and cancel_reason = 'payment_failed' from public.tir_park_bookings where id = (select id from ids where k='b2')),
  'P10 failure: the hold is freed');
set role authenticated;
select tests.login(:driver);
select tests.check((select (public.tir_park_availability((select id from ids where k='p'), now() + interval '2 hours', now() + interval '4 hours') ->> 'free')::int = 1),
  'P11 free places follow (1 confirmed, the failed one freed)');
select tests.check((select code is not null from public.tir_park_bookings where id = (select id from ids where k='b1')), 'P12 the driver sees his code');

-- ---- expired hold -----------------------------------------------------------------
insert into ids select 'b3', (public.tir_park_booking_create((select id from ids where k='p'), now() + interval '10 hours', now() + interval '11 hours', 2) ->> 'id')::uuid;
reset role;
update public.tir_park_bookings set hold_until = now() - interval '1 minute' where id = (select id from ids where k='b3');
set role authenticated;
select tests.login(:driver);
select tests.check((select (public.tir_park_availability((select id from ids where k='p'), now() + interval '10 hours', now() + interval '11 hours') ->> 'free')::int = 2),
  'E1 an expired hold frees its space');
select tests.check(tests.err($$ select public.tir_park_booking_payment_create((select id from ids where k='b3'), 'card', 'tpbook-0003') $$)
  like '%payments_disabled%' or tests.err($$ select public.tir_park_booking_payment_create((select id from ids where k='b3'), 'card', 'tpbook-0003') $$) like '%order_not_payable%',
  'E2 an expired hold cannot be paid');
insert into ids select 'b4', (public.tir_park_booking_create((select id from ids where k='p'), now() + interval '10 hours', now() + interval '11 hours', 2) ->> 'id')::uuid;
select tests.check((select status = 'expired' from public.tir_park_bookings where id = (select id from ids where k='b3')), 'E3 …and is marked expired');

-- ---- entry code -----------------------------------------------------------------
select tests.check(tests.err(format($$ select public.tir_park_booking_check_in(%L, %L) $$, (select id from ids where k='p'),
  (select code from public.tir_park_bookings where id = (select id from ids where k='b1')))) like '%not_allowed%',
  'C1 the driver cannot check himself in');
create temp table t_code as select code from public.tir_park_bookings where id = (select id from ids where k='b1');
grant select on t_code to authenticated;
select tests.login(:manager);
select tests.check((public.tir_park_booking_check_in((select id from ids where k='p'), 'AAAA2222') ->> 'error') = 'invalid_code',
  'C2 a made-up code is refused');
reset role;
select tests.check((select count(*) = 1 from public.tir_park_code_attempts), 'C3 …and counted for the hourly limit');
set role authenticated;
select tests.login(:manager);
select tests.check((public.tir_park_booking_check_in((select id from ids where k='p'), lower((select code from t_code))) ->> 'status') = 'checked_in',
  'C4 the right code: the TIR is in');
select tests.check(tests.err(format($$ select public.tir_park_booking_check_in(%L, %L) $$, (select id from ids where k='p'), (select code from t_code)))
  like '%already_used%', 'C5 a used code is refused');
select public.tir_park_booking_check_out((select id from ids where k='b1'));
reset role;
select tests.check((select status = 'completed' and checked_out_at is not null from public.tir_park_bookings where id = (select id from ids where k='b1')),
  'C6 exit: completed');
set role authenticated;
select tests.login(:driver);
select tests.check((select (public.tir_park_availability((select id from ids where k='p'), now() + interval '2 hours', now() + interval '4 hours') ->> 'free')::int = 2),
  'C7 …and its space is free again');

-- another park's manager cannot check this park's codes
select tests.login(:admin);
select tests.check(public.tir_park_booking_check_in((select id from ids where k='p'), 'BBBB3333') ->> 'error' = 'invalid_code', 'C8 an admin may check (wrong code refused)');
select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_booking_check_out((select id from ids where k='b1')) $$) like '%not_allowed%',
  'C9 only the park''s manager / an admin records the exit');

-- ---- cancel, admin -------------------------------------------------------------------
select public.tir_park_booking_cancel((select id from ids where k='b4'));
select tests.check((select status = 'cancelled' from public.tir_park_bookings where id = (select id from ids where k='b4')), 'X1 the driver cancels');
select tests.check(tests.err($$ select public.admin_tir_park_booking_set_status((select id from ids where k='b4'), 'completed') $$) like '%admin_only%',
  'X2 only an admin sets a booking''s status');
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_tir_park_booking_set_status((select id from ids where k='b4'), 'confirmed') $$) like '%not_paid%',
  'X3 an unpaid booking cannot be confirmed by hand');
select public.admin_tir_park_booking_set_status((select id from ids where k='b4'), 'expired');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'tir_park.booking_expired'), 'X4 admin changes are logged');

-- ---- manager edits, claim of an existing park -------------------------------------
set role authenticated;
select tests.login(:manager);
select public.tir_park_manager_update((select id from ids where k='p'), 20, 5, 6, 'day', '08:00–22:00', '+994501234567', true);
select tests.check((select bookable = 5 and price = 6 and price_unit = 'day' from public.tir_parks where id = (select id from ids where k='p')),
  'U1 the approved manager changes free places and price');
select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_manage_apply((select id from ids where k='p'), 'Başqa Park', null, null, null, null, '+994501111111', '{}', 5, 1, 3, 'hour', null) $$)
  like '%already_managed%', 'U2 a managed park cannot be claimed by another');
reset role;
select tests.check((select count(*) = 0 from public.tir_parks where manager_id = :driver), 'U3 …nothing changed');
select tests.summary('TIRPARK REZERVASİYA (0079)');

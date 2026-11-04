-- TIR park: one plate per truck in a booking — 0092. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set drv     '''a0000000-0000-4000-8000-000000000021'''
\set drv2    '''a0000000-0000-4000-8000-000000000011'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
create or replace function pg_temp.today_baku() returns timestamptz language sql as $$
  select date_trunc('day', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku';
$$;
create or replace function pg_temp.stay(p_plate text) returns uuid language sql as $$
  select id from public.tir_park_stays where plate = p_plate and exited_at is null;
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- A park of 4 places, 3 AZN / day.
set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Plates Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.91, 46.71, null, 4, 3, '+994501112233'));
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select public.tir_park_manager_update((select id from ids where k='p'), 4, 4, 3, 'day', '24/7', '+994501112233', true);

-- ---- Booking -----------------------------------------------------------------------
select tests.login(:drv);
select tests.check(tests.err(format($$ select public.tir_park_booking_create(%L, %L::timestamptz, %L::timestamptz, 3, '10-AA-001',
                     array['10-AA-001', '10-AA-002']) $$, (select id from ids where k='p'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day'))
  like '%plates_count%', 'B1 3 TIRs need 3 plates');
select tests.check(tests.err(format($$ select public.tir_park_booking_create(%L, %L::timestamptz, %L::timestamptz, 2, '10-AA-001',
                     array['10 aa 001', '10-AA-001']) $$, (select id from ids where k='p'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day'))
  like '%duplicate_plate%', 'B2 the same plate twice is refused (after tidying)');
select tests.check(tests.err(format($$ select public.tir_park_booking_create(%L, %L::timestamptz, %L::timestamptz, 2, '10-AA-001',
                     array['10-AA-001', 'ABC']) $$, (select id from ids where k='p'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day'))
  like '%invalid_plate%', 'B3 every plate must look like a plate');
insert into ids select 'm', (public.tir_park_booking_create((select id from ids where k='p'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day',
  3, '10 aa 001', array['10 aa 001', '10.aa.002', '10-AA-003']) ->> 'id')::uuid;
reset role;
select tests.check((select plates = array['10-AA-001', '10-AA-002', '10-AA-003'] and plate = '10-AA-001' and trucks = 3 and amount = 9
                      from public.tir_park_bookings where id = (select id from ids where k='m')),
  'B4 three tidy plates kept, the first as "plate"; 3 AZN × 1 day × 3 TIR = 9 AZN');
set role authenticated;
-- An old app: one truck, one plate (5 arguments) — unchanged.
select tests.login(:drv2);
insert into ids select 's', (public.tir_park_booking_create((select id from ids where k='p'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day',
  1, '20-BB-001') ->> 'id')::uuid;
reset role;
select tests.check((select plates is null and plate = '20-BB-001' from public.tir_park_bookings where id = (select id from ids where k='s')),
  'B5 a single-truck booking from the old app works as before');
-- Pay both (receipt → confirm).
insert into storage.objects (bucket_id, name, owner) values
  ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='m') || '/r.jpg', :drv),
  ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000011/' || (select id from ids where k='s') || '/r.jpg', :drv2);
set role authenticated;
select tests.login(:drv);
select public.tir_park_booking_receipt((select id from ids where k='m'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='m') || '/r.jpg');
select tests.login(:drv2);
select public.tir_park_booking_receipt((select id from ids where k='s'), 'a0000000-0000-4000-8000-000000000011/' || (select id from ids where k='s') || '/r.jpg');
select tests.login(:owner);
select tests.check((select (e -> 'plates') = '["10-AA-001", "10-AA-002", "10-AA-003"]'::jsonb
                      from jsonb_array_elements(public.tir_park_manager_bookings((select id from ids where k='p'))) e
                     where e ->> 'id' = (select id from ids where k='m')::text),
  'B6 the manager sees every plate next to the receipt');
select public.tir_park_booking_confirm_payment((select id from ids where k='m'));
select public.tir_park_booking_confirm_payment((select id from ids where k='s'));
select tests.check((select count(*) = 2 from jsonb_array_elements(public.tir_park_parked((select id from ids where k='p')) -> 'expected')),
  'B7 both paid bookings are expected today');

-- ---- Entry ---------------------------------------------------------------------------
select tests.check(public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-002') ->> 'booking_no' is not null,
  'E1 the 2nd plate of the booking comes in on the booking');
reset role;
select tests.check((select status = 'checked_in' from public.tir_park_bookings where id = (select id from ids where k='m')),
  'E2 the booking is checked in from its first truck');
set role authenticated;
select tests.login(:owner);
select tests.check(public.tir_park_stay_enter((select id from ids where k='p'), '10 aa 001') ->> 'booking_no' is not null,
  'E3 another plate of the same booking also comes in on it (not as a car without a booking)');
select tests.check((select (e -> 'plates') = '["10-AA-003"]'::jsonb
                      from jsonb_array_elements(public.tir_park_parked((select id from ids where k='p')) -> 'expected') e
                     where e ->> 'id' = (select id from ids where k='m')::text),
  'E4 the list still expects the truck that has not come (10-AA-003)');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-AA-002') $$, (select id from ids where k='p'))) like '%already_in%',
  'E5 a plate already in the park cannot come in twice');
select tests.check(public.tir_park_stay_enter((select id from ids where k='p'), '20-BB-001') ->> 'booking_no' is not null,
  'E6 the single-truck booking comes in as before');

-- ---- Capacity --------------------------------------------------------------------------
select tests.check((public.tir_park_owner_summary((select id from ids where k='p')) ->> 'in_park')::int = 3
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'reserved')::int = 1
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'free')::int = 0,
  'C1 3 in the park + 1 booked truck not come yet = 4 of 4 places');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '30-CC-001') $$, (select id from ids where k='p'))) like '%no_space%',
  'C2 a car without a booking is refused: the 3rd booked truck keeps its place');
select tests.login(:drv);
select tests.check((public.tir_park_availability((select id from ids where k='p'), now(), now() + interval '1 minute') ->> 'free')::int = 0,
  'C3 no free place for booking now either');
select tests.check((public.tir_park_availability((select id from ids where k='p'), pg_temp.today_baku() + interval '3 days',
                     pg_temp.today_baku() + interval '4 days') ->> 'free')::int = 4,
  'C4 a future day is free (0091 unchanged)');

-- ---- Exit ------------------------------------------------------------------------------
select tests.login(:owner);
select tests.check((public.tir_park_stay_exit(pg_temp.stay('10-AA-002')) ->> 'amount')::numeric = 0,
  'X1 a booked truck leaving within its booking pays nothing more');
reset role;
select tests.check((select status = 'checked_in' from public.tir_park_bookings where id = (select id from ids where k='m')),
  'X2 the booking is not finished while its other trucks are in or still to come');
set role authenticated;
select tests.login(:owner);
select tests.check(public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-003') ->> 'booking_no' is not null,
  'X3 the 3rd truck still comes in on the booking');
select tests.check(public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-002') ->> 'booking_no' is not null,
  'X4 a truck of the running booking that went out comes back on its paid place');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '30-CC-002') $$, (select id from ids where k='p'))) like '%no_space%',
  'X4b the park is full again (3 booked trucks + 1 single)');
select public.tir_park_stay_exit(pg_temp.stay('10-AA-002'));
select public.tir_park_stay_exit(pg_temp.stay('10-AA-001'));
reset role;
select tests.check((select status = 'checked_in' from public.tir_park_bookings where id = (select id from ids where k='m')),
  'X5 still one truck of the booking in the park → not finished');
-- The booking's time ends; the last truck overstays 2 hours: only the overstay is paid.
update public.tir_park_bookings set start_at = now() - interval '1 day 2 hours', end_at = now() - interval '2 hours'
 where id = (select id from ids where k='m');
update public.tir_park_stays set entered_at = now() - interval '1 day', paid_until = now() - interval '2 hours'
 where booking_id = (select id from ids where k='m') and exited_at is null;
set role authenticated;
select tests.login(:owner);
select tests.check((public.tir_park_stay_exit(pg_temp.stay('10-AA-003')) ->> 'amount')::numeric = 0.25,
  'X6 the last truck pays only its overstay: 2 h × 3 AZN / 24 h = 0.25');
reset role;
select tests.check((select status = 'completed' from public.tir_park_bookings where id = (select id from ids where k='m')),
  'X7 the booking is finished with its last truck');
set role authenticated;
select tests.login(:owner);
select public.tir_park_stay_exit(pg_temp.stay('20-BB-001'));
reset role;
select tests.check((select status = 'completed' from public.tir_park_bookings where id = (select id from ids where k='s')),
  'X8 the single-truck booking is finished at its exit, as before');
select tests.summary('TIRPARK HƏR TIR ÜÇÜN NÖMRƏ (0092)');

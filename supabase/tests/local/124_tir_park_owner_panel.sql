-- TIR park owner panel, stage 1 — 0086. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''
\set other   '''a0000000-0000-4000-8000-000000000011'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

-- ---- "Park işlədirəm": name → admin → panel ----------------------------------------
set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Göygöl TIR Park'));
select tests.check(tests.err($$ select public.tir_park_owner_apply('İkinci') $$) like '%already_applied%', 'A1 one open request at a time');
select tests.check(tests.err(format($$ select public.tir_park_owner_setup(%L, null, 40.5, 46.3, null, 50, 3, '+994501112233') $$,
  (select id from ids where k='r'))) like '%not_allowed%', 'A2 nothing before the admin approves');
select tests.check(tests.err(format($$ select public.admin_tir_park_owner_request_set(%L, 'approved') $$, (select id from ids where k='r')))
  like '%admin_only%', 'A3 only an admin approves');
select tests.login(:admin);
select tests.check(exists (select 1 from jsonb_array_elements(public.admin_tir_park_owner_requests()) e
                    where e ->> 'park_name' = 'Göygöl TIR Park' and e ->> 'status' = 'pending'), 'A4 the admin sees the request');
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.tir_park_owner_setup(%L, null, 40.5, 46.3, null, 50, 3, '+994501112233') $$,
  (select id from ids where k='r'))) like '%not_found%', 'A5 nobody else sets it up');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.5800, 46.3200, 'Göygöl', 3, 3, '+994501112233'));
select tests.check((select status = 'approved' and manager_id = :owner and manager_status = 'approved' and capacity = 3 and bookable = 3
                     and price = 3 and price_unit = 'day' and name = 'Göygöl TIR Park' from public.tir_parks where id = (select id from ids where k='p')),
  'A6 the park is on the map, run by its owner (3 places, 3 AZN / day)');
select tests.check((select park_id = (select id from ids where k='p') from public.tir_park_owner_requests where id = (select id from ids where k='r')),
  'A7 the request points at the park (panel opens)');
select tests.check(tests.err(format($$ select public.tir_park_owner_setup(%L, null, 41.0, 46.0, null, 5, 3, '+994501112233') $$,
  (select id from ids where k='r'))) like '%not_allowed%', 'A8 set up once');

-- ---- cars by plate, money by time --------------------------------------------------
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, 'abc') $$, (select id from ids where k='p'))) like '%invalid_plate%',
  'S1 a plate is needed');
insert into ids select 's1', (public.tir_park_stay_enter((select id from ids where k='p'), '10 bb 442') ->> 'id')::uuid;
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-BB-442') $$, (select id from ids where k='p'))) like '%already_in%',
  'S2 the same truck is not in twice');
select tests.login(:driver);
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '77-AA-777') $$, (select id from ids where k='p'))) like '%not_allowed%',
  'S3 only the park''s people add cars');
select tests.check((select count(*) = 0 from public.tir_park_stays), 'S4 …and see them');
reset role;
-- 5 h / 28 h / 48 h at 3 AZN per 24 h.
select tests.check(public._tir_park_stay_amount(3, now() - interval '5 hours', null, now()) = 0.63
               and public._tir_park_stay_amount(3, now() - interval '28 hours', null, now()) = 3.50
               and public._tir_park_stay_amount(3, now() - interval '48 hours', null, now()) = 6.00,
  'M1 3 AZN / 24 h: 5 h = 0.63, 1 day 4 h = 3.50, 2 days = 6.00');
select tests.check(public._tir_park_stay_amount(3, now() - interval '3 days', now() + interval '1 hour', now()) = 0
               and public._tir_park_stay_amount(3, now() - interval '3 days', now() - interval '5 hours', now()) = 0.63,
  'M2 a paid booking: nothing until its end, then the overstay by the hour');
update public.tir_park_stays set entered_at = now() - interval '28 hours' where id = (select id from ids where k='s1');
set role authenticated;
select tests.login(:owner);
select tests.check((public.tir_park_owner_summary((select id from ids where k='p')) ->> 'accruing')::numeric = 3.50
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'today_paid')::numeric = 0
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'in_park')::int = 1
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'free')::int = 2,
  'M3 in the park: 3.50 run up (not taken yet); Bu gün 0; 1 in, 2 free');
select tests.check((public.tir_park_stay_exit((select id from ids where k='s1')) ->> 'amount')::numeric = 3.50, 'M4 the exit takes 3.50');
select tests.check(tests.err(format($$ select public.tir_park_stay_exit(%L) $$, (select id from ids where k='s1'))) like '%already_out%',
  'M5 no second exit');
select tests.check((public.tir_park_owner_summary((select id from ids where k='p')) ->> 'today_paid')::numeric = 3.50
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'accruing')::numeric = 0,
  'M6 Bu gün 3.50; nothing counted twice');

-- ---- bookings by day from 00:00 and the places ----------------------------------------
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select public.tir_park_manager_update((select id from ids where k='p'), 3, 3, 3, 'day', null, '+994501112233', true);
select tests.login(:driver);
insert into ids select 'b', (public.tir_park_booking_create((select id from ids where k='p'), public._tir_park_today_start(),
  public._tir_park_today_start() + interval '2 days', 1, '99-AC-981') ->> 'id')::uuid;
select tests.check((select units = 2 and amount = 6 and start_at = public._tir_park_today_start() from public.tir_park_bookings
                     where id = (select id from ids where k='b')), 'B1 today from 00:00, 2 days = 6 AZN');
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), public._tir_park_today_start() - interval '1 day',
  public._tir_park_today_start(), 1, '99-AC-982') $$) like '%invalid_time%', 'B2 not for yesterday');
-- Two cars come without a booking: the park (3) is full with the booking.
select tests.login(:owner);
select public.tir_park_stay_enter((select id from ids where k='p'), '11-AA-111');
select public.tir_park_stay_enter((select id from ids where k='p'), '22-BB-222');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '33-CC-333') $$, (select id from ids where k='p'))) like '%no_space%',
  'B3 cars without a booking cannot take the booked place');
select tests.check((public.tir_park_owner_summary((select id from ids where k='p')) ->> 'free')::int = 0, 'B4 Boş 0');
select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), public._tir_park_today_start(),
  public._tir_park_today_start() + interval '1 day', 1, '44-DD-444') $$) like '%no_space%', 'B5 no new booking over the free places');
-- The booked truck pays, then comes: it takes its booked place and pays nothing for the paid days.
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg', :driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
select tests.login(:owner);
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '99-AC-981') $$, (select id from ids where k='p')))
  like '%payment_in_review%', 'B6 a booking still being checked: confirm the payment first');
select public.tir_park_booking_confirm_payment((select id from ids where k='b'));
insert into ids select 's2', (public.tir_park_stay_enter((select id from ids where k='p'), '99 ac 981') ->> 'id')::uuid;
reset role;
select tests.check((select s.booking_id = (select id from ids where k='b') and s.paid_until = b.end_at and b.status = 'checked_in'
                     from public.tir_park_stays s join public.tir_park_bookings b on b.id = s.booking_id
                    where s.id = (select id from ids where k='s2')),
  'B7 the booked truck comes in by its plate (no code) into its booked place');
set role authenticated;
select tests.login(:owner);
select tests.check((public.tir_park_stay_exit((select id from ids where k='s2')) ->> 'amount')::numeric = 0, 'B8 paid days cost nothing more at the exit');
reset role;
select tests.check((select status = 'completed' from public.tir_park_bookings where id = (select id from ids where k='b')), 'B9 the booking is completed');
set role authenticated;
select tests.login(:owner);
select tests.check((public.tir_park_owner_summary((select id from ids where k='p')) ->> 'today_paid')::numeric = 9.50,
  'B10 Bu gün = 3.50 (exit) + 6.00 (booking confirmed today)');
select tests.check((select count(*) >= 5 from jsonb_array_elements(public.tir_park_owner_feed((select id from ids where k='p'), 30)) e
                     where e ->> 'kind' in ('in', 'out', 'booking', 'paid')),
  'B11 Parkın gedişatı lists entries, exits, bookings and payments');
select tests.check(jsonb_array_length(public.tir_park_parked((select id from ids where k='p')) -> 'in') = 2, 'B12 the cars in the park now');
select tests.login(:driver);
select tests.check(tests.err(format($$ select public.tir_park_owner_summary(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'B13 only the park''s people see its numbers');
reset role;
select tests.summary('TIRPARK SAHİBKAR PANELİ (0086)');

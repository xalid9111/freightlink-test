-- TIR park: capacity and money fixes — 0091. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set drv     '''a0000000-0000-4000-8000-000000000021'''
\set worker  '''a0000000-0000-4000-8000-000000000011'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table codes (k text primary key, code text) on commit drop;
grant all on ids, codes to authenticated;
create or replace function pg_temp.today_baku() returns timestamptz language sql as $$
  select date_trunc('day', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku';
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- ---- 1) An overstaying truck counts (park of 1 place) -----------------------------
set role authenticated;
select tests.login(:owner);
insert into ids values ('r1', public.tir_park_owner_apply('Overstay Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r1'), 'approved');
select tests.login(:owner);
insert into ids values ('p1', public.tir_park_owner_setup((select id from ids where k='r1'), null, 40.81, 46.61, null, 1, 3, '+994501112233'));
select public.tir_park_set_pay_details((select id from ids where k='p1'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select public.tir_park_manager_update((select id from ids where k='p1'), 1, 1, 3, 'day', '24/7', '+994501112233', true);
select tests.login(:drv);
insert into ids select 'b1', (public.tir_park_booking_create((select id from ids where k='p1'), pg_temp.today_baku(),
  pg_temp.today_baku() + interval '1 day', 1, '77-BB-777') ->> 'id')::uuid;
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b1') || '/r.jpg', :drv);
select public.tir_park_booking_receipt((select id from ids where k='b1'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b1') || '/r.jpg');
select tests.login(:owner);
select public.tir_park_booking_confirm_payment((select id from ids where k='b1'));
select tests.check(public.tir_park_stay_enter((select id from ids where k='p1'), '77-BB-777') ->> 'booking_no' is not null,
  'O1 the booked truck comes in with its booking (unchanged)');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-CC-001') $$, (select id from ids where k='p1'))) like '%no_space%',
  'O2 while the booking runs, the full park takes no other truck (unchanged)');
-- The booking's time is over; the truck is still in the park.
reset role;
update public.tir_park_bookings set start_at = now() - interval '2 days', end_at = now() - interval '1 hour'
 where id = (select id from ids where k='b1');
set role authenticated;
select tests.login(:owner);
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-CC-002') $$, (select id from ids where k='p1'))) like '%no_space%',
  'O3 an overstaying truck still takes its place: no second truck in a 1-place park');
select tests.login(:drv);
select tests.check((public.tir_parks_booking_now(array[(select id from ids where k='p1')]) -> 0 ->> 'free')::int = 0,
  'O4 the park card shows no free place while the truck overstays');
select tests.check((public.tir_park_availability((select id from ids where k='p1'), now() + interval '5 days', now() + interval '6 days') ->> 'free')::int = 1,
  'O5 …but a future day is free');
select tests.login(:owner);
select public.tir_park_stay_exit((select id from tir_park_stays where park_id = (select id from ids where k='p1') and exited_at is null));
select tests.check(public.tir_park_stay_enter((select id from ids where k='p1'), '10-CC-003') ->> 'plate' = '10-CC-003',
  'O6 after its exit the place is free again');

-- ---- 2) Today's trucks do not lower future days (park of 2 places) ----------------
select tests.login(:owner);
insert into ids values ('r2', public.tir_park_owner_apply('Future Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r2'), 'approved');
select tests.login(:owner);
insert into ids values ('p2', public.tir_park_owner_setup((select id from ids where k='r2'), null, 40.82, 46.62, null, 2, 3, '+994501112233'));
select public.tir_park_set_pay_details((select id from ids where k='p2'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select public.tir_park_manager_update((select id from ids where k='p2'), 2, 2, 3, 'day', '24/7', '+994501112233', true);
select public.tir_park_stay_enter((select id from ids where k='p2'), '10-AA-001');
select public.tir_park_stay_enter((select id from ids where k='p2'), '10-AA-002');
select tests.login(:drv);
select tests.check((public.tir_park_availability((select id from ids where k='p2'), pg_temp.today_baku() + interval '10 days',
                     pg_temp.today_baku() + interval '11 days') ->> 'free')::int = 2,
  'F1 in 10 days both places are free (today''s trucks are not counted)');
select tests.check(public.tir_park_booking_create((select id from ids where k='p2'), pg_temp.today_baku() + interval '10 days',
                     pg_temp.today_baku() + interval '11 days', 2, '77-BB-778') ->> 'status' = 'pending_payment',
  'F2 a booking for that day is taken');
select tests.check((public.tir_park_availability((select id from ids where k='p2'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day') ->> 'free')::int = 0,
  'F3 today the trucks in the park still take the places');
select tests.check(tests.err(format($$ select public.tir_park_booking_create(%L, %L::timestamptz, %L::timestamptz, 1, '77-BB-779') $$,
                     (select id from ids where k='p2'), pg_temp.today_baku(), pg_temp.today_baku() + interval '1 day')) like '%no_space%',
  'F4 …so a booking for today is refused');
select tests.check(tests.err(format($$ select public.tir_park_booking_create(%L, %L::timestamptz, %L::timestamptz, 1, '77-BB-780') $$,
                     (select id from ids where k='p2'), pg_temp.today_baku() + interval '10 days', pg_temp.today_baku() + interval '11 days')) like '%no_space%',
  'F5 the future day is full with its own bookings');
select tests.login(:owner);
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-AA-003') $$, (select id from ids where k='p2'))) like '%no_space%',
  'F6 entry now: a full park takes no third truck (unchanged)');

-- ---- 3) Workers do not read the money from the table --------------------------------
select tests.login(:owner);
insert into codes select 'c', public.tir_park_invite_create((select id from ids where k='p2')) ->> 'code';
select tests.login(:worker);
select public.tir_park_invite_accept((select code from codes where k='c'), 'Vüsal Həsənov');
select tests.login(:owner);
select public.tir_park_worker_approve((select id from ids where k='p2'), :worker);
reset role;
update public.tir_park_stays set entered_at = now() - interval '30 hours' where park_id = (select id from ids where k='p2') and plate = '10-AA-001';
set role authenticated;
select tests.login(:worker);
select tests.check(jsonb_array_length(public.tir_park_parked((select id from ids where k='p2')) -> 'in') = 2,
  'M1 the worker still sees the trucks in the park (his list)');
-- He records the exit through the server (the app's way): 30 h × 3 AZN / 24 h.
insert into ids select 's', (e ->> 'id')::uuid from jsonb_array_elements(public.tir_park_parked((select id from ids where k='p2')) -> 'in') e
 where e ->> 'plate' = '10-AA-001';
select tests.check((public.tir_park_stay_exit((select id from ids where k='s')) ->> 'amount')::numeric = 3.75,
  'M2 the worker records the exit; the server takes 3.75');
select tests.check((select count(*) = 0 from public.tir_park_stays), 'M3 a worker reads no rows of the stays table directly');
select tests.check((select coalesce(sum(amount), 0) = 0 from public.tir_park_stays), 'M4 …so he cannot add up the takings');
select tests.check((public.tir_park_owner_summary((select id from ids where k='p2')) ->> 'today_paid') is null
               and (public.tir_park_owner_summary((select id from ids where k='p2')) ->> 'in_park')::int = 1,
  'M5 his summary: places yes, money no (unchanged)');
select tests.login(:owner);
select tests.check((select sum(amount) = 3.75 from public.tir_park_stays where park_id = (select id from ids where k='p2')),
  'M6 the owner still reads the stays and the money directly');
select tests.check((public.tir_park_owner_summary((select id from ids where k='p2')) ->> 'today_paid')::numeric = 3.75,
  'M7 the owner''s "Bu gün" shows the money taken');
select tests.login(:drv);
select tests.check((select count(*) = 0 from public.tir_park_stays), 'M8 a driver reads nothing');
select tests.login(:admin);
select tests.check((select count(*) >= 3 from public.tir_park_stays), 'M9 an admin reads the stays');
reset role;
select tests.summary('TIRPARK TUTUM VƏ GƏLİR DÜZƏLİŞİ (0091)');

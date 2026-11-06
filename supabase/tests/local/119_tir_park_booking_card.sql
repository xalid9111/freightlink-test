-- TIR park booking on the park card — 0081. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set manager '''a0000000-0000-4000-8000-000000000012'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''
\set driver2 '''a0000000-0000-4000-8000-000000000011'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
create or replace function pg_temp.now_of(p uuid) returns jsonb language sql as $$
  select coalesce((select e from jsonb_array_elements(public.tir_parks_booking_now(array[p])) e limit 1), '{}'::jsonb);
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- A park: capacity 10, takes 6 TIRs now, 3 AZN / day.
set role authenticated;
select tests.login(:manager);
insert into ids values ('p', public.tir_park_manage_apply(null, 'Kart Park', 40.9000, 47.5000, 'Şəki', null,
  '+994501234567', '{}', 10, 6, 3, 'day', '24/7', null));
-- A plain park without a manager.
reset role;  -- users no longer add parks (0100): the park is made directly
with n as (insert into public.tir_parks (name, lat, lng, city, amenities, created_by, status)
           values ('Sadə park', 40.1000, 46.9000, null, '{}', auth.uid(), 'pending') returning id)
insert into ids select 'q', id from n;
set role authenticated;
select tests.login(:admin);
select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved');
select public.admin_tir_park_set_status((select id from ids where k='q'), 'approved');

select tests.login(:driver);
select tests.check(pg_temp.now_of((select id from ids where k='p')) ->> 'open' = 'false',
  'K1 "Rezervasiya bağlıdır" while the park has no payment details');
select tests.check(jsonb_array_length(public.tir_parks_booking_now(array[(select id from ids where k='q')])) = 0,
  'K2 a park without a manager has no booking line');
select tests.login(:manager);
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select tests.login(:driver);
select tests.check(pg_temp.now_of((select id from ids where k='p')) ->> 'open' = 'true'
                   and (pg_temp.now_of((select id from ids where k='p')) ->> 'free')::int = 6,
  'K3 the card shows "Boş yerlər: 6"');
select tests.check(not (pg_temp.now_of((select id from ids where k='p')) ?| array['account', 'card', 'holder', 'bank']),
  'K4 the card gets no payment details');

-- 3 AZN/day × 2 days × 2 TIRs = 12 AZN.
insert into ids select 'b', (public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '2 days', 2) ->> 'id')::uuid;
reset role;
select tests.check((select amount = 12 and units = 2 and unit = 'day' and trucks = 2 from public.tir_park_bookings where id = (select id from ids where k='b')),
  'K5 the server prices it: 3 AZN/gün × 2 gün × 2 TIR = 12 AZN');
set role authenticated;
select tests.login(:driver2);
select tests.check((pg_temp.now_of((select id from ids where k='p')) ->> 'free')::int = 4, 'K6 a held booking takes its places');
select tests.login(:driver);
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg', :driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
select tests.login(:driver2);
select tests.check((pg_temp.now_of((select id from ids where k='p')) ->> 'free')::int = 4,
  'K7 "Ödəniş yoxlanılır": the places are not given to another driver');
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 5) $$)
  like '%no_space%', 'K8 nobody books more than the free places');

select tests.login(:manager);
select public.tir_park_booking_reject_payment((select id from ids where k='b'), 'Pul gəlməyib');
select tests.login(:driver2);
select tests.check((pg_temp.now_of((select id from ids where k='p')) ->> 'free')::int = 6, 'K9 "Rədd et" frees the places at once');

-- Cancelled by the driver → free again.
insert into ids select 'c', (public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 6) ->> 'id')::uuid;
select tests.check((pg_temp.now_of((select id from ids where k='p')) ->> 'free')::int = 0, 'K10 all taken → "Boş yer yoxdur"');
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 1) $$)
  like '%no_space%', 'K11 the last place is not sold twice');
select public.tir_park_booking_cancel((select id from ids where k='c'));
select tests.check((pg_temp.now_of((select id from ids where k='p')) ->> 'free')::int = 6, 'K12 a cancelled booking frees its places');

-- The manager closes booking → "Rezervasiya bağlıdır".
select tests.login(:manager);
select public.tir_park_manager_update((select id from ids where k='p'), 10, 6, 3, 'day', '24/7', '+994501234567', false);
select tests.login(:driver);
select tests.check(pg_temp.now_of((select id from ids where k='p')) ->> 'open' = 'false', 'K13 booking off → "Rezervasiya bağlıdır"');
select tests.login(:manager);
select tests.check(tests.err($$ select public.tir_park_manager_update((select id from ids where k='p'), 5, 6, 3, 'day', null, '+994501234567', true) $$)
  like '%invalid_argument%', 'K14 free places never more than the capacity');
select tests.login(null);
select tests.check(tests.err($$ select public.tir_parks_booking_now(array[gen_random_uuid()]) $$) is not null, 'K15 only for signed-in users');
reset role;
select tests.summary('TIRPARK KART REZERVASİYASI (0081)');

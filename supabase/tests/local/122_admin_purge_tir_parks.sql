-- Admin "Test məlumatlarını sil": TIR parks — 0084. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set manager '''a0000000-0000-4000-8000-000000000012'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

-- A test park with a manager, payment details, a booking (with a receipt
-- in review), a comment; and a real park that must stay.
set role authenticated;
select tests.login(:manager);
insert into ids values ('p', public.tir_park_manage_apply(null, 'Test Park', 40.3000, 47.2000, 'Bərdə', null,
  '+994501234567', '{}', 20, 10, 3, 'day', '24/7', null));
reset role;  -- users no longer add parks (0100): the park is made directly
with n as (insert into public.tir_parks (name, lat, lng, city, amenities, created_by, status)
           values ('Real Park', 41.0000, 45.5000, 'Qazax', '{}', auth.uid(), 'pending') returning id)
insert into ids select 'q', id from n;
set role authenticated;
select tests.login(:admin);
select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved');
select public.admin_tir_park_set_status((select id from ids where k='q'), 'approved');
select tests.login(:manager);
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select tests.login(:driver);
insert into ids select 'b', (public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 1, '99-ZB-911') ->> 'id')::uuid;
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg', :driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
insert into public.tir_park_reviews (park_id, rating, comment) values ((select id from ids where k='p'), 4, 'test');

select tests.login(:manager);
select tests.check(tests.err($$ select public.admin_purge('tir_park', (select id from ids where k='p'), 'SİL') $$) like '%admin_only%',
  'T1 only admins (not even the park''s manager)');
select tests.login(:admin);
select tests.check(exists (select 1 from jsonb_array_elements(public.admin_purge_list('tir_park', 'Test Park', 50)) e
                    where (e ->> 'id')::uuid = (select id from ids where k='p')),
  'T2 the admin finds the park');
select tests.check(tests.err($$ select public.admin_purge('tir_park', (select id from ids where k='p'), 'yox') $$) like '%confirm_required%',
  'T3 nothing without SİL');
select public.admin_purge('tir_park', (select id from ids where k='p'), 'SİL');
reset role;
select tests.check(not exists (select 1 from public.tir_parks where id = (select id from ids where k='p'))
               and not exists (select 1 from public.tir_park_bookings where park_id = (select id from ids where k='p'))
               and not exists (select 1 from public.tir_park_pay_details where park_id = (select id from ids where k='p'))
               and not exists (select 1 from public.tir_park_reviews where park_id = (select id from ids where k='p')),
  'T4 the park goes with its bookings, payment details and comments');
select tests.check(exists (select 1 from public.tir_parks where id = (select id from ids where k='q'))
               and exists (select 1 from public.users where id = :manager)
               and exists (select 1 from public.users where id = :driver),
  'T5 other parks and the people stay');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'purge.tir_park'
                           and entity_id = (select id from ids where k='p')::text and old_value ->> 'name' = 'Test Park'),
  'T6 in the Audit Log');
select tests.check(jsonb_array_length(public.admin_purge_list('user', null, 5)) >= 1, 'T7 the other kinds still work');
select tests.summary('ADMİN: TIR PARKLARINI SİL (0084)');

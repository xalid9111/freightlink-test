-- The truck's plate on a TIR park booking — 0082. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set manager '''a0000000-0000-4000-8000-000000000012'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

set role authenticated;
select tests.login(:manager);
insert into ids values ('p', public.tir_park_manage_apply(null, 'Plate Park', 40.6000, 46.0000, 'Gəncə', null,
  '+994501234567', '{}', 20, 10, 3, 'day', '24/7', null));
select tests.login(:admin);
select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved');
select tests.login(:manager);
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);

select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 1, '  ') $$)
  like '%invalid_plate%', 'L1 no booking without the truck''s plate');
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 1, 'ABC') $$)
  like '%invalid_plate%', 'L2 a plate has digits');
insert into ids select 'b', (public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 1, ' 99 zb.911 ') ->> 'id')::uuid;
select tests.check((select plate from public.tir_park_bookings where id = (select id from ids where k='b')) = '99-ZB-911',
  'L3 kept tidy: " 99 zb.911 " → 99-ZB-911; the driver sees it on his booking');
select tests.check((public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '1 day', 1) ->> 'plate') is null,
  'L4 an old app (4 arguments) still books');
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg', :driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');

select tests.login(:manager);
select tests.check(exists (select 1 from jsonb_array_elements(public.tir_park_manager_bookings((select id from ids where k='p'))) e
                    where e ->> 'status' = 'payment_review' and e ->> 'plate' = '99-ZB-911'),
  'L5 the manager sees the plate next to the receipt');
select tests.check((public.tir_park_booking_confirm_payment((select id from ids where k='b')) ->> 'plate') = '99-ZB-911',
  'L6 …and on the confirmed payment');
reset role;
select tests.check(tests.err($$ update public.tir_park_bookings set plate = 'x' where id = (select id from ids where k='b') $$)
  like '%check constraint%', 'L7 the table keeps plates tidy');
create temp table codes on commit drop as select code from public.tir_park_bookings where id = (select id from ids where k='b');
grant select on codes to authenticated;
set role authenticated;
select tests.login(:manager);
select tests.check((public.tir_park_booking_check_in((select id from ids where k='p'), (select code from codes)) ->> 'plate') = '99-ZB-911',
  'L8 the entry check shows the plate');
reset role;
select tests.summary('TIRPARK MAŞIN NÖMRƏSİ (0082)');

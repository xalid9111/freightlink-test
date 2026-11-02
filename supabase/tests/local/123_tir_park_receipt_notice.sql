-- TIR park: the manager is told about a receipt — 0085. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set manager '''a0000000-0000-4000-8000-000000000012'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

set role authenticated;
select tests.login(:manager);
insert into ids values ('p', public.tir_park_manage_apply(null, 'Bildiriş Park', 40.2000, 46.6000, 'Tovuz', null,
  '+994501234567', '{}', 20, 10, 3, 'day', '24/7', null));
select tests.login(:admin);
select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved');
select tests.login(:manager);
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'AZ21ABCD00001111', null, null);
select tests.check(public.tir_park_manager_pending() = 0, 'N0 nothing waits yet');

select tests.login(:driver);
insert into ids select 'b', (public.tir_park_booking_create((select id from ids where k='p'), now(), now() + interval '2 days', 1, '99-AC-981') ->> 'id')::uuid;
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg', :driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
select tests.check((select status from public.tir_park_bookings where id = (select id from ids where k='b')) = 'payment_review',
  'N1 the receipt goes through as before');
select tests.check(public.tir_park_manager_pending() = 0, 'N2 the driver has nothing to confirm');

select tests.login(:manager);
select tests.check(public.tir_park_manager_pending() = 1, 'N3 the manager sees 1 receipt waiting');
select tests.check((select count(*) = 1 from public.notifications where type = 'tirpark_payment_review'
                     and title = 'Yeni ödəniş: 99-AC-981' and (data ->> 'booking_id')::uuid = (select id from ids where k='b')),
  'N4 a notice for the manager (his own notifications)');
select tests.check((select count(*) = 1 from public.messages m
                     where m.sender_id = :driver and m.receiver_id = :manager
                       and m.message like 'Ödəniş etdim, qəbz yükləndi.%' and m.message like '%Maşın: 99-AC-981%'
                       and m.message like '%2 gün, 1 TIR%' and m.message like '%Məbləğ: 6.00 AZN%'),
  'N5 a message from the driver in Mesajlar: truck, days, amount');

-- The driver uploads again while it is checked: no second message, a notice for the new receipt.
select tests.login(:driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
reset role;
select tests.check((select count(*) = 1 from public.messages where sender_id = :driver and message like 'Ödəniş etdim%'),
  'N6 no second message for the same booking');
select tests.check((select count(*) <= 2 from public.notifications where type = 'tirpark_payment_review'), 'N7 at most one notice per receipt');

set role authenticated;
select tests.login(:manager);
select public.tir_park_booking_confirm_payment((select id from ids where k='b'));
select tests.check(public.tir_park_manager_pending() = 0, 'N8 confirmed → nothing waits');
select tests.login(:driver);
select tests.check((select count(*) = 0 from public.notifications where type = 'tirpark_payment_review'),
  'N9 the driver does not see the manager''s notices');
reset role;
select tests.summary('TIRPARK QƏBZ BİLDİRİŞİ (0085)');

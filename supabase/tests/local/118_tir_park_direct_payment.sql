-- TIR park booking paid by direct bank transfer — 0080. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set manager '''a0000000-0000-4000-8000-000000000012'''
\set driver  '''a0000000-0000-4000-8000-000000000021'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

set role authenticated;
select tests.login(:manager);
insert into ids values ('p', public.tir_park_manage_apply(null, 'Transfer Park', 41.2000, 48.9000, 'Quba', null,
  '+994501234567', '{}', 10, 1, 4, 'hour', '24/7', null));
select tests.login(:admin);
select public.admin_tir_park_manager_set((select id from ids where k='p'), 'approved');

-- ---- the park's payment details ---------------------------------------------
select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_booking_create((select id from ids where k='p'), now() + interval '1 hour', now() + interval '2 hours', 1) $$)
  like '%not_bookable%', 'D1 no booking before the park has payment details');
select tests.check(tests.err($$ select public.tir_park_set_pay_details((select id from ids where k='p'), 'Mən', null, 'AZ00X', null) $$)
  like '%not_allowed%', 'D2 only the park''s manager enters the details');
select tests.login(:manager);
select tests.check(tests.err($$ select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', null, null, null) $$)
  like '%invalid_argument%', 'D3 an account or a card is needed');
select tests.check(tests.err($$ select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', null, null, '1234') $$)
  like '%invalid_argument%', 'D4 a card number must look like one');
select public.tir_park_set_pay_details((select id from ids where k='p'), 'Park MMC', 'ABB', 'az21 abcd 0000 1111', '4169 7388 1234 5678', 'Təyinat: rezervasiya nömrəsi');
select tests.check((public.tir_park_get_pay_details((select id from ids where k='p')) ->> 'card') = '4169 7388 1234 5678'
                   and (public.tir_park_get_pay_details((select id from ids where k='p')) ->> 'account') = 'AZ21ABCD00001111',
  'D5 the manager sees and keeps his details (tidied)');
select tests.check(tests.err($$ select * from public.tir_park_pay_details $$) like '%permission denied%', 'D6 the table is not readable directly');
select tests.login(:driver);
select tests.check(tests.err($$ select public.tir_park_get_pay_details((select id from ids where k='p')) $$) like '%not_allowed%',
  'D7 a driver cannot read the park''s details from the park');
select tests.check((select to_jsonb(p) ? 'card' or to_jsonb(p) ? 'account' from public.tir_parks p where id = (select id from ids where k='p')) = false,
  'D8 nothing of it on the park card');

-- ---- booking, details, receipt -------------------------------------------------
insert into ids select 'b', (public.tir_park_booking_create((select id from ids where k='p'), now() + interval '1 hour', now() + interval '3 hours', 1) ->> 'id')::uuid;
select tests.check((select hold_until > now() + interval '55 minutes' from public.tir_park_bookings where id = (select id from ids where k='b')),
  'R1 the space is held 60 minutes (time for a bank transfer)');
select tests.check((public.tir_park_booking_pay_details((select id from ids where k='b')) ->> 'card') = '4169 7388 1234 5678'
                   and (public.tir_park_booking_pay_details((select id from ids where k='b')) ->> 'amount')::numeric = 8,
  'R2 after booking the driver sees where to pay and how much');
select tests.login(:admin);
select tests.check(tests.err($$ select public.tir_park_booking_pay_details((select id from ids where k='b')) $$) like '%not_found%',
  'R3 nobody else gets them through another one''s booking');
select tests.login(:driver);
select tests.check(tests.err(format($$ select public.tir_park_booking_receipt(%L, %L) $$, (select id from ids where k='b'),
  'a0000000-0000-4000-8000-000000000012/' || (select id from ids where k='b') || '/r.jpg')) like '%invalid_path%',
  'R4 a receipt only from the driver''s own folder');
insert into storage.objects (bucket_id, name, owner)
values ('tirpark-receipts', 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg', :driver);
select tests.check(tests.err($$ insert into storage.objects (bucket_id, name, owner) values ('tirpark-receipts',
  'a0000000-0000-4000-8000-000000000021/' || gen_random_uuid() || '/x.jpg', 'a0000000-0000-4000-8000-000000000021') $$) like '%row-level security%',
  'R5 storage: only into the folder of one''s own booking');
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
select tests.check((select status = 'payment_review' and receipt_path is not null and hold_until is null and code is null
                    from public.tir_park_bookings where id = (select id from ids where k='b')),
  'R6 receipt uploaded → "Ödəniş yoxlanılır", no code yet');
select tests.check((select (public.tir_park_availability((select id from ids where k='p'), now() + interval '1 hour', now() + interval '2 hours') ->> 'free')::int = 0),
  'R7 while it is checked, the space stays taken');
select tests.check(tests.err($$ select public.tir_park_booking_confirm_payment((select id from ids where k='b')) $$) like '%not_allowed%',
  'R8 the driver cannot confirm his own payment');

-- ---- the manager checks his account -----------------------------------------------
select tests.login(:manager);
select tests.check((select count(*) = 1 from storage.objects where bucket_id = 'tirpark-receipts'), 'C1 the park''s manager can open the receipt');
select tests.check((public.tir_park_manager_bookings((select id from ids where k='p')) -> 0 ->> 'status') = 'payment_review'
                   and (public.tir_park_manager_bookings((select id from ids where k='p')) -> 0 ->> 'receipt_path') is not null,
  'C2 …and sees it waiting in his list');
select public.tir_park_booking_reject_payment((select id from ids where k='b'), 'Pul gəlməyib');
reset role;
select tests.check((select status = 'pending_payment' and hold_until > now() and reject_note = 'Pul gəlməyib'
                    from public.tir_park_bookings where id = (select id from ids where k='b')),
  'C3 "Rədd et": back to the driver with a note and a new hold');
set role authenticated;
select tests.login(:driver);
select public.tir_park_booking_receipt((select id from ids where k='b'), 'a0000000-0000-4000-8000-000000000021/' || (select id from ids where k='b') || '/r.jpg');
select tests.login(:manager);
select tests.check((public.tir_park_booking_confirm_payment((select id from ids where k='b')) ->> 'status') = 'confirmed',
  'C4 "Ödənişi təsdiqlə" confirms the booking');
reset role;
select tests.check((select paid_mode = 'transfer' and code ~ '^[A-Z2-9]{8}$' and paid_confirmed_by = :manager
                    from public.tir_park_bookings where id = (select id from ids where k='b')),
  'C5 the code is made only now (transfer, confirmed by the manager)');
select tests.check((select count(*) = 0 from public.ad_payments where tir_park_booking_id = (select id from ids where k='b')),
  'C6 FreightLink took no payment');
set role authenticated;
select tests.login(:manager);
select tests.check(tests.err($$ select public.tir_park_booking_confirm_payment((select id from ids where k='b')) $$) like '%not_in_review%',
  'C7 a confirmed booking is not confirmed twice');
select tests.login(:driver);
select tests.check((select code is not null from public.tir_park_bookings where id = (select id from ids where k='b')), 'C9 the driver sees his code');
select tests.check(tests.err($$ select public.tir_park_booking_pay_details((select id from ids where k='b')) $$) like '%not_payable%',
  'C10 the details are not handed out after confirmation');

-- ---- other people ---------------------------------------------------------------------
select tests.login(:admin);
select tests.check((select count(*) = 1 from storage.objects where bucket_id = 'tirpark-receipts'), 'O1 an admin can open receipts');
reset role;
select tests.summary('TIRPARK BİRBAŞA KÖÇÜRMƏ (0080)');

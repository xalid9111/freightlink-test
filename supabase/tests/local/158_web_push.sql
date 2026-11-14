-- 0121: Web Push — devices, preferences, who gets which notification. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set u1      '''a0000000-0000-4000-8000-000000000021'''
\set u2      '''a0000000-0000-4000-8000-000000000011'''
\set conv    '''d0000000-0000-4000-8000-0000000003a1'''
\set ep1     '''https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaa1'''
\set ep2     '''https://web.push.apple.com/QbbbbbbbbbbbbbbbbbbbbbbbbbbB2'''
\set epA     '''https://updates.push.services.mozilla.com/wpush/v2/cccccccccccA'''
\set k       '''BKeyKeyKeyKeyKeyKeyKeyKeyKeyKey1234'''

begin;
reset role;
update public.users set role = 'admin' where id = :admin;
insert into public.conversations (id, cargo_owner_id, carrier_user_id) values (:conv, :u1, :u2);

-- 1) Devices.
set role authenticated;
select tests.login(:u2);
select tests.check(tests.err(format($$ select public.push_subscribe('https://evil.example.com/x/yyyyyyyyyyyyyy', %L, 'authauth12') $$, :k)) like '%invalid_subscription%',
  'D1 only the real push services are accepted');
select public.push_subscribe(:ep1, :k, 'authauth12', 'android', 'test');
select tests.check((select count(*) = 1 from public.push_subscriptions), 'D2 his device is saved, he sees it');
select tests.check(tests.err($$ insert into public.push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://fcm.googleapis.com/x/zzzzzzzzzzzzzzzz', 'xxxxxxxxxxxxxxxxxxxxxxxx', 'xxxxxxxxxx') $$) is not null,
  'D3 no direct writes');
select tests.check(tests.err($$ select * from public.push_outbox $$) is not null, 'D4 nobody reads the outbox');
reset role;
set role authenticated;
select tests.login(:u1);
select tests.check((select count(*) = 0 from public.push_subscriptions), 'D5 nobody sees another user''s devices');
select public.push_subscribe(:ep2, :k, 'authauth12', 'ios', 'test');
reset role;
set role authenticated;
select tests.login(:admin);
select public.push_subscribe(:epA, :k, 'authauth12', 'desktop', 'test');
reset role;
set role anon;
select tests.check(tests.err(format($$ select public.push_subscribe(%L, %L, 'authauth12') $$, :ep1, :k)) is not null, 'D6 visitors cannot');
reset role;

-- 2) Messages: "Name: Yeni mesajınız var" to the receiver only.
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u1, :u2, 'Salam, yük hazırdır? Sabah səhər Bakıdan çıxırıq, zəhmət olmasa təsdiq edin, çox sağ olun, uğurlar');
select tests.check((select count(*) = 1 and bool_and(kind = 'message' and body = 'Yeni mesajınız var' and url = '/#/chat/' || :conv and tag = 'chat-' || :conv
                                         and title = (select full_name from public.users where id = :u1))
                    from public.push_outbox where user_id = :u2), 'M1 the receiver: name + "Yeni mesajınız var", opens the chat');
select tests.check((select count(*) = 0 from public.push_outbox where user_id = :u1), 'M2 never to the sender');
set role authenticated;
select tests.login(:u2);
select public.push_prefs_set(true, true, true);
select tests.check((public.push_prefs_get() ->> 'preview')::boolean, 'M3 the preview is his choice');
reset role;
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u1, :u2, 'Salam, yük hazırdır? Sabah səhər Bakıdan çıxırıq, zəhmət olmasa təsdiq edin, çox sağ olun, uğurlar');
select tests.check((select body = 'Salam, yük hazırdır? Sabah səhər Bakıdan çıxırıq, zəhmət olmasa təsdiq edin, ç' and char_length(body) = 80
                    from public.push_outbox where user_id = :u2 order by created_at desc, id limit 1)
                   or (select count(*) from public.push_outbox where user_id = :u2 and char_length(body) = 80) = 1,
  'M4 preview on: the first 80 characters');
-- He is reading this chat now → no push.
set role authenticated;
select tests.login(:u2);
select public.push_active(:conv);
reset role;
create temp table n0 on commit drop as select count(*) c from public.push_outbox where user_id = :u2;
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u1, :u2, 'oxuyur');
select tests.check((select count(*) from public.push_outbox where user_id = :u2) = (select c from n0), 'M5 no push for the chat he is reading');
set role authenticated;
select tests.login(:u2);
select public.push_active(null);
select public.push_prefs_set(false, true, false);
reset role;
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u1, :u2, 'söndürülüb');
select tests.check((select count(*) from public.push_outbox where user_id = :u2) = (select c from n0), 'M6 messages switched off → none');
-- A receiver without devices gets nothing (the sender u2 → u1 who has one: yes).
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u2, :u1, 'cavab');
select tests.check((select count(*) = 1 from public.push_outbox where user_id = :u1 and kind = 'message'), 'M7 the other way round works too');

-- 3) Admins: a user's suggestion / payment problem.
set role authenticated;
select tests.login(:u1);
select public.support_report_submit('payment', 'Pul getdi VIP olmadı');
reset role;
select tests.check((select count(*) = 1 and bool_and(kind = 'admin_report' and body = 'Ödəniş problemi bildirildi' and url = '/#/admin-reports')
                    from public.push_outbox where user_id = :admin), 'A1 the admin is told');
select tests.check((select count(*) = 0 from public.push_outbox where user_id = :u1 and kind = 'admin_report'), 'A2 an ordinary user is not');

-- 4) İş Mərkəzi: an application → the employer.
insert into public.job_vacancies (id, owner_id, company_name, specialties) values ('b0000000-0000-4000-8000-0000000003a1', :u1, 'Push MMC', '{}');
insert into public.job_applications (vacancy_id, seeker_id, employer_id, initiated_by)
values ('b0000000-0000-4000-8000-0000000003a1', :u2, :u1, 'seeker');
select tests.check((select count(*) = 1 and bool_and(body = 'İş Mərkəzi: yeni müraciət' and url = '/#/jobs/applications')
                    from public.push_outbox where user_id = :u1 and kind = 'job_application'), 'J1 the employer gets the application');
select tests.check((select count(*) = 0 from public.push_outbox where user_id = :u2 and kind = 'job_application'), 'J2 not the applicant');

-- 5) TIR park: the approved manager (u1) gets a worker request.
insert into public.tir_parks (id, name, lat, lng, status, manager_id, manager_status)
values ('7a000000-0000-4000-8000-0000000003a1', 'Push Park', 40.4, 49.9, 'approved', :u1, 'approved');
insert into public.tir_park_workers (park_id, user_id, active, status, full_name)
values ('7a000000-0000-4000-8000-0000000003a1', :u2, false, 'pending', 'Vəli Vəliyev');
select tests.check((select count(*) = 1 and bool_and(body = 'Yeni işçi müraciəti: Vəli Vəliyev' and url = '/#/tirpark/manage')
                    from public.push_outbox where user_id = :u1 and kind = 'park_worker'), 'T1 the manager: a worker request');

-- 6) Language: Russian.
update public.users set preferred_lang = 'ru' where id = :u1;
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u2, :u1, 'привет');
select tests.check(exists (select 1 from public.push_outbox where user_id = :u1 and kind = 'message' and body = 'У вас новое сообщение'), 'L1 in his language');

-- (In one transaction now() is the same for every row, so the receipt
-- test comes after the others.) A booking and its receipt → the manager; the receipt's chat message does not ring twice.
insert into public.tir_park_bookings (id, booking_no, park_id, user_id, trucks, start_at, end_at, units, unit, price, amount)
values ('7b000000-0000-4000-8000-0000000003a1', 'PUSH-0001', '7a000000-0000-4000-8000-0000000003a1', :u2, 1,
        now() + interval '1 day', now() + interval '2 days', 1, 'day', 3, 3);
select tests.check((select count(*) = 1 and bool_and(body = 'Новая бронь: Push Park')
                    from public.push_outbox where user_id = :u1 and kind = 'park_booking'), 'T2 the manager: a new booking');
create temp table n1 on commit drop as select count(*) c from public.push_outbox where user_id = :u1 and kind = 'message';
update public.tir_park_bookings set receipt_at = now(), receipt_path = 'x/y.jpg' where id = '7b000000-0000-4000-8000-0000000003a1';
insert into public.messages (conversation_id, sender_id, receiver_id, message) values (:conv, :u2, :u1, 'Qəbz yükləndi');
select tests.check((select count(*) = 1 from public.push_outbox where user_id = :u1 and kind = 'park_receipt')
               and (select count(*) from public.push_outbox where user_id = :u1 and kind = 'message') = (select c from n1),
  'T3 the receipt: one notification, not two');

-- 7) push-send (service role): take once, result, gone devices removed.
create temp table o1 on commit drop as select id from public.push_outbox where user_id = :u1 and kind = 'message' order by created_at limit 1;
grant select on o1 to service_role, authenticated;
set role authenticated;
select tests.login(:u1);
select tests.check(tests.err($$ select public.push_outbox_take((select id from o1)) $$) is not null, 'S1 a user cannot take notifications');
select tests.check(tests.err($$ select public.push_hook_check('x') $$) is not null, 'S2 a user cannot test the secret');
reset role;
set role service_role;
select tests.check((select (public.push_outbox_take((select id from o1)) -> 'subscriptions' -> 0 ->> 'endpoint') = :ep2), 'S3 push-send gets the devices');
select tests.check(public.push_outbox_take((select id from o1)) is null, 'S4 taken only once');
select tests.check(not public.push_hook_check('0123456789abcdef0123456789abcdef0123'), 'S5 a wrong secret is refused');
select public.push_outbox_done((select id from o1), 0, 1, array[:ep2], 'gone');
reset role;
select tests.check((select status = 'failed' from public.push_outbox where id = (select id from o1))
               and not exists (select 1 from public.push_subscriptions where endpoint = :ep2), 'S6 a gone device is removed');

-- 8) Sign-out / a blocked account.
set role authenticated;
select tests.login(:u2);
select public.push_unsubscribe(:ep1);
select tests.check((select count(*) = 0 from public.push_subscriptions), 'O1 sign-out removes this device');
select public.push_subscribe(:ep1, :k, 'authauth12', 'android', 'test');
reset role;
update public.users set is_blocked = true where id = :u2;
select tests.check(not exists (select 1 from public.push_subscriptions where user_id = :u2), 'O2 a blocked / deleted account keeps no devices');
rollback;

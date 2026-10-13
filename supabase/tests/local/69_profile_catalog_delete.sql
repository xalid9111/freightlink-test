-- PROFILE / CATALOG / MESSAGE DELETE — 0031. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;

-- ---- profile details ------------------------------------------------
select tests.login(:owner1);
insert into public.profile_details (user_id, about, work_hours, address)
values (:owner1, 'Yük daşımaları', 'B.e.–Ş. 09:00–18:00', 'Bakı');
select tests.check((select about = 'Yük daşımaları' from public.profile_details where user_id = :owner1), 'P1 user saves own profile details');
select tests.check(tests.err(format($$ insert into public.profile_details (user_id, about) values (%L, 'hack') $$, :other)) is not null,
  'P2 nobody writes another user''s profile');
select tests.check(tests.err(format($$ update public.profile_details set cover_url = 'https://evil.example/x.png' where user_id = %L $$, :owner1)) like '%check%',
  'P3 cover must be in our profile-media bucket');
select tests.check(tests.err(format($$ update public.profile_details set about = repeat('a', 501) where user_id = %L $$, :owner1)) like '%check%',
  'P4 about is max 500 characters');
select tests.login(:other);
select tests.check((select count(*) = 1 from public.profile_details where user_id = :owner1), 'P5 other signed-in users can read it');
update public.profile_details set about = 'hacked' where user_id = :owner1;
select tests.check((select about = 'Yük daşımaları' from public.profile_details where user_id = :owner1), 'P6 …but not change it');

-- ---- catalog --------------------------------------------------------
select tests.login(:owner1);
insert into public.profile_catalog_items (user_id, image_path, caption)
values (:owner1, :owner1 || '/catalog/1.jpg', 'Tent dəyişimi');
select tests.check((select count(*) = 1 from public.profile_catalog_items where user_id = :owner1), 'C1 owner adds a catalog photo with caption');
select tests.check(tests.err(format($$ insert into public.profile_catalog_items (user_id, image_path) values (%L, %L) $$, :owner1, :other || '/catalog/x.jpg')) like '%check%',
  'C2 image must be in the owner''s own folder');
select tests.check(tests.err(format($$ insert into public.profile_catalog_items (user_id, image_path, caption) values (%L, %L, repeat('a', 301)) $$, :owner1, :owner1 || '/catalog/2.jpg')) like '%check%',
  'C3 caption is max 300 characters');
update public.profile_catalog_items set image_path = :owner1 || '/catalog/other.jpg', caption = 'Yeni izah' where user_id = :owner1;
select tests.check((select image_path = :owner1 || '/catalog/1.jpg' and caption = 'Yeni izah' from public.profile_catalog_items where user_id = :owner1),
  'C4 caption can be edited, the image path cannot');
reset role;
insert into public.profile_catalog_items (user_id, image_path)
select :owner1, :owner1 || '/catalog/f' || g || '.jpg' from generate_series(1, 59) g;
set role authenticated;
select tests.login(:owner1);
select tests.check(tests.err(format($$ insert into public.profile_catalog_items (user_id, image_path) values (%L, %L) $$, :owner1, :owner1 || '/catalog/61.jpg')) like '%catalog_full%',
  'C5 max 60 photos per user');
select tests.login(:other);
delete from public.profile_catalog_items where user_id = :owner1;
select tests.check((select count(*) = 60 from public.profile_catalog_items where user_id = :owner1), 'C6 nobody else can delete them');
select tests.login(:owner1);
delete from public.profile_catalog_items where user_id = :owner1 and image_path = :owner1 || '/catalog/f1.jpg';
select tests.check((select count(*) = 59 from public.profile_catalog_items where user_id = :owner1), 'C7 owner deletes own photo');

-- ---- messages: delete for me / for everyone --------------------------
reset role;
insert into public.conversations (id, cargo_owner_id, carrier_user_id)
values ('c0000000-0000-4000-8000-0000000000d1', :owner1, :other);
insert into public.messages (id, conversation_id, sender_id, receiver_id, message, created_at) values
  ('e0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-0000000000d1', :owner1, :other, 'salam', now() - interval '3 minutes'),
  ('e0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-0000000000d1', :other, :owner1, 'necəsən', now() - interval '2 minutes');
set role authenticated;

select tests.login(:owner1);
select tests.check(tests.err($$ select public.delete_message('e0000000-0000-4000-8000-000000000002', 'direct', 'everyone') $$) like '%not_your_message%',
  'M1 you cannot delete the other person''s message for everyone');
select public.delete_message('e0000000-0000-4000-8000-000000000002', 'direct', 'me');
select tests.check((select count(*) = 1 from public.message_hidden where user_id = :owner1), 'M2 delete for me hides it for me');
select tests.login(:other);
select tests.check((select message = 'necəsən' and deleted_at is null from public.messages where id = 'e0000000-0000-4000-8000-000000000002'),
  'M3 …the other person still has it');
select tests.check((select count(*) = 0 from public.message_hidden), 'M4 hidden lists are private');

select tests.login(:owner1);
select public.delete_message('e0000000-0000-4000-8000-000000000001', 'direct', 'everyone');
select tests.check((select message = '' and deleted_at is not null and sender_id = :owner1 from public.messages where id = 'e0000000-0000-4000-8000-000000000001'),
  'M5 sender deletes own message for everyone: text blanked, marked deleted');
select tests.check(tests.err($$ update public.messages set message = 'changed' where id = 'e0000000-0000-4000-8000-000000000002' $$) is null
  and (select message = 'necəsən' from public.messages where id = 'e0000000-0000-4000-8000-000000000002'),
  'M6 the old guard still blocks editing messages directly');
select tests.login(:admin);
select tests.check(tests.err($$ select public.delete_message('e0000000-0000-4000-8000-000000000002', 'direct', 'me') $$) like '%message_not_found%',
  'M7 outsiders cannot touch the chat');

-- ---- clear chat for me ----------------------------------------------
select tests.login(:owner1);
select tests.check(public.clear_chat_for_me(:other, 'direct') = 1, 'L1 clear chat with a person (all their conversations)');
select tests.check((select count(*) = 1 from public.chat_clears where user_id = :owner1 and kind = 'direct'), 'L2 clear is stored for me only');
select tests.check((select count(*) = 2 from public.messages where conversation_id = 'c0000000-0000-4000-8000-0000000000d1'),
  'L3 no message was deleted from the database');
select tests.check((select count(*) = 1 from public.my_chat_activity()), 'L4 activity list works');
select tests.check(tests.err(format($$ select public.clear_chat_for_me(%L, 'group') $$, :other)) like '%group_not_found%',
  'L5 cannot clear a group you are not in');

reset role;
select tests.summary('profile_catalog_delete');
rollback;

-- Chats started from a service / shop page — 0100. Rolled back.
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set user    '''a0000000-0000-4000-8000-000000000021'''
\set third   '''a0000000-0000-4000-8000-000000000013'''
\set p1      '''5e000000-0000-4000-8000-000000000001'''
\set p4      '''5e000000-0000-4000-8000-000000000004'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
set role authenticated;
select tests.login(:user);
insert into ids select 'c', (public.get_or_create_service_conversation(:p1)).id;
select tests.check((select service_id = :p1 and service_name = 'Approved Garage' and service_kind = 'service'
                       and cargo_owner_id = :user and carrier_user_id = :owner1 and cargo_id is null
                      from public.conversations where id = (select id from ids where k='c')),
  'C1 the chat remembers the page (name, kind); the receiver is the page''s owner');
select tests.check((public.get_or_create_service_conversation(:p1)).id = (select id from ids where k='c'), 'C2 the same page: the same chat');
insert into ids select 'd', (public.get_or_create_direct_conversation(:owner1)).id;
select tests.check((select id from ids where k='d') <> (select id from ids where k='c')
                   and (select service_id is null from public.conversations where id = (select id from ids where k='d')),
  'C3 the person-to-person chat stays separate (not merged)');
insert into public.messages (conversation_id, sender_id, receiver_id, message)
values ((select id from ids where k='c'), :user, :owner1, 'Salam, təkər var?');
select tests.check(exists (select 1 from public.messages where conversation_id = (select id from ids where k='c')), 'C4 a message goes into the page chat');
select tests.check(tests.err($$ insert into public.conversations (cargo_owner_id, carrier_user_id, service_id, service_name, service_kind)
  values ('a0000000-0000-4000-8000-000000000021', 'a0000000-0000-4000-8000-000000000011', '5e000000-0000-4000-8000-000000000001', 'Fake', 'shop') $$)
  like '%row-level security%', 'C5 a user cannot write a page into a chat himself');
select tests.check(tests.err(format($$ select public.get_or_create_service_conversation(%L) $$, :p4)) like '%not_found%',
  'C6 a suspended page cannot be written to');

select tests.login(:owner1);
select tests.check((select service_name = 'Approved Garage' and service_kind = 'service' from public.conversations where id = (select id from ids where k='c')),
  'C7 the receiver sees which page the chat is about');
select tests.check(tests.err(format($$ select public.get_or_create_service_conversation(%L) $$, :p1)) like '%invalid_user%',
  'C8 not to one''s own page');
select tests.login(:third);
select tests.check(not exists (select 1 from public.conversations where id = (select id from ids where k='c')), 'C9 others do not see it');

-- A shop is named a shop.
reset role;
update public.service_providers set categories = '{spare_parts,shop_new}' where id = :p1;
set role authenticated;
select tests.login(:user);
select tests.check((public.get_or_create_service_conversation(:p1)).service_kind = 'shop', 'C10 a shop page: kind "shop"');
-- Google / Apple sign-in: a new account gets its public.users row with the name.
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated', 'g@oauth.test', '{"name":"Google Ad","provider":"google"}'),
 ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-0000000000a2', 'authenticated', 'authenticated', 'a@privaterelay.test', '{"provider":"apple"}');
select tests.check((select full_name = 'Google Ad' and role = 'cargo_owner' from public.users where id = 'a0000000-0000-4000-8000-0000000000a1'),
  'O1 a Google account: profile row with the provider''s name');
select tests.check((select full_name = '' and email = 'a@privaterelay.test' from public.users where id = 'a0000000-0000-4000-8000-0000000000a2'),
  'O2 an Apple account without a name: profile row too (name set later in Profil)');
select tests.summary('SERVİS / MAĞAZA SÖHBƏT KONTEKSTİ (0100)');
rollback;

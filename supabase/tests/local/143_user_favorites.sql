-- "Bəyəndiklərim" (chats, profiles, services, parks) — 0106. Rolled back.
\set u1    '''a0000000-0000-4000-8000-000000000011'''
\set u2    '''a0000000-0000-4000-8000-000000000012'''
\set other '''a0000000-0000-4000-8000-000000000021'''
\set svc   '''5e000000-0000-4000-8000-000000000001'''
\set svc2  '''5e000000-0000-4000-8000-000000000003'''

begin;
reset role;
update public.service_providers set status = 'approved', is_active = true where id = :svc;
update public.service_providers set status = 'rejected' where id = :svc2;
insert into public.conversations (cargo_owner_id, carrier_user_id) values (:u1, :u2);
insert into public.tir_parks (id, name, lat, lng, status) values ('7a000000-0000-4000-8000-000000000001', 'Fav Park', 40.4, 49.8, 'approved')
  on conflict (id) do nothing;

set role authenticated;
select tests.login(:u1);
select tests.check(public.favorite_set('chat', :u2, true), 'F1 a chat I have: liked');
select tests.check(tests.err(format($$ select public.favorite_set('chat', %L, true) $$, :other)) like '%not_found%', 'F2 a chat I do not have: refused');
select tests.check(public.favorite_set('user', :other, true), 'F3 a person''s profile');
select tests.check(tests.err($$ select public.favorite_set('user', auth.uid(), true) $$) like '%not_found%', 'F4 not my own profile');
select tests.check(public.favorite_set('service', :svc, true), 'F5 an approved service');
select tests.check(tests.err(format($$ select public.favorite_set('service', %L, true) $$, :svc2)) like '%not_found%', 'F6 a rejected service: refused');
select tests.check(public.favorite_set('park', '7a000000-0000-4000-8000-000000000001', true), 'F7 an approved park');
select tests.check(public.favorite_set('park', '7a000000-0000-4000-8000-000000000001', true), 'F8 a double tap = one row');
select tests.check((select count(*) = 4 from public.user_favorites), 'F9 my list: 4');
select tests.check(not public.favorite_set('user', :other, false), 'F10 heart off');
select tests.check((select count(*) = 3 from public.user_favorites), 'F10b …only that row goes');
select tests.check(tests.err(format($$ insert into public.user_favorites (user_id, kind, target_id) values (auth.uid(), 'user', %L) $$, :other))
  like '%permission denied%', 'F11 no direct writes');
select tests.check(tests.err($$ select public.favorite_set('moon', gen_random_uuid(), true) $$) like '%invalid_argument%', 'F12 only the four kinds');
select tests.login(:other);
select tests.check(not exists (select 1 from public.user_favorites), 'F13 nobody sees another person''s favourites');
reset role;
select tests.check((select count(*) = 1 from public.conversations where cargo_owner_id = :u1 and carrier_user_id = :u2), 'F14 the chat itself is untouched');
select tests.summary('BƏYƏNDİKLƏRİM (0106)');
rollback;

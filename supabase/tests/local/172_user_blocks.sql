-- USERS BLOCK ONE ANOTHER — 0135. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set u1     '''a0000000-0000-4000-8000-000000000021'''
\set u2     '''a0000000-0000-4000-8000-000000000011'''
\set u3     '''a0000000-0000-4000-8000-000000000013'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
set role authenticated;
select tests.login(:u1);
insert into ids select 'd', (public.get_or_create_direct_conversation(:u2)).id;
insert into public.messages (conversation_id, sender_id, receiver_id, message)
values ((select id from ids where k='d'), :u1, :u2, 'Salam');
select tests.check((select count(*) = 1 from public.messages where conversation_id = (select id from ids where k='d')),
  'B1 before a block messages go as before');

select tests.check(tests.err(format($$ select public.user_block_set(%L, true) $$, :u1)) like '%invalid_user%', 'B2 never oneself');
select tests.check(tests.err($$ insert into public.user_blocks (blocker_id, blocked_id)
  values ('a0000000-0000-4000-8000-000000000021', 'a0000000-0000-4000-8000-000000000013') $$) like '%permission denied%',
  'B3 no direct writes');
select public.user_block_set(:u2, true);
select public.user_block_set(:u2, true);
select tests.check((select (public.user_block_state(:u2) ->> 'i_blocked')::boolean
                       and not (public.user_block_state(:u2) ->> 'blocked_me')::boolean), 'B4 the blocker sees "I blocked"');
select tests.check((select count(*) = 1 from public.user_blocks), 'B5 twice = once; he reads his own block');
select tests.check(tests.err(format($$ insert into public.messages (conversation_id, sender_id, receiver_id, message)
  values (%L, %L, %L, 'x') $$, (select id from ids where k='d'), :u1, :u2)) like '%user_blocked%',
  'B6 the blocker cannot write either');

select tests.login(:u2);
select tests.check((select (public.user_block_state(:u1) ->> 'blocked_me')::boolean
                       and not (public.user_block_state(:u1) ->> 'i_blocked')::boolean), 'B7 the blocked one learns only "blocked me"');
select tests.check((select count(*) = 0 from public.user_blocks), 'B8 …and cannot read the blocker''s list');
select tests.check(tests.err(format($$ insert into public.messages (conversation_id, sender_id, receiver_id, message)
  values (%L, %L, %L, 'x') $$, (select id from ids where k='d'), :u2, :u1)) like '%user_blocked%',
  'B9 the blocked one cannot write');
select tests.check(tests.err(format($$ select public.user_block_set(%L, false) $$, :u1)) is null
                   and (select (public.user_block_state(:u1) ->> 'blocked_me')::boolean),
  'B10 he cannot lift somebody else''s block');
select tests.check((select count(*) = 1 from public.messages where conversation_id = (select id from ids where k='d')),
  'B11 the old messages stay');

select tests.login(:u3);
insert into ids select 'e', (public.get_or_create_direct_conversation(:u2)).id;
insert into public.messages (conversation_id, sender_id, receiver_id, message)
values ((select id from ids where k='e'), :u3, :u2, 'Salam');
select tests.check(exists (select 1 from public.messages where conversation_id = (select id from ids where k='e')),
  'B12 other people write as before');

select tests.login(:u1);
select public.user_block_set(:u2, false);
insert into public.messages (conversation_id, sender_id, receiver_id, message)
values ((select id from ids where k='d'), :u1, :u2, 'Yenə salam');
select tests.check((select count(*) = 2 from public.messages where conversation_id = (select id from ids where k='d'))
                   and not (public.user_block_state(:u2) ->> 'i_blocked')::boolean, 'B13 unblocked: writing again');
reset role;
set role anon;
select tests.login(null);
select tests.check(tests.err(format($$ select public.user_block_set(%L, true) $$, :u2)) like '%permission denied%', 'B14 a visitor cannot block');
reset role;
select tests.summary('USER BLOCKS (0135)');
rollback;

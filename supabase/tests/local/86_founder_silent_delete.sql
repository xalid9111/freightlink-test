-- FOUNDER SILENT DELETE — 0048: the founder's "delete for everyone" leaves
-- no "deleted" line; everyone else keeps 0031. Rolled back.
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set founder '''a0000000-0000-4000-8000-0000000000f8'''
\set conv    '''c8600000-0000-4000-8000-000000000001'''
\set grp     '''c8600000-0000-4000-8000-0000000000aa'''
\set m1      '''e8600000-0000-4000-8000-000000000001'''
\set m2      '''e8600000-0000-4000-8000-000000000002'''
\set m3      '''e8600000-0000-4000-8000-000000000003'''
\set g1      '''e8600000-0000-4000-8000-0000000000b1'''
\set g2      '''e8600000-0000-4000-8000-0000000000b2'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :founder, 'authenticated', 'authenticated', 'xelilov.1881@gmail.com', '{"full_name":"Founder","role":"cargo_owner"}');
select public.founder_sync();
insert into public.conversations (id, cargo_owner_id, carrier_user_id) values (:conv, :founder, :other);
insert into public.messages (id, conversation_id, sender_id, receiver_id, message, created_at) values
  (:m1, :conv, :founder, :other, 'gizli', now() - interval '3 minutes'),
  (:m2, :conv, :other, :founder, 'salam', now() - interval '2 minutes'),
  (:m3, :conv, :founder, :other, 'qalsın', now() - interval '1 minutes');
insert into public.chat_groups (id, name, created_by) values (:grp, 'Test', :founder);
insert into public.chat_group_members (group_id, user_id) values (:grp, :founder), (:grp, :other), (:grp, :owner1);
insert into public.group_messages (id, group_id, sender_id, message) values (:g1, :grp, :founder, 'qrup gizli'), (:g2, :grp, :other, 'qrup adi');

set role authenticated;
-- The founder deletes his own message for everyone: no trace, and no
-- unread badge left for the other person.
select tests.login(:founder);
select public.delete_message(:m1, 'direct', 'everyone');
select tests.check((select deleted_silent and deleted_at is not null and message = '' and read_at is not null from public.messages where id = :m1),
  'S1 founder: direct message gone without a trace, counted as read');
select public.delete_message(:g1, 'group', 'everyone');
select tests.check((select deleted_silent and deleted_at is not null and message = '' from public.group_messages where id = :g1),
  'S2 founder: group message gone without a trace');
select tests.check((select not deleted_silent and message = 'qalsın' from public.messages where id = :m3), 'S3 his other messages stay');
select tests.check(tests.err(format($$ select public.delete_message(%L, 'direct', 'everyone') $$, :m2)) like '%not_your_message%',
  'S4 the founder still cannot delete the other person''s message for everyone');

-- Anyone else: the 0031 "This message was deleted" line stays.
select tests.login(:other);
select public.delete_message(:g2, 'group', 'everyone');
select tests.check((select not deleted_silent and deleted_at is not null from public.group_messages where id = :g2),
  'N1 a normal user''s delete-for-everyone is not silent');
select tests.login(:other);
update public.messages set deleted_silent = true where id = :m3;
select tests.login(:founder);
update public.messages set deleted_silent = true where id = :m3;
reset role;
select tests.check((select not deleted_silent from public.messages where id = :m3),
  'N2 nobody sets the flag directly (not even the founder, only through delete)');
select tests.check((select message = 'salam' and not deleted_silent from public.messages where id = :m2), 'N3 the other person''s message is untouched');

select tests.summary('FOUNDER SILENT DELETE (0048)');
rollback;

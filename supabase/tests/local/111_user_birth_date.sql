-- Age at registration and in Profil (0074). Rolled back.
\set u1 '''a0000000-0000-4000-8000-000000000012'''
\set u2 '''a0000000-0000-4000-8000-000000000021'''

begin;
-- Signup carries the birth date (the real signup trigger).
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000b1','authenticated','authenticated','b1@t.test','{"full_name":"Yaşlı","role":"carrier","birth_date":"1990-01-01"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000b2','authenticated','authenticated','b2@t.test','{"full_name":"Pis","role":"carrier","birth_date":"ab-cd"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000b3','authenticated','authenticated','b3@t.test','{"full_name":"Uşaq","role":"carrier","birth_date":"2024-01-01"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000b4','authenticated','authenticated','b4@t.test','{"full_name":"Admin olmaq","role":"admin","birth_date":"1985-01-01"}');
select tests.check((select birth_date = '1990-01-01' and role = 'carrier' from public.users where id = 'a0000000-0000-4000-8000-0000000000b1'),
  'B1 the birth date picked at signup is saved');
select tests.check((select birth_date is null from public.users where id = 'a0000000-0000-4000-8000-0000000000b2')
                   and (select birth_date is null from public.users where id = 'a0000000-0000-4000-8000-0000000000b3'),
  'B2 a bad or under-16 date never breaks the signup (saved empty)');
select tests.check((select role = 'cargo_owner' and birth_date = '1985-01-01' from public.users where id = 'a0000000-0000-4000-8000-0000000000b4'),
  'B3 the signup trigger still refuses role=admin (0018 kept)');

set role authenticated;
select tests.login(:u1);
update public.users set birth_date = '1995-01-01' where id = :u1;
select tests.check((select birth_date = '1995-01-01' from public.users where id = :u1), 'B4 the user sets his age in Profil');
select tests.check(tests.err($$ update public.users set birth_date = current_date - 365 where id = 'a0000000-0000-4000-8000-000000000012' $$)
  like '%invalid_birth_date%', 'B5 younger than 16 is refused');
update public.users set birth_date = '1990-01-01' where id = :u2;
select tests.login(:u2);
select tests.check((select birth_date is null from public.users where id = :u2), 'B6 nobody sets another user''s age');
select tests.check(not exists (select 1 from information_schema.columns where table_name = 'user_profiles' and column_name = 'birth_date')
                   and (select count(*) = 0 from public.users where id = :u1),
  'B7 the age is private (not in user_profiles; others cannot read the row)');
reset role;
select tests.summary('YAŞ (0074)');
rollback;

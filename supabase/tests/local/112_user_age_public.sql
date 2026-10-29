-- Age (years only) on other users' profiles (0075). Rolled back.
\set u1 '''a0000000-0000-4000-8000-000000000012'''
\set u2 '''a0000000-0000-4000-8000-000000000021'''

begin;
update public.users set birth_date = (current_date - interval '48 years')::date where id = :u1;
update public.users set birth_date = null where id = :u2;

set role authenticated;
select tests.login(:u2);
select tests.check(public.user_age(:u1) = 48, 'A1 another user sees the age as a number (48)');
select tests.check(public.user_age(:u2) is null, 'A2 no birth date given -> no age');
select tests.check((select count(*) = 0 from public.users where id = :u1)
                   and not exists (select 1 from information_schema.columns where table_name = 'user_profiles' and column_name = 'birth_date'),
  'A3 the birth date itself stays private');
reset role;
select tests.check(not has_function_privilege('anon', 'public.user_age(uuid)', 'execute'),
  'A4 not for signed-out visitors');
select tests.summary('YAŞ PROFİLDƏ (0075)');
rollback;

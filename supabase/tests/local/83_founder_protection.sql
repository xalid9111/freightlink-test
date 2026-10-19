-- FOUNDER PROTECTION — 0045: only the founder changes the founder's
-- account; other admins cannot. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set founder '''a0000000-0000-4000-8000-0000000000f1'''
\set fake    '''a0000000-0000-4000-8000-0000000000f2'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :founder, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder","role":"cargo_owner"}'),
  ('00000000-0000-0000-0000-000000000000', :fake,    'authenticated', 'authenticated', 'xelilov.1881@gmail.co',  '{"full_name":"Look alike","role":"cargo_owner"}');
update public.users set role = 'admin' where id in (:founder, :fake);
select tests.check(public.founder_sync() = 1, 'F1 founder bound by the exact e-mail (look-alike is not)');
select tests.check(public.founder_sync() = 0, 'F2 re-run binds nothing twice');

set role authenticated;
select tests.login(:admin);
select tests.check(public.is_founder(:founder) and not public.is_founder(:fake) and not public.is_founder(:admin),
  'F3 only the founder is the founder');
select tests.check((select array_agg(x) = array[:founder]::uuid[] from public.founder_ids() x), 'F4 admin panel sees which account is locked');

-- Another admin: every admin action on the founder is refused.
select tests.check(tests.err(format($$ select public.admin_update_user(%L, '{"role":"driver"}') $$, :founder)) like '%founder_protected%',
  'A1 another admin cannot change the founder''s role');
select tests.check(tests.err(format($$ select public.admin_update_user(%L, '{"is_verified":true}') $$, :founder)) like '%founder_protected%',
  'A2 …nor give / take the blue tick');
select tests.check(tests.err(format($$ select public.admin_set_user_block(%L, true, null, 'x') $$, :founder)) like '%founder_protected%',
  'A3 …nor block');
select tests.check(tests.err(format($$ select public.admin_set_user_active(%L, false) $$, :founder)) like '%founder_protected%',
  'A4 …nor deactivate');
select tests.check(tests.err(format($$ select public.admin_delete_user(%L, 'x') $$, :founder)) like '%founder_protected%',
  'A5 …nor delete');
select tests.check(tests.err(format($$ update public.users set role = 'driver', is_verified = true where id = %L $$, :founder)) like '%founder_protected%',
  'A6 …nor change the row through the API');
select tests.check(tests.err(format($$ delete from public.users where id = %L $$, :founder)) like '%founder_protected%',
  'A7 …nor delete the row through the API');
reset role;
select tests.check((select role = 'admin' and not is_verified and not is_blocked and is_active and full_name = 'Founder'
                      from public.users where id = :founder), 'A8 the founder''s account is unchanged');

-- Admins still manage everybody else.
set role authenticated;
select tests.login(:admin);
select public.admin_update_user(:fake, '{"is_verified":true}');
select tests.check((select is_verified from public.users where id = :fake), 'O1 admins still verify other accounts');
select public.admin_set_user_block(:other, true, null, 'test');
select tests.check((select is_blocked from public.users where id = :other), 'O2 admins still block other accounts');

-- A normal user cannot touch it either.
select tests.login(:other);
select tests.check(coalesce(tests.err(format($$ update public.users set full_name = 'x' where id = %L $$, :founder)), 'founder_protected') like '%founder_protected%',
  'U1 a normal user''s change is ignored (RLS) or refused');
reset role;
select tests.check((select full_name = 'Founder' from public.users where id = :founder), 'U2 a normal user cannot change the founder');

-- The founder himself can.
set role authenticated;
select tests.login(:founder);
select public.admin_update_user(:founder, '{"is_verified":true}');
select tests.check((select is_verified from public.users where id = :founder), 'S1 the founder gives himself the blue tick');
update public.users set full_name = 'Founder X' where id = :founder;
select tests.check((select full_name = 'Founder X' from public.users where id = :founder), 'S2 the founder edits his own profile');
reset role;
update public.users set is_verified = false where id = :founder;
select tests.check((select not is_verified from public.users where id = :founder), 'S3 the SQL editor (owner) can still change it');

reset role;
select tests.summary('FOUNDER PROTECTION (0045)');
rollback;

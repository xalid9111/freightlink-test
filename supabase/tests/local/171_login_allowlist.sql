-- WHO STAYS IN A CLOSED SITE — 0134: admins, the Baş admin and the accounts
-- given the permission; nobody gives himself the permission; the Auth hook
-- refuses a not-allowed token only while the site is closed. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set user1  '''a0000000-0000-4000-8000-000000000012'''
\set user2  '''a0000000-0000-4000-8000-000000000011'''

begin;
set role authenticated;
select tests.login(:user1);
select tests.check((select not (public.site_status() ->> 'allowed')::boolean), 'L1 an ordinary account is not on the list');
select tests.check((select (public.site_status() ->> 'closed') is not null and (public.site_status() ? 'admin')
                      and (public.site_status() ? 'message')), 'L2 the 0068 fields are still there');
select tests.check(tests.err(format($$ select public.admin_user_login_allowed_set(%L, true) $$, :user1)) like '%admin_only%',
  'L3 a user cannot give the permission');
select tests.check(tests.err(format($$ update public.users set login_allowed = true where id = %L $$, :user1)) like '%admin_only%',
  'L4 …nor give it to himself directly');
reset role;
set role anon;
select tests.login(null);
select tests.check(tests.err(format($$ select public.admin_user_login_allowed_set(%L, true) $$, :user1)) like '%permission denied%',
  'L5 a visitor cannot either');
select tests.check((select not (public.site_status() ->> 'allowed')::boolean), 'L6 a visitor is never "allowed"');
reset role;

-- Open site: the hook lets everybody in, as before.
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', :user1, 'claims', '{}'::jsonb)) ? 'claims'),
  'O1 open site: everybody signs in');

set role authenticated;
select tests.login(:admin);
select tests.check((select (public.site_status() ->> 'allowed')::boolean), 'A1 an admin is always allowed');
select public.admin_user_login_allowed_set(:user2, true);
select public.admin_set_site_status(true, 'Texniki işlər');
select tests.login(:user2);
select tests.check((select (public.site_status() ->> 'closed')::boolean and (public.site_status() ->> 'allowed')::boolean),
  'A2 closed site: the chosen account stays in');
select tests.login(:user1);
select tests.check((select (public.site_status() ->> 'closed')::boolean and not (public.site_status() ->> 'allowed')::boolean),
  'A3 …an ordinary account sees the notice');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'user.login_allowed' and entity_id = :user2),
  'A4 the permission is logged');

-- The Auth hook (runs as supabase_auth_admin, no auth.uid()).
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', :user1, 'claims', '{}'::jsonb)) ? 'error'),
  'H1 closed site: the hook refuses an ordinary account');
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', :user2, 'claims', '{}'::jsonb)) ? 'claims'),
  'H2 …lets the chosen one in');
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', :admin, 'claims', '{}'::jsonb)) ? 'claims'),
  'H3 …and every admin');
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', 'not-a-uuid', 'claims', '{}'::jsonb)) ? 'claims'),
  'H4 a broken event never locks anybody out');
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', gen_random_uuid(), 'claims', '{}'::jsonb)) ? 'error'),
  'H5 a new account (not on the list) is refused while closed: no registration');

set role authenticated;
select tests.login(:admin);
select public.admin_user_login_allowed_set(:user2, false);
select public.admin_set_site_status(false);
reset role;
select tests.check((select public.login_allowlist_hook(jsonb_build_object('user_id', :user1, 'claims', '{}'::jsonb)) ? 'claims'),
  'O2 opened again = everybody signs in');
select tests.check((select count(*) = 0 from public.users where login_allowed is not null and id <> :user2),
  'O3 nobody else was touched');
select tests.summary('CLOSED SITE ALLOW-LIST (0134)');
rollback;

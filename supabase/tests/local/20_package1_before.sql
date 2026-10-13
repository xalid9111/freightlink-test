-- =====================================================================
-- PACKAGE 1 — "BEFORE" suite. Runs on a DB with migrations 0001–0017
-- only. Every check here PASSES when the vulnerability is REPRODUCED,
-- i.e. it documents the root cause. Everything is rolled back.
-- =====================================================================
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set owner2  '''a0000000-0000-4000-8000-000000000012'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''
\set p2      '''5e000000-0000-4000-8000-000000000002'''
\set p6      '''5e000000-0000-4000-8000-000000000006'''

begin;

-- R1 signup with role=admin in metadata creates an admin --------------
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000ee','authenticated','authenticated','evil@t.test','{"full_name":"Evil","role":"admin"}');
select tests.check((select role from public.users where id = 'a0000000-0000-4000-8000-0000000000ee') = 'admin',
  'R1 signup metadata role=admin -> public.users.role = admin');

-- R2/R3 unrelated user sees a PENDING profile and every admin_note -----
set role authenticated;
select tests.login(:other);
select tests.check(exists (select 1 from public.service_providers where id = :p2),
  'R2 unrelated user can read a pending service profile');
select tests.check((select count(*) from public.service_providers where admin_note is not null) >= 2,
  'R3 unrelated user can read admin_note of other users'' profiles');

-- R4 nearby_services returns pending profiles and admin_note ----------
select tests.check(
  (select bool_or(e->>'status' = 'pending') and bool_or(e ? 'admin_note' and e->>'admin_note' is not null)
   from jsonb_array_elements(public.nearby_services(40.42, 49.88, 50)) e),
  'R4 nearby_services exposes pending profiles and admin_note');

-- R5 owner bypasses the guard with a session setting ------------------
select tests.login(:owner2);
select set_config('app.service_rating_sync', 'on', true);
update public.service_providers set status = 'approved', is_verified = true, rating_avg = 5, rating_count = 999
 where id = :p2;
select set_config('app.service_rating_sync', 'off', true);
select tests.check((select status = 'approved' and is_verified and rating_count = 999
                      from public.service_providers where id = :p2),
  'R5 owner self-approves/self-verifies/fakes rating via app.service_rating_sync');

-- R6 blocked owner can still edit their profile ------------------------
select tests.login(:blocked);
update public.service_providers set name = 'Edited while blocked' where id = :p6;
select tests.check((select name from public.service_providers where id = :p6) = 'Edited while blocked',
  'R6 blocked owner can still update their service profile');

-- R7 anon role holds EXECUTE on admin RPCs ----------------------------
reset role;
select tests.check(has_function_privilege('anon', 'public.admin_save_service(uuid, jsonb)', 'execute'),
  'R7 anon has EXECUTE on admin_save_service');

-- R8 SECURITY DEFINER functions without search_path -------------------
select tests.check(exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and p.proname in ('is_admin','current_carrier_id')
    and p.proconfig is null),
  'R8 is_admin()/current_carrier_id() are SECURITY DEFINER with no search_path');

-- R9 other users can read a user's internal block_reason --------------
set role authenticated;
select tests.login(:other);
select tests.check((select block_reason from public.users where id = :blocked) is not null,
  'R9 any signed-in user can read another user''s block_reason (NOT fixed in 0018 — see report)');
reset role;

select tests.summary('PACKAGE 1 BEFORE (vulnerabilities reproduced)');
rollback;

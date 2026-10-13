-- =====================================================================
-- PACKAGE 1 — "AFTER" suite. Runs on a DB with migrations 0001–0018.
-- Every check PASSES when the behaviour is SECURE and existing features
-- still work. Roles covered: owner, non-owner, admin, blocked user,
-- unauthenticated (anon), plus trusted server-side paths.
-- Everything is rolled back at the end.
-- =====================================================================
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set owner2  '''a0000000-0000-4000-8000-000000000012'''
\set owner3  '''a0000000-0000-4000-8000-000000000013'''
\set owner4  '''a0000000-0000-4000-8000-000000000014'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''
\set p1      '''5e000000-0000-4000-8000-000000000001'''
\set p2      '''5e000000-0000-4000-8000-000000000002'''
\set p3      '''5e000000-0000-4000-8000-000000000003'''
\set p4      '''5e000000-0000-4000-8000-000000000004'''
\set p5      '''5e000000-0000-4000-8000-000000000005'''
\set p6      '''5e000000-0000-4000-8000-000000000006'''
\set pubcols 'id, owner_id, kind, name, specialty, description, categories, country, city, address, lat, lng, is_mobile, service_radius_km, phone, whatsapp, working_hours, is_24h, is_active, status, is_verified, added_by_admin, photos, rating_avg, rating_count, created_at, updated_at'

begin;

-- =============== 1. SIGNUP ROLE =======================================
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000ee','authenticated','authenticated','evil@t.test','{"full_name":"Evil","role":"admin"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000ef','authenticated','authenticated','junk@t.test','{"full_name":"Junk","role":"superuser"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000f0','authenticated','authenticated','carr@t.test','{"full_name":"New carrier","role":"carrier","phone":"+994500000000"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000f1','authenticated','authenticated','drv@t.test', '{"full_name":"New driver","role":"driver"}'),
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000f2','authenticated','authenticated','none@t.test','{"full_name":"No role"}');
select tests.check((select role from public.users where id = 'a0000000-0000-4000-8000-0000000000ee') = 'cargo_owner',
  'S1 signup with role=admin becomes cargo_owner');
select tests.check((select role from public.users where id = 'a0000000-0000-4000-8000-0000000000ef') = 'cargo_owner',
  'S2 signup with unknown role becomes cargo_owner');
select tests.check((select role = 'carrier' and phone = '+994500000000' and full_name = 'New carrier'
                      from public.users where id = 'a0000000-0000-4000-8000-0000000000f0')
                   and exists (select 1 from public.carriers where user_id = 'a0000000-0000-4000-8000-0000000000f0')
                   and exists (select 1 from public.credit_wallets w join public.carriers c on c.id = w.carrier_id
                               where c.user_id = 'a0000000-0000-4000-8000-0000000000f0' and w.balance = 3),
  'S3 carrier signup still works (users row, carriers row, signup credits)');
select tests.check((select role from public.users where id = 'a0000000-0000-4000-8000-0000000000f1') = 'driver',
  'S4 driver signup keeps role driver');
select tests.check((select role from public.users where id = 'a0000000-0000-4000-8000-0000000000f2') = 'cargo_owner',
  'S5 signup without role defaults to cargo_owner');

-- =============== 2. VISIBILITY ========================================
set role authenticated;

select tests.login(:other);
select tests.check((select array_agg(name order by name) from public.service_providers)
                   = array['Admin Added Tow','Approved Garage'],
  'V1 non-owner sees only approved profiles of non-blocked owners');
select tests.check(not exists (select 1 from public.service_providers where id in (:p2, :p3, :p4, :p6)),
  'V2 non-owner cannot fetch pending/rejected/suspended/blocked-owner profiles by id');

select tests.login(:owner2);
select tests.check(exists (select 1 from public.service_providers where id = :p2),
  'V3 owner sees own PENDING profile');
select tests.check(not exists (select 1 from public.service_providers where id in (:p3, :p4)),
  'V4 owner does not see other owners'' non-approved profiles');
select tests.login(:owner3);
select tests.check(exists (select 1 from public.service_providers where id = :p3),
  'V5 owner sees own REJECTED profile');
select tests.login(:owner4);
select tests.check(exists (select 1 from public.service_providers where id = :p4),
  'V6 owner sees own SUSPENDED profile');

select tests.login(:blocked);
select tests.check((select count(*) from public.service_providers where id in (:p1, :p5, :p6)) = 3,
  'V7 blocked user sees public approved profiles and own profile');

select tests.login(:admin);
select tests.check((select count(*) from public.service_providers) = 6,
  'V8 admin sees all 6 profiles');

reset role;
set role anon;
select tests.login(null);
select tests.check(tests.err('select id from public.service_providers') like '%permission denied%',
  'V9 anonymous cannot read service profiles');
reset role;

-- =============== 3. admin_note ========================================
set role authenticated;
select tests.login(:other);
select tests.check(tests.err('select admin_note from public.service_providers') like '%permission denied%',
  'N1 non-owner: selecting admin_note is denied');
select tests.check(tests.err('select * from public.service_providers') like '%permission denied%',
  'N2 non-owner: select * is denied (clients must use explicit columns)');
select tests.check(tests.err('select ' || :'pubcols' || ' from public.service_providers') is null,
  'N3 non-owner: explicit public column list works');
select tests.check(not exists (select 1 from public.service_provider_notes(array[:p1, :p2, :p5]::uuid[])),
  'N4 non-owner: service_provider_notes() returns nothing for others'' profiles');
select tests.check(tests.err($$select admin_note from public.service_providers where id = '5e000000-0000-4000-8000-000000000001'$$) like '%permission denied%'
                   and tests.err($$select id from public.service_providers where admin_note ilike '%NOTE%'$$) like '%permission denied%',
  'N5 non-owner: cannot read or filter by admin_note');

select tests.login(:owner2);
select tests.check((select admin_note from public.service_provider_notes(array[:p2]::uuid[])) = 'NOTE-PENDING: waiting docs',
  'N6 owner reads own admin_note via service_provider_notes()');
select tests.check((select count(*) from public.service_provider_notes(array[:p1, :p2, :p3]::uuid[])) = 1,
  'N7 owner gets only own note when asking for several ids');

select tests.login(:admin);
select tests.check((select count(*) from public.service_provider_notes(array[:p1,:p2,:p3,:p4,:p5,:p6]::uuid[])) = 6,
  'N8 admin reads every admin_note via service_provider_notes()');
select tests.check(tests.err('select admin_note from public.service_providers') like '%permission denied%',
  'N9 admin direct column read also denied (admin uses RPC; documented)');

-- nearby_services --------------------------------------------------------
select tests.login(:other);
select tests.check(
  (select array_agg(e->>'name' order by e->>'name') from jsonb_array_elements(public.nearby_services(40.42, 49.88, 50)) e)
  = array['Admin Added Tow','Approved Garage'],
  'M1 nearby_services returns only approved, non-blocked-owner profiles');
select tests.check(
  (select bool_and(not (e ? 'admin_note')) from jsonb_array_elements(public.nearby_services(40.42, 49.88, 50)) e),
  'M2 nearby_services output has no admin_note key');
select tests.check(
  (select bool_and(e ? 'distance_km' and e ? 'rating_avg' and e ? 'photos' and e ? 'is_verified')
     from jsonb_array_elements(public.nearby_services(40.42, 49.88, 50)) e),
  'M3 nearby_services still returns the fields the app uses');
select tests.login(:owner2);
select tests.check(
  not exists (select 1 from jsonb_array_elements(public.nearby_services(40.42, 49.88, 50)) e where e->>'id' = '5e000000-0000-4000-8000-000000000002'),
  'M4 owner''s own pending profile is not on the public map');
select tests.login(:admin);
select tests.check(
  (select count(*) from jsonb_array_elements(public.nearby_services(40.42, 49.88, 50))) = 2,
  'M5 admin map also shows approved only (moderation list is separate)');

-- =============== 4. GUARD ============================================
-- G1: the old session-flag bypass no longer works
select tests.login(:owner2);
select set_config('app.service_rating_sync', 'on', true);
update public.service_providers set status = 'approved', is_verified = true, rating_avg = 5, rating_count = 999,
       added_by_admin = true, owner_id = :other, created_at = '2000-01-01'
 where id = :p2;
select set_config('app.service_rating_sync', 'off', true);
select tests.check((select status = 'pending' and not is_verified and rating_avg = 0 and rating_count = 0
                           and not added_by_admin and owner_id = 'a0000000-0000-4000-8000-000000000012'
                           and created_at > '2001-01-01'
                      from public.service_providers where id = :p2),
  'G1 owner cannot change status/verification/rating/ownership even with app.service_rating_sync=on');
select tests.check(tests.err($$update public.service_providers set admin_note = 'self note' where id = '5e000000-0000-4000-8000-000000000002'$$) is null
                   and (select admin_note from public.service_provider_notes(array[:p2]::uuid[])) = 'NOTE-PENDING: waiting docs',
  'G2 owner cannot overwrite admin_note');

select tests.login(:owner1);
update public.service_providers set name = 'Approved Garage 2', phone = '+994501112233', is_active = false where id = :p1;
select tests.check((select name = 'Approved Garage 2' and phone = '+994501112233' and not is_active and status = 'approved'
                      from public.service_providers where id = :p1),
  'G3 owner can still edit normal fields (name, phone, availability)');

select tests.login(:other);
update public.service_providers set name = 'hijack' where id = :p1;
select tests.check((select name from public.service_providers where id = :p1) = 'Approved Garage 2',
  'G4 non-owner cannot edit someone else''s profile');
delete from public.service_providers where id = :p1;
select tests.check(exists (select 1 from public.service_providers where id = :p1),
  'G5 non-owner cannot delete someone else''s profile');

select tests.login(:blocked);
select tests.check(tests.err($$update public.service_providers set name = 'edit while blocked' where id = '5e000000-0000-4000-8000-000000000006'$$) like '%account_blocked%',
  'G6 blocked owner cannot edit own profile');
select tests.check(tests.err($$insert into public.service_providers (name, lat, lng) values ('new while blocked', 40, 49)$$) is not null,
  'G7 blocked user cannot create a profile');

select tests.login(:other);
insert into public.service_providers (name, lat, lng, status, is_verified, owner_id, rating_avg, rating_count, added_by_admin, categories)
values ('Brand new', 40.40, 49.80, 'approved', true, :owner1, 4.9, 50, true, '{engine,not_a_category}');
-- (0028: new profiles are published at once — status 'approved' — but the
--  owner still cannot set verification / rating / owner / admin flags.)
select tests.check((select status = 'approved' and not is_verified and owner_id = 'a0000000-0000-4000-8000-000000000021'
                           and rating_avg = 0 and rating_count = 0 and not added_by_admin and categories = '{engine}'
                      from public.service_providers where name = 'Brand new'),
  'G8 new profile: published (0028), own owner, zero rating, not verified, known categories');
select tests.check(tests.err($$insert into public.service_providers (name, lat, lng) values ('second one', 40, 49)$$) is not null,
  'G9 one profile per account still enforced');

-- rating sync (trusted SECURITY DEFINER path) still works
update public.service_reviews set rating = 2 where provider_id = :p1 and user_id = :other;
select tests.check((select rating_avg = 2 and rating_count = 1 from public.service_providers where id = :p1),
  'G10 review update recalculates rating through the trusted path');
delete from public.service_reviews where provider_id = :p1 and user_id = :other;
select tests.check((select rating_avg = 0 and rating_count = 0 from public.service_providers where id = :p1),
  'G11 review delete recalculates rating');

-- admin paths
select tests.login(:admin);
select public.admin_set_service_status(:p2, 'approved', 'ok after call');
select tests.check((select status = 'approved' and is_verified from public.service_providers where id = :p2)
                   and (select admin_note from public.service_provider_notes(array[:p2]::uuid[])) = 'ok after call'
                   and exists (select 1 from public.admin_audit_log where action = 'service.status' and entity_id = '5e000000-0000-4000-8000-000000000002'),
  'G12 admin RPC approves, sets note, writes audit log');
update public.service_providers set status = 'suspended' where id = :p2;
select tests.check((select status from public.service_providers where id = :p2) = 'suspended',
  'G13 admin direct table update of status still allowed');
select tests.check((select (public.admin_save_service(null, '{"name":"Admin created","lat":40.1,"lng":49.1,"admin_note":"internal"}'::jsonb)).status) = 'approved',
  'G14 admin_save_service still creates approved profiles');

select tests.login(:other);
select tests.check(tests.err($$select public.admin_set_service_status('5e000000-0000-4000-8000-000000000003', 'approved')$$) like '%admin_only%',
  'G15 non-admin cannot call admin_set_service_status');
reset role;

-- =============== 5. SECURITY DEFINER / EXECUTE =======================
select tests.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c
                      where c like 'search_path=%'
                        and (substr(c, 13) in ('', '""') or substr(c, 13) ~* '(^|,)\s*"?pg_temp"?\s*$'))),
  'D1 every SECURITY DEFINER function in public has a safe search_path (pg_temp last)');
select tests.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'admin\_%' or p.proname in
      ('unlock_contact','get_or_create_conversation','get_or_create_direct_conversation','create_chat_group',
       'add_chat_group_members','remove_chat_group_member','rename_chat_group','mark_chat_group_read',
       'create_ad_order','submit_ad_payment','cancel_ad_order','delete_my_cargo','get_ad_payment_info',
       'nearby_services','service_provider_notes','_require_admin'))
      and has_function_privilege('anon', p.oid, 'execute')),
  'D2 anon has no EXECUTE on any admin or user RPC');
select tests.check(has_function_privilege('authenticated', 'public.nearby_services(double precision, double precision, double precision, text, numeric, boolean, text, text, integer)', 'execute')
                   and has_function_privilege('authenticated', 'public.admin_save_service(uuid, jsonb)', 'execute')
                   and has_function_privilege('authenticated', 'public.get_or_create_conversation(uuid, uuid, uuid)', 'execute')
                   and not has_function_privilege('authenticated', 'public._require_admin()', 'execute'),
  'D3 authenticated keeps EXECUTE on RPCs; _require_admin is internal only');
select tests.check((select prosecdef from pg_proc where proname = 'guard_service_provider') = false,
  'D4 guard_service_provider is SECURITY INVOKER');
select tests.check(not exists (select 1 from pg_proc where proname = 'recalc_service_rating' and prosrc ilike '%set_config%')
                   and not exists (select 1 from pg_proc where proname = 'guard_service_provider' and prosrc ilike '%current_setting%'),
  'D5 no session-setting bypass left in guard / recalc');

set role anon;
select tests.login(null);
select tests.check(tests.err('select public.admin_dashboard_stats()') like '%permission denied%',
  'D6 anon calling an admin RPC is refused at the privilege level');
select tests.check(tests.err('select count(*) from public.cargo') is null,
  'D7 anon queries on tables whose policies call is_admin() still work (helpers kept)');
reset role;

-- regression: other features that run through the touched functions
set role authenticated;
select tests.login('11111111-1111-1111-1111-111111111111');
select tests.check(tests.err($$select public.get_or_create_conversation((select id from public.cargo where owner_id = '22222222-2222-2222-2222-222222222222' limit 1))$$) is null,
  'D8 authenticated user can still open a cargo conversation');
select tests.check(public.is_admin() = false and (select count(*) from public.cargo) > 0,
  'D9 is_admin()/cargo listing still work for a normal user');
select tests.login(:other);
select tests.check(tests.err($$update public.users set role = 'admin', is_verified = true, full_name = 'D10 name' where id = 'a0000000-0000-4000-8000-000000000021'$$) is null
                   and (select role = 'cargo_owner' and not is_verified from public.users where id = 'a0000000-0000-4000-8000-000000000021'),
  'D10 own-profile update succeeds but cannot self-promote / self-verify');
reset role;

-- =============== 6. REPORTS CONSTRAINT ================================
select tests.check((select count(*) from pg_constraint
                     where conrelid = 'public.reports'::regclass and contype = 'c'
                       and conname = 'reports_target_type_check' and convalidated) = 1,
  'C1 exactly one validated reports_target_type_check');
select tests.check((select array_agg(distinct target_type order by target_type) from public.reports)
                   = array['cargo','message','offer','other','service','shipment','user'],
  'C2 all existing report target types preserved');
select tests.check((select pg_get_constraintdef(oid) from pg_constraint where conname = 'reports_target_type_check')
                   like '%status%' = false
                   and exists (select 1 from pg_constraint where conrelid = 'public.reports'::regclass and conname = 'reports_status_check'),
  'C3 unrelated reports constraints (status) untouched');
set role authenticated;
select tests.login(:other);
select tests.check(tests.err($$insert into public.reports (target_type, target_id, reason) values ('service', '5e000000-0000-4000-8000-000000000001', 'spam')$$) is null,
  'C4 user can still report a service');
select tests.check(tests.err($$insert into public.reports (target_type, target_id, reason) values ('bogus', 'x', 'r')$$) like '%reports_target_type_check%',
  'C5 unknown target_type is rejected');
reset role;

select tests.summary('PACKAGE 1 AFTER');
rollback;

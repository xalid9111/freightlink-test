-- =====================================================================
-- PACKAGE 1B — user privacy & account security. Runs on 0001–0019.
-- PASS = secure behaviour AND existing features still work.
-- Everything is rolled back at the end.
-- =====================================================================
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set owner2  '''a0000000-0000-4000-8000-000000000012'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''
\set cargo   '''c0000000-0000-4000-8000-0000000000c1'''

begin;

-- ---- setup (postgres) --------------------------------------------------
update public.users set phone = '+99450000' || right(id::text, 4)
 where id in (:owner1, :owner2, :other, :blocked, :admin);
-- owner2's load starts HIDDEN, so owner2 has no published open load yet
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, pickup_date, offered_price, is_hidden)
values (:cargo, :owner2, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 1000, current_date + 1, 500, true);

-- =============== 1. WHO CAN READ public.users ============================
set role authenticated;
select tests.login(:other);
select tests.check((select count(*) from public.users) = 1
                   and (select id from public.users) = 'a0000000-0000-4000-8000-000000000021',
  'P1 ordinary user reads only their own users row');
select tests.check(not exists (select 1 from public.users where id = :owner2)
                   and not exists (select 1 from public.users where email ilike '%owner%')
                   and not exists (select 1 from public.users where phone like '+994%' and id <> :other),
  'P2 other users'' e-mail / phone cannot be read or searched');
select tests.check(not exists (select 1 from public.users where id = :blocked and block_reason is not null),
  'P3 another user''s block_reason / block state is not readable');
select tests.check((select email = 'other@t.test' and phone is not null and preferred_lang is not null
                      from public.users where id = :other),
  'P4 user reads own e-mail, phone, language');

select tests.login(:blocked);
select tests.check((select is_blocked and block_reason = 'internal: suspected fraud' from public.users where id = :blocked),
  'P5 blocked user still reads own block state + reason (restriction banner)');

select tests.login(:admin);
select tests.check((select count(*) from public.users) = (select count(*) from public.user_profiles)
                   and (select count(*) from public.users) >= 10,
  'P6 admin reads every users row');
select tests.check((select block_reason from public.users where id = :blocked) = 'internal: suspected fraud'
                   and (select email from public.users where id = :owner2) = 'owner2@t.test'
                   and tests.err('select * from public.users') is null,
  'P7 admin reads e-mail, phone and moderation fields (select * works — admin panel / Realtime stream)');

-- public profile view -----------------------------------------------------
select tests.login(:other);
select tests.check((select count(*) from public.user_profiles) >= 10,
  'V1 any signed-in user sees every user''s public profile');
select tests.check((select array_agg(column_name::text order by ordinal_position) from information_schema.columns
                    where table_schema = 'public' and table_name = 'user_profiles')
                   = array['id','role','full_name','avatar_url','is_verified','is_early_member','last_seen_at','is_active','created_at'],
  'V2 view exposes exactly the public columns');
select tests.check(tests.err('select email from public.user_profiles') like '%does not exist%'
                   and tests.err('select block_reason from public.user_profiles') like '%does not exist%',
  'V3 private columns are not in the view');
select tests.check((select full_name from public.user_profiles where id = :owner2) = 'Owner pending',
  'V4 names/avatars of others still available (cards, chat headers)');
select tests.check((select count(*) from public.user_profiles where role = 'carrier' and is_active) >= 2
                   and (select count(*) from public.user_profiles where full_name ilike '%owner%') >= 4,
  'V5 carrier counter and people-picker search work on the view');
select tests.check(tests.err('insert into public.user_profiles (id, full_name) values (gen_random_uuid(), ''x'')') is not null
                   and tests.err($$update public.user_profiles set full_name = 'x' where id = 'a0000000-0000-4000-8000-000000000012'$$) is not null,
  'V6 view is read-only for users');
reset role;

set role anon;
select tests.login(null);
select tests.check(tests.err('select 1 from public.user_profiles') like '%permission denied%',
  'V7 anonymous cannot read the profile view');
select tests.check((select count(*) from public.users) = 0,
  'V8 anonymous reads no users rows');
select tests.check(tests.err($$select public.get_user_contact('a0000000-0000-4000-8000-000000000012')$$) like '%permission denied%',
  'V9 anonymous cannot call get_user_contact');
reset role;

-- =============== 2. CONTACT RULES =======================================
set role authenticated;
select tests.login(:owner1);  -- carrier, no relation to owner2 yet
select tests.check((select public.get_user_contact(:owner2)) @> '{"phone":null,"email":null,"reason":null}'
                   and (select public.get_user_contact(:owner2)->>'full_name') = 'Owner pending',
  'K1 no relation -> name only, no phone / e-mail');
reset role;
insert into public.contact_unlocks (carrier_id, cargo_id)
select c.id, :cargo from public.carriers c where c.user_id = :owner1;
set role authenticated;
select tests.login(:owner1);
select tests.check((select public.get_user_contact(:owner2)) @> '{"phone":"+994500000012","email":"owner2@t.test","reason":"unlocked"}',
  'K2 after a paid contact unlock -> phone + e-mail of that load owner');

select tests.login(:other);
select tests.check((select public.get_user_contact(:owner1)->>'phone') is null,
  'K3 unrelated user -> no phone');
reset role;
insert into public.conversations (id, cargo_id, cargo_owner_id, carrier_user_id)
values ('d0000000-0000-4000-8000-0000000000d1', null, :other, :owner1);
insert into public.messages (conversation_id, sender_id, receiver_id, message)
values ('d0000000-0000-4000-8000-0000000000d1', :owner1, :other, 'Salam');
set role authenticated;
select tests.login(:other);
select tests.check((select public.get_user_contact(:owner1)) @> '{"phone":"+994500000011","email":null,"reason":"messaged_you"}',
  'K4 the person wrote to you -> phone (call button in chat), no e-mail');
select tests.login(:owner1);
select tests.check((select public.get_user_contact(:other)->>'phone') is null,
  'K5 writing to someone does NOT reveal THEIR phone to you');

reset role;
insert into public.ads (advertiser_id, image_url, starts_at, ends_at, is_active)
values (:owner2, 'https://x/y.png', now() - interval '1 day', now() + interval '1 day', true),
       (:other,  'https://x/z.png', now() - interval '9 day', now() - interval '1 day', true);
set role authenticated;
select tests.login(:other);
select tests.check((select public.get_user_contact(:owner2)) @> '{"phone":"+994500000012","email":null,"reason":"advertiser"}',
  'K6 live advertiser -> phone on their profile');
select tests.login(:owner2);
select tests.check((select public.get_user_contact(:other)->>'phone') is null,
  'K7 expired advert -> no phone');

select tests.login(:admin);
select tests.check((select public.get_user_contact(:blocked)) @> '{"email":"blocked@t.test","reason":"admin"}',
  'K8 admin -> phone + e-mail');
select tests.login(:owner2);
select tests.check((select public.get_user_contact(:owner2)) @> '{"email":"owner2@t.test","reason":"self"}',
  'K9 self -> own phone + e-mail');
select tests.login(:blocked);
select tests.check((select public.get_user_contact(:owner2)->>'phone') is null,
  'K10 blocked caller gets no phone even for a live advertiser');
select tests.check(public.get_user_contact('a0000000-0000-4000-8000-0000000000ff') is null,
  'K11 unknown user -> null');
reset role;

-- load contact block (get_cargo_contact) + open-load rule -------------------
set role authenticated;
select tests.login(:other);
select tests.check(public.get_cargo_contact(:cargo) is null,
  'L1 hidden load: no contact for an unrelated user');
select tests.login(:owner1);  -- has a contact unlock on this load -> can_see_hidden_cargo? no (not offer/chat); still null
select tests.check(public.get_cargo_contact(:cargo) is null,
  'L2 hidden load: still no contact through the load page');
reset role;
select tests.login(null);
update public.cargo set is_hidden = false where id = :cargo;
set role authenticated;
select tests.login(:other);
select tests.check((select public.get_cargo_contact(:cargo)) @> '{"phone":"+994500000012","email":"owner2@t.test","full_name":"Owner pending"}',
  'L3 visible load: poster''s name, phone, e-mail on the load page (marketplace behaviour kept)');
select tests.check((select public.get_user_contact(:owner2)) @> '{"phone":"+994500000012","email":null}',
  'L4 user with an open published load: phone on their public profile');
select tests.login(:blocked);
select tests.check(public.get_cargo_contact(:cargo) is null,
  'L5 blocked caller gets no load contact');
select tests.login(:owner2);
select tests.check((select public.get_cargo_contact(:cargo)->>'email') = 'owner2@t.test',
  'L6 owner sees own load contact');
select tests.login(:other);
select tests.check(public.get_cargo_contact('c0000000-0000-4000-8000-0000000000ff') is null,
  'L7 unknown load -> null');
reset role;
select tests.check(not has_function_privilege('anon', 'public.get_cargo_contact(uuid)', 'execute'),
  'L8 anonymous cannot call get_cargo_contact');
select tests.login(null);
update public.cargo set is_hidden = true where id = :cargo;

-- =============== 3. NO ROLE / FLAG ESCALATION ============================
set role authenticated;
select tests.login(:other);
update public.users
   set role = 'admin', is_verified = true, is_early_member = false, is_blocked = true,
       is_active = false, email = 'admin@t.test', created_at = '2000-01-01',
       full_name = 'Renamed', phone = '+994559999999'
 where id = :other;
select tests.check((select role = 'cargo_owner' and not is_verified and is_early_member and not is_blocked and is_active
                           and email = 'other@t.test' and created_at > '2001-01-01'
                      from public.users where id = :other),
  'E1 user cannot change role / verification / moderation flags / e-mail / created_at');
select tests.check((select full_name = 'Renamed' and phone = '+994559999999' from public.users where id = :other),
  'E2 user can still change own name and phone (profile screen)');
select tests.check(public.is_admin() = false,
  'E3 is_admin() still false after the attempt');

select tests.login(:blocked);
update public.users set is_blocked = false, blocked_until = null, block_reason = null where id = :blocked;
select tests.check((select is_blocked and block_reason is not null from public.users where id = :blocked),
  'E4 blocked user cannot unblock themselves');

select tests.login(:other);
update public.users set full_name = 'hijack' where id = :owner2;
reset role;
select tests.check((select full_name from public.users where id = :owner2) = 'Owner pending',
  'E5 user cannot edit another user''s row');
set role authenticated;
select tests.check(tests.err($$insert into public.users (id, role, full_name, email) values (gen_random_uuid(), 'admin', 'x', 'x@x.x')$$) is not null,
  'E6 user cannot insert a users row (e.g. a second admin account)');
select tests.check(tests.err($$select public.admin_update_user('a0000000-0000-4000-8000-000000000021', '{"role":"admin"}')$$) like '%admin_only%',
  'E7 admin_update_user refuses non-admins');
-- forged context: JWT without sub -> auth.uid() null -> no row matches
select set_config('request.jwt.claims', '{"role":"authenticated"}', false);
select set_config('request.jwt.claim.sub', '', false);
update public.users set role = 'admin' where id = :other;
reset role;
select tests.check((select role from public.users where id = :other) = 'cargo_owner',
  'E8 request without a user id cannot update anyone (old auth.uid()-is-null shortcut gone)');
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000','a0000000-0000-4000-8000-0000000000e9','authenticated','authenticated','evil2@t.test','{"role":"admin"}');
select tests.check((select role from public.users where id = 'a0000000-0000-4000-8000-0000000000e9') = 'cargo_owner',
  'E9 signup with role=admin still becomes cargo_owner (0018)');

set role authenticated;
select tests.login(:admin);
select public.admin_update_user(:owner2, '{"is_verified":true}');
update public.users set block_reason = 'admin direct edit' where id = :blocked;
reset role;
select tests.check((select is_verified from public.users where id = :owner2)
                   and (select block_reason from public.users where id = :blocked) = 'admin direct edit',
  'E10 admin can still edit users (RPC and direct)');
select tests.login(:admin);
select public.admin_set_user_block(:owner2, true, null, 'test');
select tests.check((select is_blocked from public.users where id = :owner2),
  'E11 admin block via RPC still works');

-- user edits own auth metadata (supabase.auth.updateUser(data: {role: 'admin'}))
update auth.users set raw_user_meta_data = raw_user_meta_data || '{"role":"admin"}' where id = :other;
select tests.check((select role from public.users where id = :other) = 'cargo_owner'
                   and not exists (select 1 from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal
                                   and tgtype & 16 = 16),
  'E12 changing own auth metadata (role=admin) does not change public.users.role (no UPDATE trigger on auth.users)');

-- =============== 4. FEATURE REGRESSION ===================================
set role authenticated;
select tests.login(:other);
select tests.check(tests.err($$select public.get_or_create_direct_conversation('a0000000-0000-4000-8000-000000000014')$$) is null,
  'F1 direct chat with any user still opens');
select tests.check(tests.err($$select public.create_chat_group('Test group', array['a0000000-0000-4000-8000-000000000011','a0000000-0000-4000-8000-000000000014']::uuid[])$$) is null,
  'F2 group creation with members still works');
select tests.check((select count(*) from public.cargo) > 0,
  'F3 load list still readable');
select tests.check(tests.err($$insert into public.reports (target_type, target_id, reason) values ('user', 'a0000000-0000-4000-8000-000000000012', 'spam')$$) is null,
  'F4 reporting a user still works');
reset role;
select tests.check(exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'users'),
  'F5 users still in the Realtime publication (admin live list)');
select tests.check(not exists (select 1 from pg_policies where tablename = 'users' and policyname = 'users_select_all')
                   and exists (select 1 from pg_policies where tablename = 'users' and policyname = 'users_select_own'),
  'F6 policy set on users is as intended');
select tests.check((select prosecdef from pg_proc where proname = 'guard_user_protected_columns') = false
                   and has_function_privilege('authenticated', 'public.get_user_contact(uuid)', 'execute')
                   and not has_function_privilege('anon', 'public.get_user_contact(uuid)', 'execute'),
  'F7 guard is SECURITY INVOKER; contact RPC is signed-in only');

select tests.summary('PACKAGE 1B AFTER');
rollback;

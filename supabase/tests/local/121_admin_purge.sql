-- Admin: delete test data for good — 0083. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set real    '''a0000000-0000-4000-8000-000000000021'''
\set fake    '''f0000000-0000-4000-8000-0000000000f1'''
\set fake2   '''f0000000-0000-4000-8000-0000000000f2'''

begin;
-- Two fake profiles (through Auth, like a real signup) with test data.
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000', :fake,  'authenticated', 'authenticated', 'fake1@t.test', '{"full_name":"Saxta Profil"}'),
 ('00000000-0000-0000-0000-000000000000', :fake2, 'authenticated', 'authenticated', 'fake2@t.test', '{"full_name":"Saxta İki"}');
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values ('c0000000-0000-4000-8000-0000000000c1', :fake, 'Azerbaijan', 'Saxtakənd', 'Georgia', 'Tbilisi', 1000, 100, current_date),
       ('c0000000-0000-4000-8000-0000000000c2', :real, 'Azerbaijan', 'Baku', 'Georgia', 'Batumi', 1000, 100, current_date),
       ('c0000000-0000-4000-8000-0000000000c3', :fake2, 'Azerbaijan', 'Gəncə', 'Turkey', 'Kars', 1000, 100, current_date);
-- A chat of the fake profile with a real person (and one between real people).
insert into public.conversations (id, cargo_owner_id, carrier_user_id)
values ('d0000000-0000-4000-8000-0000000000f1', :real, :fake),
       ('d0000000-0000-4000-8000-0000000000f2', :real, 'a0000000-0000-4000-8000-000000000011');
insert into public.messages (conversation_id, sender_id, receiver_id, message)
values ('d0000000-0000-4000-8000-0000000000f1', :fake, :real, 'Salam'),
       ('d0000000-0000-4000-8000-0000000000f1', :real, :fake, 'Salam'),
       ('d0000000-0000-4000-8000-0000000000f2', :real, 'a0000000-0000-4000-8000-000000000011', 'Real');
insert into public.service_providers (id, owner_id, name, lat, lng, status, categories)
values ('5e000000-0000-4000-8000-0000000000f1', :fake, 'Saxta Servis', 40.5, 49.9, 'approved', '{engine}');
insert into public.service_reviews (provider_id, user_id, rating, comment)
values ('5e000000-0000-4000-8000-0000000000f1', :real, 5, 'ok'),
       ('5e000000-0000-4000-8000-000000000001', :fake, 1, 'saxta şərh');
insert into public.tir_parks (id, name, lat, lng, status, created_by)
values ('7a000000-0000-4000-8000-0000000000f1', 'Saxta Park', 40.9, 45.1, 'approved', :fake);
set local app.market_trusted = '1';
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status)
values ('e0000000-0000-4000-8000-0000000000f1', :fake, 'truck', 'DAF', 'XF', 100, 'AZN', 'active'),
       ('e0000000-0000-4000-8000-0000000000f2', :fake2, 'truck', 'MAN', 'TGX', 100, 'AZN', 'active');
set local app.market_trusted = '';
insert into public.job_vacancies (id, owner_id, company_name, specialties)
values ('b0000000-0000-4000-8000-0000000000f1', :fake, 'Saxta MMC', '{}'),
       ('b0000000-0000-4000-8000-0000000000f2', :fake2, 'Saxta İki MMC', '{}');
insert into public.job_seeker_profiles (user_id, full_name, specialties) values (:fake, 'Saxta Sürücü', '{}'), (:fake2, 'Saxta İki', '{}');
create temp table before_real on commit drop as
  select (select count(*) from public.users) as users, (select count(*) from public.cargo where owner_id <> :fake) as cargo;

set role authenticated;
-- ---- only admins ----------------------------------------------------------
select tests.login(:real);
select tests.check(tests.err($$ select public.admin_purge('user', 'f0000000-0000-4000-8000-0000000000f1', 'SİL') $$) like '%admin_only%',
  'A1 a normal user cannot delete anything');
select tests.check(tests.err($$ select public.admin_purge_list('user', null, 10) $$) like '%admin_only%', 'A2 …nor list it');
select tests.login(null);
select tests.check(tests.err($$ select public.admin_purge('cargo', 'c0000000-0000-4000-8000-0000000000c1', 'SİL') $$) is not null,
  'A3 nobody signed out');

select tests.login(:admin);
select tests.check(exists (select 1 from jsonb_array_elements(public.admin_purge_list('user', 'saxta', 50)) e
                    where e ->> 'id' = 'f0000000-0000-4000-8000-0000000000f1'),
  'L1 the admin finds the fake profile by name');
select tests.check(jsonb_array_length(public.admin_purge_list('cargo', 'Saxtakənd', 50)) = 1, 'L2 …a load by city');
select tests.check(jsonb_array_length(public.admin_purge_list('market', 'DAF', 50)) >= 1
                   and jsonb_array_length(public.admin_purge_list('job_vacancy', 'Saxta', 50)) = 2
                   and jsonb_array_length(public.admin_purge_list('job_seeker', 'Saxta', 50)) = 2
                   and jsonb_array_length(public.admin_purge_list('service', 'Saxta', 50)) = 1,
  'L3 …sale ads, job ads, driver profiles, services');

-- ---- guards -----------------------------------------------------------------
select tests.check(tests.err($$ select public.admin_purge('user', 'f0000000-0000-4000-8000-0000000000f1', 'sil') $$) like '%confirm_required%',
  'G1 nothing without typing SİL');
select tests.check(tests.err($$ select public.admin_purge('user', 'a0000000-0000-4000-8000-000000000001', 'SİL') $$) like '%cannot_delete_self%',
  'G2 never oneself');
reset role;
update public.users set role = 'admin' where id = 'a0000000-0000-4000-8000-000000000011';
set role authenticated;
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_purge('user', 'a0000000-0000-4000-8000-000000000011', 'SİL') $$) like '%admin_protected%',
  'G3 never another admin');
select tests.check(tests.err($$ select public.admin_purge('table', gen_random_uuid(), 'SİL') $$) like '%invalid_argument%', 'G4 only the six kinds');
select tests.check(tests.err($$ select public.admin_purge('cargo', gen_random_uuid(), 'SİL') $$) like '%not_found%', 'G5 unknown id');

-- ---- one item ----------------------------------------------------------------
select public.admin_purge('market', 'e0000000-0000-4000-8000-0000000000f2', 'SİL');
select public.admin_purge('job_vacancy', 'b0000000-0000-4000-8000-0000000000f2', 'SİL');
select public.admin_purge('job_seeker', 'f0000000-0000-4000-8000-0000000000f2', 'SİL');
select public.admin_purge('cargo', 'c0000000-0000-4000-8000-0000000000c3', 'SİL');
reset role;
select tests.check(not exists (select 1 from public.market_listings where id = 'e0000000-0000-4000-8000-0000000000f2')
               and not exists (select 1 from public.job_vacancies where id = 'b0000000-0000-4000-8000-0000000000f2')
               and not exists (select 1 from public.job_seeker_profiles where user_id = :fake2)
               and not exists (select 1 from public.cargo where id = 'c0000000-0000-4000-8000-0000000000c3')
               and exists (select 1 from public.users where id = :fake2),
  'I1 one sale ad / job ad / driver profile / load goes alone; its owner stays');

-- ---- a whole fake profile ------------------------------------------------------
set role authenticated;
select tests.login(:admin);
select tests.check((public.admin_purge('user', 'f0000000-0000-4000-8000-0000000000f1', 'SİL') ->> 'deleted')::int = 1, 'U1 the profile is deleted');
reset role;
select tests.check(not exists (select 1 from public.users where id = :fake) and not exists (select 1 from auth.users where id = :fake),
  'U2 the account and its sign-in are gone');
select tests.check(not exists (select 1 from public.cargo where owner_id = :fake)
               and not exists (select 1 from public.service_providers where id = '5e000000-0000-4000-8000-0000000000f1')
               and not exists (select 1 from public.market_listings where owner_id = :fake)
               and not exists (select 1 from public.job_vacancies where owner_id = :fake)
               and not exists (select 1 from public.job_seeker_profiles where user_id = :fake)
               and not exists (select 1 from public.service_reviews where user_id = :fake)
               and not exists (select 1 from public.tir_parks where created_by = :fake or id = '7a000000-0000-4000-8000-0000000000f1'),
  'U3 its loads, service, TIR park, sale and job ads, driver profile and comments are gone');
select tests.check(not exists (select 1 from public.conversations where id = 'd0000000-0000-4000-8000-0000000000f1')
               and not exists (select 1 from public.messages where sender_id = :fake or receiver_id = :fake),
  'U4 its chats and messages are gone ("Hamısını sil")');
select tests.check(exists (select 1 from public.conversations where id = 'd0000000-0000-4000-8000-0000000000f2')
               and exists (select 1 from public.messages where message = 'Real')
               and exists (select 1 from public.cargo where id = 'c0000000-0000-4000-8000-0000000000c2')
               and exists (select 1 from public.service_providers where id = '5e000000-0000-4000-8000-000000000001')
               and exists (select 1 from public.users where id = :real),
  'U5 real people, their loads, chats and services stay');
select tests.check((select count(*) from public.users) = (select users from before_real) - 1, 'U6 exactly one user less');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'purge.user' and entity_id = 'f0000000-0000-4000-8000-0000000000f1'
                           and admin_id = :admin and old_value ->> 'email' = 'fake1@t.test'),
  'U7 the admin log keeps who deleted whom');
select tests.summary('ADMİN: TEST MƏLUMATLARINI SİL (0083)');

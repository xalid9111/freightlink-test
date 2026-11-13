-- 0119: a deleted user's ads leave every list; "Hesabı sil". Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set real    '''a0000000-0000-4000-8000-000000000021'''
\set gone    '''f0000000-0000-4000-8000-0000000001a1'''
\set self    '''f0000000-0000-4000-8000-0000000001a2'''
\set chief   '''a0000000-0000-4000-8000-0000000000f1'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000', :gone, 'authenticated', 'authenticated', 'gone@t.test', '{"full_name":"Gedən"}'),
 ('00000000-0000-0000-0000-000000000000', :self, 'authenticated', 'authenticated', 'self@t.test', '{"full_name":"Özü"}'),
 ('00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder"}')
 on conflict (id) do nothing;
update public.users set role = 'admin' where id = :chief;
-- Each user: a load, a TIR Bazarı ad, a service, a vacancy, a driver profile, an empty truck.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values ('c0000000-0000-4000-8000-0000000001a1', :gone, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 1000, 100, current_date),
       ('c0000000-0000-4000-8000-0000000001a2', :self, 'Azerbaijan', 'Baku', 'Georgia', 'Batumi', 1000, 100, current_date),
       ('c0000000-0000-4000-8000-0000000001a3', :real, 'Azerbaijan', 'Baku', 'Turkey', 'Kars', 1000, 100, current_date);
set local app.market_trusted = '1';
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status)
values ('e0000000-0000-4000-8000-0000000001a1', :gone, 'truck', 'DAF', 'XF', 100, 'AZN', 'active'),
       ('e0000000-0000-4000-8000-0000000001a2', :self, 'truck', 'MAN', 'TGX', 100, 'AZN', 'active'),
       ('e0000000-0000-4000-8000-0000000001a3', :real, 'truck', 'Volvo', 'FH', 100, 'AZN', 'active');
set local app.market_trusted = '';
insert into public.service_providers (id, owner_id, name, lat, lng, status, categories)
values ('5e000000-0000-4000-8000-0000000001a1', :gone, 'Gedən Servis', 40.5, 49.9, 'approved', '{engine}'),
       ('5e000000-0000-4000-8000-0000000001a2', :self, 'Öz Servis', 40.5, 49.9, 'approved', '{engine}');
insert into public.job_vacancies (id, owner_id, company_name, specialties)
values ('b0000000-0000-4000-8000-0000000001a1', :gone, 'Gedən MMC', '{}'),
       ('b0000000-0000-4000-8000-0000000001a2', :self, 'Öz MMC', '{}');
insert into public.job_seeker_profiles (user_id, full_name, specialties) values (:gone, 'Gedən', '{}'), (:self, 'Özü', '{}');
insert into public.empty_truck_ads (owner_id, from_city, from_country, any_direction, truck_type, free_tons)
values (:gone, 'Baku', 'Azerbaijan', true, 'tent', 10), (:self, 'Baku', 'Azerbaijan', true, 'tent', 10), (:real, 'Baku', 'Azerbaijan', true, 'ref', 5);
create temp table real_before on commit drop as
  select (select count(*) from public.cargo where owner_id = :real and not is_hidden) c,
         (select count(*) from public.market_listings where owner_id = :real and status = 'active') m,
         (select count(*) from public.empty_truck_ads where owner_id = :real and status = 'active') e;

-- 1) The admin deletes a user: every ad of his goes from the lists.
set role authenticated;
select tests.login(:admin);
select public.admin_delete_user(:gone, 'test');
reset role;
select tests.check((select is_hidden from public.cargo where id = 'c0000000-0000-4000-8000-0000000001a1'), 'D1 his load hidden');
select tests.check((select status = 'inactive' from public.market_listings where id = 'e0000000-0000-4000-8000-0000000001a1'), 'D2 his TIR Bazarı ad inactive');
select tests.check((select status = 'suspended' from public.service_providers where id = '5e000000-0000-4000-8000-0000000001a1'), 'D3 his service suspended');
select tests.check((select is_hidden from public.job_vacancies where id = 'b0000000-0000-4000-8000-0000000001a1')
               and (select is_hidden from public.job_seeker_profiles where user_id = :gone), 'D4 his job ads hidden');
select tests.check((select bool_and(status = 'paused') from public.empty_truck_ads where owner_id = :gone), 'D5 his empty truck paused');
select tests.check((select count(*) = 1 from public.cargo where id = 'c0000000-0000-4000-8000-0000000001a1')
               and (select count(*) = 1 from public.market_listings where id = 'e0000000-0000-4000-8000-0000000001a1'), 'D6 nothing deleted');

-- 2) A user deletes his own account.
set role authenticated;
select tests.login(:self);
select tests.check(tests.err($$ select public.delete_my_account('yes') $$) like '%confirm_required%', 'S1 asked to confirm');
select public.delete_my_account('DELETE');
reset role;
select tests.check((select full_name = 'Silinmiş istifadəçi' and not is_active and is_blocked and phone is null
                           and email like 'deleted-%@deleted.tirlink.app' from public.users where id = :self), 'S2 the account closed, name gone');
select tests.check((select email like 'deleted-%' from auth.users where id = :self), 'S3 the sign-in e-mail freed');
select tests.check((select is_paused from public.cargo where id = 'c0000000-0000-4000-8000-0000000001a2')
               and (select status = 'inactive' from public.market_listings where id = 'e0000000-0000-4000-8000-0000000001a2')
               and (select status = 'suspended' from public.service_providers where id = '5e000000-0000-4000-8000-0000000001a2')
               and (select status = 'closed' from public.job_vacancies where id = 'b0000000-0000-4000-8000-0000000001a2')
               and (select not is_active from public.job_seeker_profiles where user_id = :self)
               and (select bool_and(status = 'paused') from public.empty_truck_ads where owner_id = :self), 'S4 all his ads hidden');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'account.self_delete' and entity_id = :self::text), 'S5 logged');

-- 3) Others untouched; admins / the Founder cannot delete themselves; visitors cannot call it.
select tests.check((select c = (select count(*) from public.cargo where owner_id = :real and not is_hidden)
                       and m = (select count(*) from public.market_listings where owner_id = :real and status = 'active')
                       and e = (select count(*) from public.empty_truck_ads where owner_id = :real and status = 'active') from real_before),
  'O1 other users'' ads untouched');
set role authenticated;
select tests.login(:admin);
select tests.check(tests.err($$ select public.delete_my_account('DELETE') $$) like '%admin_cannot_delete%', 'O2 an admin cannot delete himself');
reset role;
set role anon;
select tests.check(tests.err($$ select public.delete_my_account('DELETE') $$) is not null, 'O3 visitors cannot');
reset role;
select tests.check(tests.err($$ set role authenticated; select public._hide_user_ads('a0000000-0000-4000-8000-000000000021') $$) is not null, 'O4 the helper is server-only');
reset role;
rollback;

-- No admin approval for services, shops and parking spots — 0099. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner2  '''a0000000-0000-4000-8000-000000000012'''
\set user    '''a0000000-0000-4000-8000-000000000021'''
\set p2      '''5e000000-0000-4000-8000-000000000002'''
\set p3      '''5e000000-0000-4000-8000-000000000003'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
select tests.check((select status = 'approved' from public.service_providers where id = :p2), 'N1 the waiting service was published once');
select tests.check((select status = 'rejected' from public.service_providers where id = :p3), 'N2 a rejected one stays rejected');

-- Even if an old guard brings 'pending' back (0018 re-run), the last trigger publishes.
set role authenticated;
select tests.login(:user);
insert into public.service_providers (name, lat, lng, categories, status) values ('Yeni Servis', 40.5, 49.9, '{tyres}', 'pending');
select tests.check((select status = 'approved' from public.service_providers where name = 'Yeni Servis'), 'N3 a new service is published at once');
update public.service_providers set status = 'pending' where name = 'Yeni Servis';
select tests.check((select status = 'approved' from public.service_providers where name = 'Yeni Servis'), 'N4 the owner cannot put it back to waiting');
delete from public.service_providers where name = 'Yeni Servis';
insert into public.service_providers (name, lat, lng, categories) values ('Yeni Servis 2', 40.6, 49.9, '{tyres}');
select tests.check((select status = 'approved' from public.service_providers where name = 'Yeni Servis 2'),
  'N5 deleted and made again: published at once (the owner''s case)');
select tests.check(exists (select 1 from jsonb_array_elements(public.nearby_services(40.6, 49.9, 20)) e where e->>'name' = 'Yeni Servis 2'),
  'N6 on the map right away');

-- Parking spot: at once.
insert into ids values ('s', public.tir_park_add('Ələt dayanacağı', 39.95, 49.40, null, '{}', null));
select tests.check((select status = 'approved' from public.tir_parks where id = (select id from ids where k='s')),
  'N7 "Dayanacaq əlavə et": shown at once');
select tests.login(:owner2);
select tests.check(exists (select 1 from public.tir_parks where id = (select id from ids where k='s')), 'N8 everybody sees it');

-- The admin still takes one down.
select tests.login(:admin);
select public.admin_tir_park_set_status((select id from ids where k='s'), 'hidden');
select tests.check((select status = 'hidden' from public.tir_parks where id = (select id from ids where k='s')), 'N9 the admin can still hide a spot');
select public.admin_set_service_status((select id from public.service_providers where name = 'Yeni Servis 2'), 'suspended', 'test');
select tests.check((select status = 'suspended' from public.service_providers where name = 'Yeni Servis 2'), 'N10 …and suspend a service');
reset role;
select tests.check(to_regprocedure('public.tir_park_owner_apply(text)') is not null, 'N11 "Park işlədirəm" still goes through the admin');
select tests.summary('ADMİN TƏSDİQİ YOXDUR: SERVİS · MAĞAZA · DAYANACAQ (0099)');
rollback;

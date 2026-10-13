-- SERVICES — 0028: auto-publish + PRO. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:other);
insert into public.service_providers (name, lat, lng, categories, is_pro, status)
values ('Utep Test', 40.44, 49.78, '{advertising}', true, 'pending');
select tests.check((select status = 'approved' and not is_pro from public.service_providers where name = 'Utep Test'),
  'P1 new profile is published at once; owner cannot make it PRO');
select tests.check(exists (select 1 from jsonb_array_elements(public.nearby_services(40.42, 49.80, 50, 'advertising')) e
                           where e->>'name' = 'Utep Test'),
  'P2 it is found on the map right away (category filter)');
update public.service_providers set is_pro = true where name = 'Utep Test';
select tests.check((select not is_pro from public.service_providers where name = 'Utep Test'), 'P3 owner cannot switch PRO on by editing');
select tests.check(tests.err(format($$ select public.admin_set_service_pro(%L, true) $$,
  (select id from public.service_providers where name = 'Utep Test'))) like '%admin_only%', 'P4 only admins set PRO');
select tests.login(:admin);
select public.admin_set_service_pro((select id from public.service_providers where name = 'Utep Test'), true);
select tests.login(:owner1);
select tests.check(exists (select 1 from jsonb_array_elements(public.nearby_services(40.42, 49.80, 50)) e
                           where e->>'name' = 'Utep Test' and (e->>'is_pro')::boolean),
  'P5 everyone sees the PRO flag');
select tests.check((select is_pro from public.service_providers where name = 'Utep Test'), 'P6 PRO readable through the table (column grant)');
select tests.login(:admin);
select public.admin_set_service_status((select id from public.service_providers where name = 'Utep Test'), 'suspended', 'test');
select tests.login(:owner1);
select tests.check(not exists (select 1 from jsonb_array_elements(public.nearby_services(40.42, 49.80, 50)) e
                               where e->>'name' = 'Utep Test'),
  'P7 admin can still take a profile down afterwards');
select tests.login(:admin);
select tests.check(exists (select 1 from public.admin_audit_log where action = 'service.pro_on'), 'P8 PRO change is in the audit log');
reset role;
select tests.summary('SERVICES AUTO-PUBLISH / PRO (0028)');
rollback;

-- Services / shops published without the admin — 0098. Rolled back.
\set owner2  '''a0000000-0000-4000-8000-000000000012'''
\set owner3  '''a0000000-0000-4000-8000-000000000013'''
\set owner4  '''a0000000-0000-4000-8000-000000000014'''
\set p2      '''5e000000-0000-4000-8000-000000000002'''
\set p3      '''5e000000-0000-4000-8000-000000000003'''
\set p4      '''5e000000-0000-4000-8000-000000000004'''

begin;
set role authenticated;
select tests.login(:owner2);
select tests.check((select status = 'pending' from public.service_providers where id = :p2), 'W0 a profile waiting from before 0028');
update public.service_providers set description = 'Mağaza' where id = :p2;
select tests.check((select status = 'approved' and description = 'Mağaza' and not is_verified from public.service_providers where id = :p2),
  'W1 the owner''s save publishes it — no admin needed');
select tests.check(exists (select 1 from jsonb_array_elements(public.nearby_services(40.41, 49.87, 50)) e where e->>'id' = :p2),
  'W2 it is on the map right away');
select tests.login(:owner3);
update public.service_providers set description = 'x', status = 'approved' where id = :p3;
select tests.check((select status = 'rejected' from public.service_providers where id = :p3), 'W3 a rejected profile stays rejected');
select tests.login(:owner4);
update public.service_providers set description = 'x' where id = :p4;
select tests.check((select status = 'suspended' from public.service_providers where id = :p4), 'W4 a suspended one stays suspended');
select tests.login('a0000000-0000-4000-8000-000000000021');
insert into public.service_providers (name, lat, lng, categories, status) values ('Yeni Mağaza', 40.5, 49.9, '{spare_parts,shop_new}', 'pending');
select tests.check((select status = 'approved' from public.service_providers where name = 'Yeni Mağaza'), 'W5 a new shop is published at once (0028)');
reset role;
select tests.summary('SERVİS / MAĞAZA ADMİNSİZ DƏRC (0098)');
rollback;

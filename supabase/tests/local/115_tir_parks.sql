-- TIRPark — 0077. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set user1  '''a0000000-0000-4000-8000-000000000012'''
\set user2  '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:user1);
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
-- 0100 (owner, 07.11.2026): users no longer add parks; every call is refused.
select tests.check(tests.err($$ select public.tir_park_add('Utep TIR Parkı', 40.4560, 49.7300, 'Xırdalan', array['secure']) $$) like '%not_available%',
  'T1 a user cannot add a park / spot (0100)');
select tests.check(tests.err($$ insert into public.tir_parks (name, lat, lng) values ('Direct', 40.1, 49.1) $$) like '%permission denied%'
                   or tests.err($$ insert into public.tir_parks (name, lat, lng) values ('Direct', 40.1, 49.1) $$) like '%row-level security%',
  'T2 …nor by writing into the table');
-- A spot a user added before 0100 (still waiting): the rules below stay.
reset role;  -- users no longer add parks (0100): the park is made directly
with n as (insert into public.tir_parks (name, lat, lng, city, amenities, created_by, status)
           values ('Utep TIR Parkı', 40.4560, 49.7300, 'Xırdalan', array['secure','24_7','food'], :user1, 'pending') returning id)
insert into ids select 'p1', id from n;
set role authenticated;
-- The author edits name / amenities, never the status.
update public.tir_parks set name = 'Utep TIR Parkı (Xırdalan)', status = 'approved' where id = (select id from ids where k='p1');
select tests.check((select name = 'Utep TIR Parkı (Xırdalan)' and status = 'pending' from public.tir_parks where id = (select id from ids where k='p1')),
  'T5 the author edits his waiting park; the status stays');

select tests.login(:user2);
select tests.check((select count(*) = 0 from public.tir_parks where id = (select id from ids where k='p1')), 'T6 others do not see a waiting park');
select tests.check(tests.err($$ select public.admin_tir_park_set_status((select id from ids where k='p1'), 'approved') $$) like '%admin_only%',
  'T8 a user cannot approve');

select tests.login(:admin);
select public.admin_tir_park_set_status((select id from ids where k='p1'), 'approved');
select tests.login(:user2);
select tests.check((select status = 'approved' from public.tir_parks where id = (select id from ids where k='p1')), 'A1 after approval everybody sees it');
update public.tir_parks set name = 'Hack' where id = (select id from ids where k='p1');
select tests.check((select name <> 'Hack' from public.tir_parks where id = (select id from ids where k='p1')), 'A2 others cannot edit it');
select tests.login(:user1);
update public.tir_parks set name = 'Changed after approval' where id = (select id from ids where k='p1');
select tests.check((select name <> 'Changed after approval' from public.tir_parks where id = (select id from ids where k='p1')),
  'A3 after approval the author no longer edits it (admin only)');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'tir_park.approved'), 'A4 approval is logged');

set role authenticated;
select tests.login(:admin);
select public.admin_tir_park_set_status((select id from ids where k='p1'), 'hidden');
select tests.login(:user2);
select tests.check((select count(*) = 0 from public.tir_parks where id = (select id from ids where k='p1')), 'A5 a hidden park is gone for users');
reset role;
select tests.check((select count(*) = 1 from public.tir_parks where id = (select id from ids where k='p1')), 'A6 …and kept (nothing deleted)');
set role anon;
select tests.login(null);
select tests.check(tests.err($$ select * from public.tir_parks $$) is null
                   and not exists (select 1 from public.tir_parks where status <> 'approved'), 'S1 a visitor sees approved parks only (0107)');
reset role;
select tests.summary('TIRPARK (0077)');
rollback;

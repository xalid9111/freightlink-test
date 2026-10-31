-- TIRPark — 0077. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set user1  '''a0000000-0000-4000-8000-000000000012'''
\set user2  '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:user1);
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
insert into ids values ('p1', public.tir_park_add('Utep TIR Parkı', 40.4560, 49.7300, 'Xırdalan', array['secure','24_7','food']));
select tests.check((select status = 'pending' from public.tir_parks where id = (select id from ids where k='p1')), 'T1 a new park waits for approval');
select tests.check(tests.err($$ select public.tir_park_add('Eyni park', 40.4561, 49.7301) $$) like '%duplicate_nearby%',
  'T2 the same place (≈14 m) is refused as a duplicate');
select tests.check(tests.err($$ select public.tir_park_add('X', 40.5, 49.8, null, array['pool']) $$) like '%tir_park_amenities_valid%'
                   or tests.err($$ select public.tir_park_add('X', 40.5, 49.8, null, array['pool']) $$) like '%check%',
  'T3 unknown amenities are refused');
select tests.check(tests.err($$ select public.tir_park_add('X', 140, 49.8) $$) like '%invalid_argument%', 'T4 a wrong place is refused');
-- The author edits name / amenities, never the status.
update public.tir_parks set name = 'Utep TIR Parkı (Xırdalan)', status = 'approved' where id = (select id from ids where k='p1');
select tests.check((select name = 'Utep TIR Parkı (Xırdalan)' and status = 'pending' from public.tir_parks where id = (select id from ids where k='p1')),
  'T5 the author edits his pending park; the status stays pending');

select tests.login(:user2);
select tests.check((select count(*) = 0 from public.tir_parks where id = (select id from ids where k='p1')), 'T6 others do not see a pending park');
select tests.check((select jsonb_array_length(public.tir_parks_near(40.4565, 49.7305, 500)) = 1
                      and public.tir_parks_near(40.4565, 49.7305, 500) -> 0 ->> 'status' = 'pending'),
  'T7 …but "nearby" warns about it before adding the same park');
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
select tests.check(tests.err($$ select * from public.tir_parks $$) like '%permission denied%', 'S1 not for signed-out visitors');
reset role;
select tests.summary('TIRPARK (0077)');
rollback;

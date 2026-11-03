-- TIR park: a new price applies to the trucks in the park — 0090. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Qiymət Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.6700, 46.4200, null, 10, 3, '+994501112233'));
insert into ids select 'old', (public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-001') ->> 'id')::uuid;
insert into ids select 'new', (public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-002') ->> 'id')::uuid;
insert into ids select 'gone', (public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-003') ->> 'id')::uuid;
reset role;
-- 5 hours in the park; one came 1 hour ago.
update public.tir_park_stays set entered_at = now() - interval '5 hours' where id in ((select id from ids where k='old'), (select id from ids where k='gone'));
update public.tir_park_stays set entered_at = now() - interval '1 hour' where id = (select id from ids where k='new');
set role authenticated;
select tests.login(:owner);
select public.tir_park_stay_exit((select id from ids where k='gone'));
reset role;
select tests.check((select amount = 0.63 from public.tir_park_stays where id = (select id from ids where k='gone')), 'R1 left at 3 AZN/day: 5 h = 0.63');

-- The owner changes the price to 6 AZN / day (Ayarlar).
set role authenticated;
select tests.login(:owner);
select public.tir_park_manager_update((select id from ids where k='p'), 10, 10, 6, 'day', '24/7', '+994501112233', false);
reset role;
select tests.check((select rate = 6 from public.tir_park_stays where id = (select id from ids where k='old')), 'R2 an old entry now counts at the new price');
select tests.check((select rate = 6 from public.tir_park_stays where id = (select id from ids where k='new')), 'R3 a new entry too');
select tests.check((select rate = 3 and amount = 0.63 from public.tir_park_stays where id = (select id from ids where k='gone')),
  'R4 a truck that already left keeps what was taken');
set role authenticated;
select tests.login(:owner);
select tests.check((select (e ->> 'amount_now')::numeric = 1.25 from jsonb_array_elements(public.tir_park_parked((select id from ids where k='p')) -> 'in') e
                     where e ->> 'plate' = '10-AA-001'), 'R5 the list shows 5 h at 6 AZN/day = 1.25');
select tests.check((public.tir_park_stay_exit((select id from ids where k='old')) ->> 'amount')::numeric = 1.25, 'R6 the exit takes the new price');
-- A change of something else (phone) leaves the rate alone.
select public.tir_park_manager_update((select id from ids where k='p'), 10, 10, 6, 'day', '24/7', '+994501112244', false);
reset role;
select tests.check((select rate = 6 from public.tir_park_stays where id = (select id from ids where k='new')), 'R7 other settings change nothing');
select tests.summary('TIRPARK YENİ QİYMƏT (0090)');

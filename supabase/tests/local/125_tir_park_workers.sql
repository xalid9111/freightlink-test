-- TIR park owner panel, stage 2: workers — 0087. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set worker  '''a0000000-0000-4000-8000-000000000021'''
\set other   '''a0000000-0000-4000-8000-000000000011'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table codes (k text primary key, code text) on commit drop;
grant all on ids, codes to authenticated;

-- A park with its owner (0086).
set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('İşçi Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.6200, 46.3600, null, 10, 3, '+994501112233'));

-- ---- invitations ---------------------------------------------------------------------
select tests.login(:worker);
select tests.check(tests.err(format($$ select public.tir_park_invite_create(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'W1 only the owner invites');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-AA-100') $$, (select id from ids where k='p'))) like '%not_allowed%',
  'W2 not a worker yet: cannot add trucks');
select tests.login(:owner);
insert into codes select 'c', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
select tests.check((select code ~ '^[A-Z2-9]{8}$' from codes where k='c'), 'W3 an 8-character one-time code');
select tests.check(jsonb_array_length(public.tir_park_workers_list((select id from ids where k='p')) -> 'invites') = 1, 'W4 the owner sees it');
reset role;
select tests.check(not exists (select 1 from public.tir_park_workers), 'W5 nobody is bound automatically');
set role authenticated;
select tests.login(:worker);
select tests.check(public.tir_park_invite_preview('XXXXXXXX') ->> 'error' = 'invalid_code', 'W6 a wrong code says so');
select tests.check(public.tir_park_invite_preview((select code from codes where k='c')) ->> 'park_name' = 'İşçi Park',
  'W7 the worker sees the park''s name before accepting');
reset role;
select tests.check(not exists (select 1 from public.tir_park_workers), 'W8 seeing it binds nothing');
set role authenticated;
select tests.check(tests.err($$ select * from public.tir_park_workers $$) like '%permission denied%', 'W8b the tables are not read directly');
select tests.check(public.tir_park_invite_accept(lower((select code from codes where k='c')), 'Elvin Məmmədov') ->> 'park_name' = 'İşçi Park',
  'W9 he accepts with his own account (0088: name and surname, then the owner approves)');
select tests.login(:owner);
select public.tir_park_worker_approve((select id from ids where k='p'), :worker);
select tests.login(:worker);
select tests.check(jsonb_array_length(public.tir_park_my_work()) = 1, 'W10 …and works at that park');
select tests.login(:other);
select tests.check(public.tir_park_invite_accept((select code from codes where k='c'), 'Başqa Adam') ->> 'error' = 'invalid_code', 'W11 a code works once');
select tests.check(jsonb_array_length(public.tir_park_my_work()) = 0, 'W12 nobody else is bound');

-- ---- the worker works: trucks by plate, places but no takings ------------------------
select tests.login(:worker);
insert into ids select 's', (public.tir_park_stay_enter((select id from ids where k='p'), '10 aa 100') ->> 'id')::uuid;
select tests.check(jsonb_array_length(public.tir_park_parked((select id from ids where k='p')) -> 'in') = 1,
  'W13 the worker adds a truck (sees it in his list; 0091: not by reading the table)');
select tests.check((public.tir_park_owner_summary((select id from ids where k='p')) ->> 'in_park')::int = 1
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'today_paid') is null
               and (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'accruing') is null,
  'W14 the worker sees the places, not the takings');
select tests.check(tests.err(format($$ select public.tir_park_owner_report(%L, 7) $$, (select id from ids where k='p'))) like '%not_allowed%'
               and tests.err(format($$ select public.tir_park_owner_feed(%L, 10) $$, (select id from ids where k='p'))) like '%not_allowed%'
               and tests.err(format($$ select public.tir_park_workers_list(%L) $$, (select id from ids where k='p'))) like '%not_allowed%'
               and tests.err(format($$ select public.tir_park_manager_update(%L, 10, 10, 3, 'day', null, '+994501112233', true) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'W15 report, gedişat, workers and settings stay the owner''s');
reset role;
update public.tir_park_stays set entered_at = now() - interval '5 hours' where id = (select id from ids where k='s');
set role authenticated;
select tests.login(:worker);
select tests.check((public.tir_park_stay_exit((select id from ids where k='s')) ->> 'amount')::numeric = 0.63, 'W16 the worker records the exit (5 h = 0.63)');

-- ---- the owner sees everything -----------------------------------------------------------
select tests.login(:owner);
select tests.check((select count(*) = 2 from jsonb_array_elements(public.tir_park_worker_activity((select id from ids where k='p'), 30)) e
                     where e ->> 'by' = 'Unrelated user' and e ->> 'plate' = '10-AA-100'),
  'W17 İşçi fəaliyyəti: who added and who let out which truck');
-- The entry was moved 5 h back: between 00:00 and 05:00 Baku it falls on
-- yesterday, so the entry is counted on its own day (any day of the report).
select tests.check((select (e ->> 'cars_paid')::numeric = 0.63 and (e ->> 'exits')::int = 1
                      from jsonb_array_elements(public.tir_park_owner_report((select id from ids where k='p'), 7)) e
                     where (e ->> 'day')::date = (now() at time zone 'Asia/Baku')::date)
                   and (select sum((e ->> 'entries')::int) = 1
                          from jsonb_array_elements(public.tir_park_owner_report((select id from ids where k='p'), 7)) e),
  'W18 Hesabat: 1 in (on its own day), today 1 out, 0.63 taken');
select tests.check((public.tir_park_workers_list((select id from ids where k='p')) -> 'workers' -> 0 ->> 'today_out')::int = 1,
  'W19 the owner sees each worker and what he did today');
select public.tir_park_worker_remove((select id from ids where k='p'), :worker);
select tests.login(:worker);
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '20-BB-200') $$, (select id from ids where k='p'))) like '%not_allowed%'
               and jsonb_array_length(public.tir_park_my_work()) = 0,
  'W20 a worker taken off cannot work any more');
reset role;
select tests.check((select count(*) = 1 from public.tir_park_stays where entered_by = :worker), 'W21 …his records stay');
-- A cancelled invitation does not work.
set role authenticated;
select tests.login(:owner);
insert into codes select 'c2', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
select public.tir_park_invite_cancel((select (e ->> 'id')::uuid from jsonb_array_elements(public.tir_park_workers_list((select id from ids where k='p')) -> 'invites') e limit 1));
select tests.login(:other);
select tests.check(public.tir_park_invite_accept((select code from codes where k='c2'), 'Başqa Adam') ->> 'error' = 'invalid_code', 'W22 a cancelled invitation does not work');
reset role;
select tests.summary('TIRPARK İŞÇİLƏR (0087)');

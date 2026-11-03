-- TIR park: one worker as the park's admin — 0089. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set boss    '''a0000000-0000-4000-8000-000000000021'''
\set w2      '''a0000000-0000-4000-8000-000000000011'''
\set w3      '''a0000000-0000-4000-8000-000000000014'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table codes (k text primary key, code text) on commit drop;
grant all on ids, codes to authenticated;

set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Admin Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.6600, 46.4100, null, 10, 3, '+994501112233'));
insert into codes select 'c1', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
insert into codes select 'c2', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
select tests.login(:boss);
select public.tir_park_invite_accept((select code from codes where k='c1'), 'Anar Quliyev');
select tests.login(:w2);
select public.tir_park_invite_accept((select code from codes where k='c2'), 'Vüsal Həsənov');
select tests.login(:owner);
select public.tir_park_worker_approve((select id from ids where k='p'), :boss);
select public.tir_park_worker_approve((select id from ids where k='p'), :w2);

-- An ordinary worker cannot manage workers.
select tests.login(:boss);
select tests.check(tests.err(format($$ select public.tir_park_invite_create(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'A1 an ordinary worker makes no invitations');
select tests.check(tests.err(format($$ select public.tir_park_worker_set_admin(%L, %L, true) $$, (select id from ids where k='p'), 'a0000000-0000-4000-8000-000000000021'))
  like '%not_allowed%', 'A2 a worker cannot make himself admin');

-- The owner names the admin.
select tests.login(:owner);
select public.tir_park_worker_set_admin((select id from ids where k='p'), :boss, true);
select tests.check((select (w ->> 'is_admin')::boolean from jsonb_array_elements(public.tir_park_workers_list((select id from ids where k='p')) -> 'workers') w
                     where w ->> 'user_id' = 'a0000000-0000-4000-8000-000000000021'), 'A3 İşçilər shows who is the admin');
select tests.login(:boss);
select tests.check((select (e ->> 'is_admin')::boolean from jsonb_array_elements(public.tir_park_my_work()) e limit 1), 'A4 the admin knows he is the admin');
insert into codes select 'c3', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
select tests.check((select code from codes where k='c3') is not null, 'A5 the admin makes an invitation');

-- A new worker asks: the admin is told and approves.
select tests.login(:w3);
select public.tir_park_invite_accept((select code from codes where k='c3'), 'Orxan Rzayev');
reset role;
select tests.check((select count(*) = 1 from public.notifications where user_id = :boss and type = 'tirpark_worker_request'
                     and title = 'İşçi təsdiq gözləyir: Orxan Rzayev'), 'A6 the admin gets the notice too');
select tests.check((select count(*) = 1 from public.notifications where user_id = :owner and title = 'İşçi təsdiq gözləyir: Orxan Rzayev'),
  'A7 the owner still gets it');
set role authenticated;
select tests.login(:boss);
select tests.check((select (e ->> 'pending')::int = 1 from jsonb_array_elements(public.tir_park_my_work()) e limit 1), 'A8 the admin sees 1 waiting');
select public.tir_park_worker_approve((select id from ids where k='p'), :w3);
select tests.login(:w3);
select tests.check((public.tir_park_stay_enter((select id from ids where k='p'), '30-CC-300') ->> 'plate') = '30-CC-300',
  'A9 approved by the admin: the worker works');

-- The admin takes an ordinary worker off, but not himself.
select tests.login(:boss);
select public.tir_park_worker_remove((select id from ids where k='p'), :w2);
select tests.check(not exists (select 1 from jsonb_array_elements(public.tir_park_workers_list((select id from ids where k='p')) -> 'workers') w
                                where w ->> 'user_id' = 'a0000000-0000-4000-8000-000000000011' and (w ->> 'active')::boolean),
  'A10 the admin takes an ordinary worker off');
select tests.check(tests.err(format($$ select public.tir_park_worker_remove(%L, %L) $$, (select id from ids where k='p'), 'a0000000-0000-4000-8000-000000000021'))
  like '%not_allowed%', 'A11 the admin cannot take himself off');
select tests.check(tests.err(format($$ select public.tir_park_worker_set_admin(%L, %L, true) $$, (select id from ids where k='p'), 'a0000000-0000-4000-8000-000000000014'))
  like '%not_allowed%', 'A12 the admin cannot hand the role on');
select tests.check(tests.err(format($$ select public.tir_park_owner_report(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'A13 the admin sees no report (money stays the owner''s)');
select tests.check(public.tir_park_owner_summary((select id from ids where k='p')) ->> 'today_paid' is null, 'A14 …nor the takings');

-- Only one admin: naming another takes it from the first.
select tests.login(:owner);
select public.tir_park_worker_set_admin((select id from ids where k='p'), :w3, true);
reset role;
select tests.check((select count(*) = 1 from public.tir_park_workers where park_id = (select id from ids where k='p') and is_admin)
               and (select is_admin from public.tir_park_workers where park_id = (select id from ids where k='p') and user_id = :w3),
  'A15 one admin per park');
set role authenticated;
select tests.login(:boss);
select tests.check(tests.err(format($$ select public.tir_park_invite_create(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'A16 the former admin is an ordinary worker again');
select tests.login(:owner);
select public.tir_park_worker_remove((select id from ids where k='p'), :w3);
reset role;
select tests.check(not (select is_admin from public.tir_park_workers where park_id = (select id from ids where k='p') and user_id = :w3),
  'A17 the owner can take the admin off; the role goes with him');
select tests.summary('TIRPARK İŞÇİ ADMİN (0089)');

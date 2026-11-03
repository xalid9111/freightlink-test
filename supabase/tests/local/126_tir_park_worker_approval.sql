-- TIR park workers: the owner approves — 0088. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set worker  '''a0000000-0000-4000-8000-000000000021'''
\set other   '''a0000000-0000-4000-8000-000000000011'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table codes (k text primary key, code text) on commit drop;
grant all on ids, codes to authenticated;

set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Təsdiq Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.6500, 46.4000, null, 10, 3, '+994501112233'));
insert into codes select 'c', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
insert into codes select 'c2', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';

select tests.login(:worker);
select tests.check(public.tir_park_invite_accept((select code from codes where k='c')) ->> 'error' = 'name_required',
  'P1 an old app (no name) binds nobody');
select tests.check(public.tir_park_invite_accept((select code from codes where k='c'), 'Elvin') ->> 'error' = 'name_required',
  'P2 name AND surname are needed');
select tests.check(public.tir_park_invite_accept((select code from codes where k='c'), '  Elvin   Məmmədov ') ->> 'status' = 'pending',
  'P3 with name and surname: sent, waiting for the owner');
select tests.check((select e ->> 'status' = 'pending' from jsonb_array_elements(public.tir_park_my_work()) e limit 1),
  'P4 the worker sees "waiting"');
select tests.check(tests.err(format($$ select public.tir_park_stay_enter(%L, '10-AA-100') $$, (select id from ids where k='p'))) like '%not_allowed%',
  'P5 waiting: he cannot add trucks yet');

select tests.login(:owner);
select tests.check(public.tir_park_owner_pending_workers() = 1, 'P6 the owner''s Profil count shows 1 waiting');
select tests.check((select count(*) = 1 from public.notifications where type = 'tirpark_worker_request'
                     and title = 'İşçi təsdiq gözləyir: Elvin Məmmədov'), 'P7 the owner gets a notice');
select tests.check((select count(*) = 1 from public.messages where sender_id = :worker and receiver_id = :owner
                     and message like 'Park işçisi kimi qoşulmaq istəyirəm.%' and message like '%Ad, soyad: Elvin Məmmədov%'),
  'P8 …and a message in Mesajlar');
select tests.check((select w ->> 'name' = 'Elvin Məmmədov' and w ->> 'status' = 'pending'
                      from jsonb_array_elements(public.tir_park_workers_list((select id from ids where k='p')) -> 'workers') w),
  'P9 İşçilər shows the name he wrote, waiting');
select tests.login(:worker);
select tests.check(tests.err(format($$ select public.tir_park_worker_approve(%L, %L) $$, (select id from ids where k='p'), 'a0000000-0000-4000-8000-000000000021'))
  like '%not_allowed%', 'P10 the worker cannot approve himself');
select tests.login(:owner);
select public.tir_park_worker_approve((select id from ids where k='p'), :worker);
select tests.check(public.tir_park_owner_pending_workers() = 0, 'P11 approved: nothing waits');
select tests.login(:worker);
select tests.check((public.tir_park_stay_enter((select id from ids where k='p'), '10-AA-100') ->> 'plate') = '10-AA-100',
  'P12 approved: he adds trucks');
select tests.check(public.tir_park_invite_accept((select code from codes where k='c2'), 'Elvin Məmmədov') ->> 'error' = 'already_worker',
  'P13 an approved worker is not asked again');

-- Another person: the owner says no.
select tests.login(:other);
select public.tir_park_invite_accept((select code from codes where k='c2'), 'Rəşad Əliyev');
select tests.login(:owner);
select public.tir_park_worker_reject((select id from ids where k='p'), :other);
select tests.login(:other);
select tests.check((select e ->> 'status' = 'rejected' from jsonb_array_elements(public.tir_park_my_work()) e limit 1)
               and tests.err(format($$ select public.tir_park_stay_enter(%L, '20-BB-200') $$, (select id from ids where k='p'))) like '%not_allowed%',
  'P14 rejected: told so, cannot work');
reset role;
select tests.summary('TIRPARK İŞÇİ TƏSDİQİ (0088)');

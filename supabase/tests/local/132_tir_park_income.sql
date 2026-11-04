-- TIR park: income by day / month / year — 0094. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set boss    '''a0000000-0000-4000-8000-000000000021'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table codes (k text primary key, code text) on commit drop;
grant all on ids, codes to authenticated;
create or replace function pg_temp.inc(p_part text, p_key text) returns numeric language sql as $$
  select (public.tir_park_owner_income((select id from ids where k='p')) -> p_part ->> p_key)::numeric;
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- A park (3 AZN / day) and a worker the owner made the park's admin.
set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Income Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.7700, 46.5100, null, 10, 3, '+994501112233'));
insert into codes select 'c1', public.tir_park_invite_create((select id from ids where k='p')) ->> 'code';
select tests.login(:boss);
select public.tir_park_invite_accept((select code from codes where k='c1'), 'Anar Quliyev');
select tests.login(:owner);
select public.tir_park_worker_approve((select id from ids where k='p'), :boss);
select public.tir_park_worker_set_admin((select id from ids where k='p'), :boss, true);

select tests.check(pg_temp.inc('day', 'cars') = 0 and pg_temp.inc('year', 'bookings') = 0, 'I1 a new park: nothing taken yet');
reset role;

-- Exits: today, at this month's start, at this year's start, last year.
insert into public.tir_park_stays (park_id, plate, entered_at, exited_at, rate, amount)
select (select id from ids where k='p'), x.plate, x.at - interval '1 hour', x.at, 3, x.amount
  from (values
    ('10-AA-001', now() - interval '1 minute', 7.40),
    ('10-AA-002', date_trunc('month', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku', 10),
    ('10-AA-003', date_trunc('year', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku', 100),
    ('10-AA-004', date_trunc('year', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku' - interval '1 second', 1000)
  ) x(plate, at, amount);
-- A truck still in the park: nothing taken yet.
insert into public.tir_park_stays (park_id, plate, entered_at, rate) values ((select id from ids where k='p'), '10-AA-005', now() - interval '3 hours', 3);

-- What each part should hold (today may be the 1st of the month / of January).
create temp table want as
select sum(amount) filter (where exited_at >= public._tir_park_today_start()) as d,
       sum(amount) filter (where exited_at >= date_trunc('month', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku') as m,
       sum(amount) filter (where exited_at >= date_trunc('year', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku') as y
  from public.tir_park_stays where park_id = (select id from ids where k='p') and exited_at is not null;
grant select on want to authenticated;

set role authenticated;
select tests.login(:owner);
select tests.check(pg_temp.inc('day', 'cars') = (select d from want) and pg_temp.inc('day', 'cars') >= 7.40,
  'I2 Günlük = the money taken at today''s exits');
select tests.check(pg_temp.inc('day', 'cars') = (public.tir_park_owner_summary((select id from ids where k='p')) ->> 'today_paid')::numeric,
  'I3 Günlük is the same sum as "Bu gün"');
select tests.check(pg_temp.inc('month', 'cars') = (select m from want) and pg_temp.inc('month', 'cars') >= 17.40,
  'I4 Aylıq = from the 1st of this month (Baku)');
select tests.check(pg_temp.inc('year', 'cars') = (select y from want) and pg_temp.inc('year', 'cars') = 117.40,
  'I5 İllik = from 1 January (Baku); last year not counted');
select tests.check(pg_temp.inc('year', 'exits') = 3, 'I6 a truck still in the park is not counted');
select tests.check((public.tir_park_owner_income((select id from ids where k='p')) ->> 'currency') = 'AZN', 'I7 the park''s currency');

-- Only the owner (and app admins) see money.
select tests.login(:boss);
select tests.check(tests.err(format($$ select public.tir_park_owner_income(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'I8 the park''s worker-admin never sees money');
select tests.login('a0000000-0000-4000-8000-000000000011');
select tests.check(tests.err(format($$ select public.tir_park_owner_income(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'I9 another user: not allowed');
select tests.login(:admin);
select tests.check(pg_temp.inc('year', 'cars') = 117.40, 'I10 an app admin sees it');
select tests.login(null);
select tests.check(tests.err(format($$ select public.tir_park_owner_income(%L) $$, (select id from ids where k='p'))) like '%not_allowed%',
  'I11 signed out: not allowed');
reset role;

select tests.summary('TIRPARK GƏLİR: GÜNLÜK · AYLIQ · İLLİK (0094)');
rollback;

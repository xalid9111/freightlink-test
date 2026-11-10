-- UTEP REKLAM — 0112: the day closes by itself after 23:59 (Baku); the worker
-- re-opens only today's day he closed himself. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000011'''
\set worker '''a0000000-0000-4000-8000-000000000012'''
\set chief  '''a0000000-0000-4000-8000-0000000000f1'''
\set utep   '''ad0b1200-0000-4000-8000-000000000001'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder","role":"cargo_owner"}')
  on conflict (id) do nothing;
update public.users set role = 'admin' where id = :chief;
select public.founder_sync();
create temp table t (k text primary key, id uuid) on commit drop;
grant all on t to authenticated;

set role authenticated;
select tests.login(:chief);
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 235);
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');

-- A forgotten open day of yesterday (as if the worker never closed it).
reset role;
insert into public.adbiz_days (id, company_id, user_id, work_date, target)
values ('dd000000-0000-4000-8000-000000000001', :utep, :worker, public._adbiz_today() - 1, 235);
insert into public.adbiz_entries (day_id, company_id, user_id, title, amount)
values ('dd000000-0000-4000-8000-000000000001', :utep, :worker, 'Nömrə', 20);
set role authenticated;

select tests.login(:worker);
select tests.check(tests.err($$ select public.adbiz_add_entry('dd000000-0000-4000-8000-000000000001', 'late', 5) $$) like '%day_closed%',
  'A1 after 23:59 yesterday takes no more jobs (even before it is swept)');
select tests.check(tests.err($$ select public.adbiz_add_day_expense('dd000000-0000-4000-8000-000000000001', 'late', 5) $$) like '%day_closed%',
  'A2 …nor rasxod');
insert into t values ('d', public.adbiz_open_day());
select tests.check((select status = 'closed' and closed_by is null
                      and closed_at = ((work_date + 1)::timestamp at time zone 'Asia/Baku') - interval '1 second'
                    from public.adbiz_days where id = 'dd000000-0000-4000-8000-000000000001'),
  'A3 opening today closed yesterday at 23:59:59 (automatic)');
select tests.check((select work_date = public._adbiz_today() and status = 'open' from public.adbiz_days where id = (select id from t where k = 'd')),
  'A4 today is a new open day');
select tests.check(tests.err($$ select public.adbiz_reopen_day('dd000000-0000-4000-8000-000000000001') $$) like '%not_allowed%',
  'A5 the worker cannot re-open an earlier (auto-closed) day');

-- Closed by mistake today: the worker opens it again and goes on.
select public.adbiz_add_entry((select id from t where k = 'd'), 'Kalçuk', 25);
select public.adbiz_close_day((select id from t where k = 'd'));
select public.adbiz_reopen_day((select id from t where k = 'd'));
select tests.check((select status = 'open' and closed_by is null from public.adbiz_days where id = (select id from t where k = 'd')),
  'B1 today''s day closed by mistake: re-opened by the worker');
select tests.check(public.adbiz_add_entry((select id from t where k = 'd'), 'Banner', 35) is not null, 'B2 …and he adds jobs again');
reset role;
select tests.check(exists (select 1 from public.adbiz_audit where action = 'day.reopen' and actor_id = :worker and new_value ->> 'by' = 'worker'),
  'B3 the re-open is in the history');
set role authenticated;

-- Closed by the owner: not the worker's to re-open.
select tests.login(:owner);
select public.adbiz_close_day((select id from t where k = 'd'));
select tests.login(:worker);
select tests.check(tests.err(format($$ select public.adbiz_reopen_day(%L) $$, (select id from t where k = 'd'))) like '%not_allowed%',
  'C1 a day the owner closed stays closed for the worker');
select tests.login(:owner);
select public.adbiz_reopen_day((select id from t where k = 'd'));
select tests.check((select status = 'open' from public.adbiz_days where id = (select id from t where k = 'd')), 'C2 the owner re-opens it');

-- The sweep (the app calls it when the notebook / business page opens).
reset role;
insert into public.adbiz_days (id, company_id, user_id, work_date, target)
values ('dd000000-0000-4000-8000-000000000002', :utep, :owner, public._adbiz_today() - 3, 235);
set role authenticated;
select tests.login(:owner);
select tests.check(public.adbiz_sweep() = 1, 'D1 the sweep closes the forgotten day of the company');
select tests.check((select status = 'closed' from public.adbiz_days where id = 'dd000000-0000-4000-8000-000000000002'), 'D2 …closed');
select tests.check((select status = 'open' from public.adbiz_days where id = (select id from t where k = 'd')), 'D3 today stays open');
select tests.check(exists (select 1 from public.adbiz_audit where action = 'day.auto_close' and actor_id is null), 'D4 automatic closes are in the history');
select tests.login(null);
select tests.check(tests.err($$ select public.adbiz_sweep() $$) is not null, 'D5 visitors cannot sweep');
select tests.summary('UTEP REKLAM AVTOMATİK BAĞLANMA (0112)');
rollback;

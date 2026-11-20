-- UTEP REKLAM — 0133: the monthly target (6110 from November 2026), the
-- month's "Ümumi mənfi" = net − target × workers; earlier months keep the
-- old figures; only the Baş admin sets it; the worker's own month. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000011'''
\set worker '''a0000000-0000-4000-8000-000000000012'''
\set bwork  '''a0000000-0000-4000-8000-000000000014'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
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
select tests.check((select amount = 6110 from public.adbiz_month_targets where company_id = :utep and from_month = '2026-11-01'),
  'M1 UTEP Reklam starts with 6110 AZN from November 2026');

set role authenticated;
select tests.login(:chief);
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 235);
insert into t values ('b', public.adbiz_admin_company_save(null, 'Reklam B', 300));
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');
select public.adbiz_admin_member_set(:bwork, (select id from t where k = 'b'), 'worker');

-- A November day: 270 jobs, 20 rasxod.
reset role;
insert into public.adbiz_days (id, company_id, user_id, work_date, target, status, closed_at)
values ('dd330000-0000-4000-8000-000000000001', :utep, :worker, '2026-11-12', 235, 'closed', now());
insert into public.adbiz_entries (day_id, company_id, user_id, title, amount)
values ('dd330000-0000-4000-8000-000000000001', :utep, :worker, 'Vitrin', 270);
insert into public.adbiz_expenses (company_id, day_id, user_id, spent_on, title, amount, created_by)
values (:utep, 'dd330000-0000-4000-8000-000000000001', :worker, '2026-11-12', 'Boya', 20, :worker);
set role authenticated;

select tests.login(:owner);
create temp table r on commit drop as select public.adbiz_report_periods(:utep, 2026) j;
select tests.check((select (m ->> 'net')::numeric = 1556 and (m ->> 'gap')::numeric = 1556 - 6110 and (m ->> 'target')::numeric = 6110
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 11),
  'M2 November = the old 1306 + the program''s 250, minus 6110 (the old −4693 no longer used)');
select tests.check((select (m ->> 'net')::numeric = 5038 and (m ->> 'gap')::numeric = -961 and m ->> 'target' is null
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 10),
  'M3 October keeps its old figures (5999)');
select tests.check((select (y ->> 'gap')::numeric = (select sum((m ->> 'gap')::numeric) from r, jsonb_array_elements(j -> 'months') m)
                    from r, jsonb_array_elements(j -> 'years') y where (y ->> 'key')::int = 2026),
  'M4 the year = the sum of its months');

-- The worker's own month on his notebook.
select tests.login(:worker);
select tests.check((select (j ->> 'target')::numeric = 6110 and (j ->> 'collected')::numeric = 1556 and (j ->> 'gap')::numeric = -4554
                    and (j ->> 'days')::int = 1 from public.adbiz_my_month(:worker, '2026-11-21') j),
  'M5 the worker: 6110 target, collected (the only worker: + the old account), Ümumi mənfi');
select tests.check(tests.err(format($$ select public.adbiz_my_month(%L, '2026-11-21') $$, :owner)) like '%not_allowed%',
  'M6 the worker reads only his own month');
select tests.check((select j ->> 'target' is null from public.adbiz_my_month(:worker, '2026-10-05') j), 'M7 before the target: none');
select tests.check(tests.err(format($$ select public.adbiz_month_target_set(%L, '2026-12-01', 9999) $$, :utep)) like '%chief_admin_only%',
  'M8 the worker never sets the target');
select tests.login(:owner);
select tests.check((select (j ->> 'gap')::numeric = -4554 from public.adbiz_my_month(:worker, '2026-11-21') j), 'M9 the owner reads his worker''s month');
select tests.check(tests.err(format($$ select public.adbiz_month_target_set(%L, '2026-12-01', 9999) $$, :utep)) like '%chief_admin_only%',
  'M10 …but sets no target (the Baş admin only)');
select tests.login(:bwork);
select tests.check(tests.err(format($$ select public.adbiz_my_month(%L, '2026-11-21') $$, :worker)) like '%not_allowed%', 'M11 not another company');

-- The Baş admin: a new target from December on; November keeps 6110.
select tests.login(:chief);
select public.adbiz_month_target_set(:utep, '2026-12-15', 7000);
select tests.check((select from_month = '2026-12-01' and amount = 7000 from public.adbiz_month_targets where company_id = :utep and from_month > '2026-11-01'),
  'M12 counted from the month''s first day');
select tests.check((select (m ->> 'target')::numeric = 6110 from public.adbiz_report_periods(:utep, 2026) j, jsonb_array_elements(j -> 'months') m
                    where (m ->> 'key')::int = 11)
               and (select (m ->> 'target')::numeric = 7000 from public.adbiz_report_periods(:utep, 2026) j, jsonb_array_elements(j -> 'months') m
                    where (m ->> 'key')::int = 12), 'M13 November stays 6110, December 7000');
reset role;
select tests.check(exists (select 1 from public.adbiz_audit where action = 'month_target' and actor_id = :chief), 'M14 in the history');

-- A second worker in November: the company's month counts both targets.
insert into public.adbiz_days (id, company_id, user_id, work_date, target, status, closed_at)
values ('dd330000-0000-4000-8000-000000000002', :utep, :owner, '2026-11-13', 235, 'closed', now());
set role authenticated;
select tests.login(:owner);
select tests.check((select (m ->> 'gap')::numeric = 1556 - 2 * 6110 from public.adbiz_report_periods(:utep, 2026) j, jsonb_array_elements(j -> 'months') m
                    where (m ->> 'key')::int = 11), 'M15 two workers = 2 × 6110');
select tests.check((select (j ->> 'collected')::numeric = 250 from public.adbiz_my_month(:worker, '2026-11-21') j),
  'M16 not the only worker: the old account is not his');
select tests.check(tests.err($$ insert into public.adbiz_month_targets (company_id, from_month, amount) values ('ad0b1200-0000-4000-8000-000000000001', '2030-01-01', 1) $$)
                   like '%permission denied%', 'M17 no direct writes');

select tests.summary('UTEP REKLAM AYLIQ HƏDƏF (0133)');
rollback;

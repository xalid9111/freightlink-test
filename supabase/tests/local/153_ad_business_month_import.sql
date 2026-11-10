-- UTEP REKLAM — 0116: the old account carried over; the cards = old figures +
-- the program's days; only the owner / Baş admin changes them. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000011'''
\set worker '''a0000000-0000-4000-8000-000000000012'''
\set bwork  '''a0000000-0000-4000-8000-000000000014'''
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
select tests.check((select count(*) = 11 and sum(net) = 61792 and sum(gap) = -4197 from public.adbiz_month_import
                    where company_id = :utep and year = 2026),
  'A1 the owner''s 2026 table is carried over (January – November)');
select tests.check((select net = 5784 and gap = -215 from public.adbiz_month_import where company_id = :utep and year = 2026 and month = 1)
               and (select net = 1306 and gap = -4693 from public.adbiz_month_import where company_id = :utep and year = 2026 and month = 11)
               and not exists (select 1 from public.adbiz_month_import where company_id = :utep and year = 2026 and month = 12),
  'A2 January 5784 / −215, November 1306 / −4693, no December');

set role authenticated;
select tests.login(:chief);
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 235);
insert into t values ('b', public.adbiz_admin_company_save(null, 'Reklam B', 300));
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');
select public.adbiz_admin_member_set(:bwork, (select id from t where k = 'b'), 'worker');

-- A November day in the program: 270 jobs, target 235 → +35.
reset role;
insert into public.adbiz_days (id, company_id, user_id, work_date, target, status, closed_at)
values ('dd160000-0000-4000-8000-000000000001', :utep, :worker, '2026-11-10', 235, 'closed', now());
insert into public.adbiz_entries (day_id, company_id, user_id, title, amount)
values ('dd160000-0000-4000-8000-000000000001', :utep, :worker, 'Vitrin', 270);
set role authenticated;

select tests.login(:owner);
create temp table r on commit drop as select public.adbiz_report_periods(:utep, 2026) j;
select tests.check((select (m ->> 'net')::numeric = 1576 and (m ->> 'gap')::numeric = -4658 and (m ->> 'imported')::boolean
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 11),
  'B1 November = the old 1306 / −4693 + the program''s 270 / +35');
select tests.check((select (m ->> 'net')::numeric = 7456 and (m ->> 'gap')::numeric = 1457
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 7), 'B2 July from the old table');
select tests.check((select (m ->> 'net')::numeric = 0 and not (m ->> 'imported')::boolean
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 12), 'B3 December: only the program (0)');
select tests.check((select (y ->> 'net')::numeric = 62062 and (y ->> 'gap')::numeric = -4162
                    from r, jsonb_array_elements(j -> 'years') y where (y ->> 'key')::int = 2026),
  'B4 the year 2026 = all its months');
select tests.check((select count(*) = 0 from public.adbiz_month_import where company_id = (select id from t where k = 'b')),
  'B5 another company gets nothing');

select public.adbiz_month_import_save(:utep, 2026, 6, 5700, -300);
select tests.check((select net = 5700 and gap = -300 from public.adbiz_month_import where company_id = :utep and year = 2026 and month = 6),
  'C1 the owner fixes a month');
select public.adbiz_month_import_save(:utep, 2025, 12, 4000, -100);
select tests.check((select count(*) = 1 from public.adbiz_report_periods(:utep, 2025) j, jsonb_array_elements(j -> 'years') y
                    where (y ->> 'key')::int = 2025 and (y ->> 'net')::numeric = 4000), 'C2 an older year appears with its old figures');
select public.adbiz_month_import_save(:utep, 2025, 12, null, null);
select tests.check(not exists (select 1 from public.adbiz_month_import where company_id = :utep and year = 2025), 'C3 both empty = taken off');
select tests.check((select count(*) >= 3 from public.adbiz_audit where action = 'month.import' and actor_id = :owner), 'C4 every change in the history');
select tests.check(tests.err(format($$ select public.adbiz_month_import_save(%L, 2026, 13, 1, 1) $$, :utep)) like '%invalid_argument%', 'C5 a real month');
select tests.check(tests.err(format($$ select public.adbiz_month_import_save(%L, 2026, 1, 1, 1) $$, (select id from t where k = 'b'))) like '%not_allowed%',
  'C6 not another company''s');

select tests.login(:worker);
select tests.check(not exists (select 1 from public.adbiz_month_import), 'D1 the worker reads no old figures');
select tests.check(tests.err(format($$ select public.adbiz_month_import_save(%L, 2026, 1, 1, 1) $$, :utep)) like '%not_allowed%', 'D2 …nor writes them');
select tests.check(tests.err(format($$ insert into public.adbiz_month_import (company_id, year, month) values (%L, 2030, 1) $$, :utep)) like '%permission denied%',
  'D3 no direct writes');
select tests.login(null);
select tests.check(tests.err(format($$ select public.adbiz_month_import_save(%L, 2026, 1, 1, 1) $$, :utep)) is not null, 'D4 visitors cannot');

select tests.summary('UTEP REKLAM KÖHNƏ HESAB (0116)');
rollback;

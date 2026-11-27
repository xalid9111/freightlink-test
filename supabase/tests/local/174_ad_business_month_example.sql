-- UTEP REKLAM — the owner's own example (27.11.2026): a monthly target of
-- 6110 AZN (235 × 26 work days); the month STARTS at −6110 and every day's
-- income brings it nearer to zero: day 1 with 235 → −5875, day 2 with 235
-- → −5640; a day's rasxod is taken off the income. The worker's notebook
-- (adbiz_my_month) and the owner's panel (adbiz_report_periods) agree.
-- A fresh company, September 2026 (no old account). Rolled back.
\set worker '''a0000000-0000-4000-8000-000000000012'''
\set chief  '''a0000000-0000-4000-8000-0000000000f1'''

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
insert into t values ('c', public.adbiz_admin_company_save(null, 'Neuro Reklam', 235));
select public.adbiz_month_target_set((select id from t where k = 'c'), '2026-09-01', 6110);
select public.adbiz_admin_member_set(:worker, (select id from t where k = 'c'), 'worker');

-- Before any day: the month starts at −6110.
create temp table q (step text, gap_panel numeric, gap_book numeric) on commit drop;
grant all on q to authenticated;
insert into q select '0',
  (select (m ->> 'gap')::numeric from public.adbiz_report_periods((select id from t where k = 'c'), 2026) j, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 9),
  (select (j ->> 'gap')::numeric from public.adbiz_my_month(:worker, '2026-09-15') j);
select tests.check((select gap_panel = -6110 and gap_book = -6110 from q where step = '0'), 'E1 the month starts at −6110 (panel and notebook)');

-- Day 1: income 235.
reset role;
insert into public.adbiz_days (id, company_id, user_id, work_date, target, status, closed_at)
values ('dd740000-0000-4000-8000-000000000001', (select id from t where k = 'c'), :worker, '2026-09-01', 235, 'closed', now());
insert into public.adbiz_entries (day_id, company_id, user_id, title, amount)
values ('dd740000-0000-4000-8000-000000000001', (select id from t where k = 'c'), :worker, 'Vitrin', 235);
set role authenticated;
select tests.login(:chief);
insert into q select '1',
  (select (m ->> 'gap')::numeric from public.adbiz_report_periods((select id from t where k = 'c'), 2026) j, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 9),
  (select (j ->> 'gap')::numeric from public.adbiz_my_month(:worker, '2026-09-15') j);
select tests.check((select gap_panel = -5875 and gap_book = -5875 from q where step = '1'), 'E2 day 1, 235 AZN → −5875');

-- Day 2: income 260, rasxod 25 → 235 net.
reset role;
insert into public.adbiz_days (id, company_id, user_id, work_date, target, status, closed_at)
values ('dd740000-0000-4000-8000-000000000002', (select id from t where k = 'c'), :worker, '2026-09-02', 235, 'closed', now());
insert into public.adbiz_entries (day_id, company_id, user_id, title, amount)
values ('dd740000-0000-4000-8000-000000000002', (select id from t where k = 'c'), :worker, 'Banner', 260);
insert into public.adbiz_expenses (company_id, day_id, user_id, spent_on, title, amount, created_by)
values ((select id from t where k = 'c'), 'dd740000-0000-4000-8000-000000000002', :worker, '2026-09-02', 'Boya', 25, :worker);
set role authenticated;
select tests.login(:chief);
insert into q select '2',
  (select (m ->> 'gap')::numeric from public.adbiz_report_periods((select id from t where k = 'c'), 2026) j, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 9),
  (select (j ->> 'gap')::numeric from public.adbiz_my_month(:worker, '2026-09-15') j);
select tests.check((select gap_panel = -5640 and gap_book = -5640 from q where step = '2'), 'E3 day 2, 260 − 25 rasxod → −5640');
select tests.check((select (j ->> 'collected')::numeric = 470 and (j ->> 'days')::int = 2 from public.adbiz_my_month(:worker, '2026-09-15') j),
  'E4 collected 470 in 2 days');

select tests.summary('UTEP REKLAM — SAHİBİN NÜMUNƏSİ (−6110 → −5875)');
rollback;

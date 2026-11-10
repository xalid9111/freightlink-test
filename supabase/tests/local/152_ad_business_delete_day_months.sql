-- UTEP REKLAM — 0115: delete a work day (owner / Baş admin, kept in the
-- history) and the month / year cards. Rolled back.
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

set role authenticated;
select tests.login(:chief);
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 235);
insert into t values ('b', public.adbiz_admin_company_save(null, 'Reklam B', 300));
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');
select public.adbiz_admin_member_set(:bwork, (select id from t where k = 'b'), 'worker');

-- Two closed days in March 2026 (target 235): 250 − 0 = +15, 200 − 20 = −55 → −40; a company expense of 30.
reset role;
-- The old account (0116) is checked in suite 153; here only the program's days count.
delete from public.adbiz_month_import;
insert into public.adbiz_days (id, company_id, user_id, work_date, target, status, closed_at)
values ('dd150000-0000-4000-8000-000000000001', :utep, :worker, '2026-03-10', 235, 'closed', now()),
       ('dd150000-0000-4000-8000-000000000002', :utep, :worker, '2026-03-11', 235, 'closed', now()),
       ('dd150000-0000-4000-8000-000000000003', :utep, :worker, '2025-12-30', 235, 'closed', now());
insert into public.adbiz_entries (day_id, company_id, user_id, title, amount) values
  ('dd150000-0000-4000-8000-000000000001', :utep, :worker, 'Vitrin', 250),
  ('dd150000-0000-4000-8000-000000000002', :utep, :worker, 'Nömrə', 200),
  ('dd150000-0000-4000-8000-000000000003', :utep, :worker, 'Banner', 100);
insert into public.adbiz_expenses (company_id, spent_on, title, amount, day_id, user_id) values
  (:utep, '2026-03-11', 'Yanacaq', 20, 'dd150000-0000-4000-8000-000000000002', :worker);
insert into public.adbiz_expenses (company_id, spent_on, title, amount) values (:utep, '2026-03-15', 'Boya', 30);
set role authenticated;

select tests.login(:owner);
create temp table r on commit drop as select public.adbiz_report_periods(:utep, 2026) j;
select tests.check((select jsonb_array_length(j -> 'months') = 12 from r), 'A1 twelve months');
select tests.check((select (m ->> 'net')::numeric = 400 and (m ->> 'gap')::numeric = -40
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 3),
  'A2 March: net 450 − 50 = 400; the days: +15 − 55 = −40');
select tests.check((select (m ->> 'net')::numeric = 0 and (m ->> 'gap')::numeric = 0
                    from r, jsonb_array_elements(j -> 'months') m where (m ->> 'key')::int = 7), 'A3 a month without days: 0 / 0');
select tests.check((select (y ->> 'net')::numeric = 100 and (y ->> 'gap')::numeric = -135
                    from r, jsonb_array_elements(j -> 'years') y where (y ->> 'key')::int = 2025), 'A4 the year 2025: 100, −135');
select tests.check((select count(*) >= 2 from r, jsonb_array_elements(j -> 'years')), 'A5 every year with work is listed');
select tests.check(tests.err(format($$ select public.adbiz_report_periods(%L, 2026) $$, (select id from t where k = 'b'))) like '%not_allowed%',
  'A6 not another company''s cards');

select tests.login(:worker);
select tests.check(tests.err(format($$ select public.adbiz_report_periods(%L, 2026) $$, :utep)) like '%not_allowed%', 'B1 the worker sees no cards');
select tests.check(tests.err($$ select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000001') $$) like '%not_allowed%',
  'B2 the worker deletes no day');
select tests.login(:bwork);
select tests.check(tests.err($$ select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000001') $$) like '%not_allowed%',
  'B3 another company cannot');
select tests.login(:other);
select tests.check(tests.err($$ select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000001') $$) like '%not_allowed%',
  'B4 a stranger cannot');

select tests.login(:owner);
select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000002');
reset role;
select tests.check(not exists (select 1 from public.adbiz_days where id = 'dd150000-0000-4000-8000-000000000002')
               and not exists (select 1 from public.adbiz_entries where day_id = 'dd150000-0000-4000-8000-000000000002')
               and not exists (select 1 from public.adbiz_expenses where day_id = 'dd150000-0000-4000-8000-000000000002'),
  'C1 the owner deletes the day with its jobs and rasxod');
select tests.check(exists (select 1 from public.adbiz_days where id = 'dd150000-0000-4000-8000-000000000001')
               and exists (select 1 from public.adbiz_expenses where title = 'Boya'), 'C2 nothing else goes');
select tests.check(exists (select 1 from public.adbiz_audit where action = 'day.delete' and actor_id = :owner
                           and old_value -> 'day' ->> 'work_date' = '2026-03-11'
                           and jsonb_array_length(old_value -> 'entries') = 1 and jsonb_array_length(old_value -> 'expenses') = 1),
  'C3 the whole day is kept in the history');
set role authenticated;
select tests.login(:chief);
select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000003');
select tests.check(not exists (select 1 from public.adbiz_days where id = 'dd150000-0000-4000-8000-000000000003'), 'C4 the Baş admin deletes too');
select tests.check(tests.err($$ select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000003') $$) like '%not_found%', 'C5 twice = not found');
select tests.login(null);
select tests.check(tests.err($$ select public.adbiz_delete_day('dd150000-0000-4000-8000-000000000001') $$) is not null, 'C6 visitors cannot');

select tests.summary('UTEP REKLAM GÜN SİLMƏ VƏ AYLAR (0115)');
rollback;

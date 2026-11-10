-- UTEP REKLAM — 0111: the worker's day expenses; saved jobs / expenses are
-- changed only by the owner or the Baş admin. Rolled back.
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

set role authenticated;
select tests.login(:chief);
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 235);
insert into t values ('b', public.adbiz_admin_company_save(null, 'Reklam B', 300));
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');
select public.adbiz_admin_member_set(:bwork, (select id from t where k = 'b'), 'worker');
select tests.login(:owner);
insert into t values ('cx', public.adbiz_expense_save(null, null, public._adbiz_today(), 'Ofis kirayəsi', 500));

-- ---- the worker: jobs 120, expense 30 → 90 left, 145 to the target ----------------------------
select tests.login(:worker);
insert into t values ('d', public.adbiz_open_day());
select public.adbiz_add_entry((select id from t where k = 'd'), 'Nömrə', 20);
select public.adbiz_add_entry((select id from t where k = 'd'), 'Kalçuk', 25);
select public.adbiz_add_entry((select id from t where k = 'd'), 'Banner', 35);
insert into t values ('e', public.adbiz_add_entry((select id from t where k = 'd'), 'Vinil', 40));
insert into t values ('x', public.adbiz_add_day_expense((select id from t where k = 'd'), 'Yanacaq', 30, 'c1000000-0000-4000-8000-000000000001'));
select tests.check(public.adbiz_add_day_expense((select id from t where k = 'd'), 'Yanacaq', 30, 'c1000000-0000-4000-8000-000000000001') = (select id from t where k = 'x'),
  'X1 a double tap = one expense');
select tests.check((select count(*) = 1 and sum(amount) = 30 from public.adbiz_expenses), 'X2 the worker sees only his own day expense (not the company''s rent)');
select tests.check((select sum(amount) from public.adbiz_entries) - (select sum(amount) from public.adbiz_expenses where day_id = (select id from t where k = 'd')) = 90,
  'X3 120 − 30 = 90 left for the day');
select tests.check((select day_id = (select id from t where k = 'd') and user_id = :worker and spent_on = public._adbiz_today()
                    from public.adbiz_expenses where id = (select id from t where k = 'x')), 'X4 bound to the day and the worker');
select tests.check(tests.err(format($$ select public.adbiz_update_entry(%L, 'Vinil', 4) $$, (select id from t where k = 'e'))) like '%not_allowed%',
  'X5 the worker cannot change a saved job (open day)');
select tests.check(tests.err(format($$ select public.adbiz_delete_entry(%L) $$, (select id from t where k = 'e'))) like '%not_allowed%',
  'X6 …nor delete it');
select tests.check(tests.err(format($$ select public.adbiz_expense_save(%L, null, current_date, 'x', 1) $$, (select id from t where k = 'x'))) like '%not_allowed%',
  'X7 …nor change his expense');
select tests.check(tests.err(format($$ select public.adbiz_expense_delete(%L) $$, (select id from t where k = 'x'))) like '%not_allowed%',
  'X8 …nor delete it');
select tests.check(tests.err(format($$ select public.adbiz_add_day_expense(%L, 'x', 0) $$, (select id from t where k = 'd'))) like '%invalid_argument%', 'X9 no zero expense');
select public.adbiz_close_day((select id from t where k = 'd'));
select tests.check(tests.err(format($$ select public.adbiz_add_day_expense(%L, 'late', 5) $$, (select id from t where k = 'd'))) like '%day_closed%', 'X10 closed: no new expense');

select tests.login(:bwork);
select tests.check(not exists (select 1 from public.adbiz_expenses), 'X11 another company sees none of it');
select tests.check(tests.err(format($$ select public.adbiz_add_day_expense(%L, 'x', 5) $$, (select id from t where k = 'd'))) like '%not_allowed%', 'X12 …and cannot write into it');

-- ---- the owner / Baş admin fix, with history; the report counts the day expense ------------------
select tests.login(:owner);
select public.adbiz_expense_save((select id from t where k = 'x'), null, public._adbiz_today(), 'Yanacaq', 35);
select tests.check(exists (select 1 from public.adbiz_audit where action = 'expense.update' and old_value ->> 'amount' = '30.00' and new_value ->> 'amount' = '35.00'),
  'X13 the owner''s fix: old / new kept');
select tests.check((public.adbiz_report(:utep, public._adbiz_today(), public._adbiz_today()) ->> 'expenses')::numeric = 35
                   + (select amount from public.adbiz_expenses where id = (select id from t where k = 'cx') and spent_on = public._adbiz_today()),
  'X14 the owner''s report counts the day expense with the company''s');
select tests.login(:chief);
select public.adbiz_update_entry((select id from t where k = 'e'), 'Vinil', 45);
select tests.check(exists (select 1 from public.adbiz_audit where action = 'entry.update' and actor_id = :chief and new_value ->> 'amount' = '45.00'), 'X15 the Baş admin fixes a job');
select tests.summary('UTEP REKLAM RASXOD (0111)');
rollback;

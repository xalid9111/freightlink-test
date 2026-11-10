-- UTEP REKLAM — 0110: companies kept apart, only the Baş admin switches the
-- module on, the work notebook (open day, jobs, close), targets that never
-- rewrite older days, owner / admin fixes with history. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000011'''
\set worker '''a0000000-0000-4000-8000-000000000012'''
\set w2     '''a0000000-0000-4000-8000-000000000013'''
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
create temp table roles_before on commit drop as select id, role from public.users;
grant all on t to authenticated;

set role authenticated;

-- ---- only the Baş admin switches it on ---------------------------------------------
select tests.login(:other);
select tests.check(public.adbiz_me() is null, 'A1 a normal user: no Reklam entry');
select tests.check(not exists (select 1 from public.adbiz_companies), 'A2 a normal user sees no company');
select tests.check(tests.err(format($$ select public.adbiz_admin_member_set(%L, %L, 'owner') $$, :other, :utep)) like '%chief_admin_only%', 'A3 nobody adds himself');
select tests.login(:admin);
select tests.check(tests.err(format($$ select public.adbiz_admin_member_set(%L, %L, 'worker') $$, :worker, :utep)) like '%chief_admin_only%', 'A4 an ordinary admin cannot either');
select tests.check(tests.err($$ select public.adbiz_admin_company_save(null, 'X Reklam', 100) $$) like '%chief_admin_only%', 'A5 …nor make a company');

select tests.login(:chief);
select tests.check((public.adbiz_me() ->> 'chief')::boolean, 'B1 the Baş admin sees the module');
select tests.check((select count(*) = 1 from public.adbiz_companies where name = 'UTEP Reklam'), 'B2 UTEP Reklam is there');
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 235);
insert into t values ('b', public.adbiz_admin_company_save(null, 'Reklam B', 300));
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');
select public.adbiz_admin_member_set(:bwork, (select id from t where k = 'b'), 'worker');
select tests.check((select count(*) = 3 from public.adbiz_members), 'B3 three members at once (no invitation)');
select tests.check((select count(*) >= 1 from public.adbiz_admin_search_users('owner')), 'B4 search existing accounts');
select tests.check(tests.err(format($$ select public.adbiz_admin_member_set(%L, %L, 'boss') $$, :w2, :utep)) like '%invalid_argument%', 'B5 only owner / worker');

-- ---- the worker's notebook ------------------------------------------------------------
select tests.login(:worker);
select tests.check(public.adbiz_me() ->> 'role' = 'worker' and (public.adbiz_me() ->> 'daily_target')::numeric = 235, 'C1 the worker: role + target from the company');
insert into t values ('d', public.adbiz_open_day());
select tests.check(public.adbiz_open_day() = (select id from t where k = 'd'), 'C2 opening twice = the same day');
select tests.check((select target = 235 and status = 'open' from public.adbiz_days where id = (select id from t where k = 'd')), 'C3 the day keeps 235');
insert into t values ('e1', public.adbiz_add_entry((select id from t where k = 'd'), 'Nömrə', 20, 'c0000000-0000-4000-8000-000000000001'));
select tests.check(public.adbiz_add_entry((select id from t where k = 'd'), 'Nömrə', 20, 'c0000000-0000-4000-8000-000000000001') = (select id from t where k = 'e1'),
  'C4 a double tap: the same job');
insert into t values ('e2', public.adbiz_add_entry((select id from t where k = 'd'), 'Kalçuk', 25, 'c0000000-0000-4000-8000-000000000002'));
select tests.check((select count(*) = 2 and sum(amount) = 45 from public.adbiz_entries), 'C5 two jobs, 45');
select tests.check(tests.err(format($$ select public.adbiz_add_entry(%L, 'x', 0) $$, (select id from t where k = 'd'))) like '%invalid_argument%', 'C6 no zero amounts');
select public.adbiz_update_entry((select id from t where k = 'e2'), 'Kalçuk', 30);
select tests.check(not exists (select 1 from public.adbiz_expenses), 'C7 a worker sees no expenses');
select tests.check(not exists (select 1 from public.adbiz_audit), 'C8 …nor the history');
select tests.check(tests.err(format($$ insert into public.adbiz_entries (day_id, company_id, user_id, title, amount) values (%L, %L, auth.uid(), 'x', 1) $$,
  (select id from t where k = 'd'), :utep)) like '%permission denied%', 'C9 no direct writes');
select public.adbiz_close_day((select id from t where k = 'd'));
select tests.check((select status = 'closed' from public.adbiz_days where id = (select id from t where k = 'd')), 'C10 closed below the target (50 < 235)');
select tests.check(tests.err(format($$ select public.adbiz_add_entry(%L, 'late', 10) $$, (select id from t where k = 'd'))) like '%day_closed%', 'C11 closed: no new job');
select tests.check(tests.err(format($$ select public.adbiz_update_entry(%L, 'x', 99) $$, (select id from t where k = 'e1'))) like '%day_closed%', 'C12 closed: no change');
select tests.check(tests.err(format($$ select public.adbiz_delete_entry(%L) $$, (select id from t where k = 'e1'))) like '%day_closed%', 'C13 closed: no delete');
select tests.check(tests.err(format($$ select public.adbiz_reopen_day(%L) $$, (select id from t where k = 'd'))) like '%not_allowed%', 'C14 the worker cannot re-open');

-- ---- another company sees nothing --------------------------------------------------------
select tests.login(:bwork);
select tests.check(not exists (select 1 from public.adbiz_entries) and not exists (select 1 from public.adbiz_days), 'D1 company B: no UTEP days / jobs');
select tests.check((select count(*) = 1 from public.adbiz_companies), 'D2 company B sees only its own company');
select tests.check(tests.err(format($$ select public.adbiz_add_entry(%L, 'x', 5) $$, (select id from t where k = 'd'))) like '%not_allowed%', 'D3 …and cannot write into it');
select tests.check(tests.err(format($$ select public.adbiz_report(%L, current_date - 30, current_date) $$, :utep)) like '%not_allowed%', 'D4 …nor read its report');

-- ---- the owner -----------------------------------------------------------------------------
select tests.login(:owner);
select tests.check((select count(*) = 2 from public.adbiz_entries), 'E1 the owner sees his workers'' jobs');
select public.adbiz_update_entry((select id from t where k = 'e1'), 'Nömrə', 22);
select tests.check(exists (select 1 from public.adbiz_audit where action = 'entry.update' and old_value ->> 'amount' = '20.00'
  and new_value ->> 'amount' = '22.00' and actor_id = :owner), 'E2 an owner fix on a closed day: old / new / who / when');
select public.adbiz_reopen_day((select id from t where k = 'd'));
select public.adbiz_close_day((select id from t where k = 'd'));
select tests.check((select count(*) = 2 from public.adbiz_audit where action in ('day.reopen', 'day.close') and actor_id = :owner), 'E3 re-open + close by the owner, logged');
insert into t values ('x', public.adbiz_expense_save(null, null, current_date, 'Boya', 12, 'c0000000-0000-4000-8000-000000000009'));
select tests.check(public.adbiz_expense_save(null, null, current_date, 'Boya', 12, 'c0000000-0000-4000-8000-000000000009') = (select id from t where k = 'x'), 'E4 expense double tap = one');
select tests.check((public.adbiz_report(:utep, public._adbiz_today() - 1, public._adbiz_today()) ->> 'income')::numeric = 52
               and (public.adbiz_report(:utep, public._adbiz_today() - 1, public._adbiz_today()) ->> 'expenses')::numeric = 12
               and (public.adbiz_report(:utep, public._adbiz_today() - 1, public._adbiz_today()) ->> 'net')::numeric = 40, 'E5 income 52, expenses 12, net 40');
select tests.check(tests.err(format($$ select public.adbiz_report(%L, current_date - 1, current_date) $$, (select id from t where k = 'b'))) like '%not_allowed%', 'E6 not another company''s report');
select tests.check(tests.err($$ select public.adbiz_owner_add_worker('owner3@t.test') $$) like '%not_allowed%', 'E7 adding workers needs the Baş admin''s permission');
select tests.check(tests.err(format($$ select public.adbiz_member_set_active(%L, false) $$, :worker)) like '%not_allowed%', 'E8 …and so does taking one off');

-- ---- the Baş admin: targets, permission, fixes ---------------------------------------------
select tests.login(:chief);
select public.adbiz_admin_company_save(:utep, 'UTEP Reklam', 300, true);
select tests.check((select target = 235 from public.adbiz_days where id = (select id from t where k = 'd')), 'F1 a new target never rewrites an old day');
select tests.check((select count(*) >= 2 from public.adbiz_target_history where company_id = :utep), 'F2 target history kept');
select public.adbiz_admin_member_target(:worker, 180);
select tests.check((select personal_target = 180 from public.adbiz_members where user_id = :worker), 'F3 a worker''s own target');
select tests.check(exists (select 1 from public.adbiz_entries) and exists (select 1 from public.adbiz_companies where name = 'Reklam B'), 'F4 the Baş admin sees every company');
select public.adbiz_delete_entry((select id from t where k = 'e2'));
select tests.check(exists (select 1 from public.adbiz_audit where action = 'entry.delete' and actor_id = :chief and old_value ->> 'amount' = '30.00'), 'F5 a deleted job stays in the history');
select tests.check(tests.err(format($$ select public.adbiz_open_day_for(%L, current_date + 3) $$, :worker)) like '%invalid_argument%', 'F6 no future days');

select tests.login(:owner);
select tests.check(public.adbiz_owner_add_worker('owner3@t.test') = :w2, 'G1 allowed now: the owner adds an existing account as a worker');
select tests.check(tests.err($$ select public.adbiz_owner_add_worker('owner4@t.test') $$) like '%other_company%', 'G2 never a member of another company');
select public.adbiz_member_set_active(:w2, false);
select tests.check(tests.err(format($$ select public.adbiz_member_set_active(%L, false) $$, :owner)) like '%not_allowed%', 'G3 the owner never switches himself off');

select tests.login(:w2);
select tests.check(public.adbiz_me() is null, 'H1 switched off: no Reklam entry');
select tests.check(tests.err($$ select public.adbiz_open_day() $$) like '%not_member%', 'H2 …and no day');
select tests.login(:chief);
select public.adbiz_member_set_active(:w2, true);
select tests.login(:w2);
select tests.check(public.adbiz_me() ->> 'role' = 'worker', 'H3 switched on again');
select tests.login(:worker);
select tests.check(public.adbiz_open_day() = (select id from t where k = 'd'), 'H4 today is the same day (re-opening is the owner''s)');

reset role;
select tests.check(not exists (select 1 from public.users u join roles_before r using (id) where u.role is distinct from r.role), 'I1 nobody''s FreightLink role changed');
select tests.summary('UTEP REKLAM (0110)');
rollback;

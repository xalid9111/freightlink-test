-- UTEP REKLAM — 0113: the owner's words for the workers, the target on / off,
-- jobs paid by card (a tick the worker sets / takes off on his own open day).
-- Rolled back.
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

-- ---- the owner's words ------------------------------------------------------------------
select tests.login(:owner);
select tests.check((select show_target and target_label is null and task_note is null from public.adbiz_companies where id = :utep),
  'A1 at the start: the target shown, no own words');
select public.adbiz_company_texts_save(:utep, '  Bu gün 235-ə çatırıq!  ', 'Yeni nömrələri götür');
select tests.check((select target_label = 'Bu gün 235-ə çatırıq!' and task_note = 'Yeni nömrələri götür' from public.adbiz_companies where id = :utep),
  'A2 the owner writes the caption and the task (trimmed)');
select public.adbiz_member_task_save(:worker, 'Gəncə yolunda 3 vitrin');
select tests.check((select task_note = 'Gəncə yolunda 3 vitrin' from public.adbiz_members where user_id = :worker), 'A3 a task for one worker');
select tests.check(exists (select 1 from public.adbiz_audit where action = 'company.texts' and actor_id = :owner)
               and exists (select 1 from public.adbiz_audit where action = 'member.task' and actor_id = :owner), 'A4 both in the history');
select tests.check(tests.err(format($$ select public.adbiz_company_texts_save(%L, repeat('x', 61), null) $$, :utep)) like '%invalid_argument%',
  'A5 the caption is short (60)');
select tests.check(tests.err(format($$ select public.adbiz_company_texts_save(%L, 'x', null) $$, (select id from t where k = 'b'))) like '%not_allowed%',
  'A6 not another company''s words');
select tests.check(tests.err(format($$ select public.adbiz_member_task_save(%L, 'x') $$, :bwork)) like '%not_allowed%',
  'A7 …nor its worker''s task');
select public.adbiz_company_show_target(:utep, false);
select tests.check((select not show_target from public.adbiz_companies where id = :utep), 'A8 the owner hides the target from the workers');
select public.adbiz_company_show_target(:utep, true);

select tests.login(:worker);
select tests.check((select target_label = 'Bu gün 235-ə çatırıq!' and show_target from public.adbiz_companies where id = :utep)
               and (select task_note = 'Gəncə yolunda 3 vitrin' from public.adbiz_members where user_id = :worker),
  'B1 the worker reads the words, the switch and his own task');
select tests.check(tests.err(format($$ select public.adbiz_company_texts_save(%L, 'mən', null) $$, :utep)) like '%not_allowed%',
  'B2 the worker writes no words');
select tests.check(tests.err(format($$ select public.adbiz_member_task_save(%L, 'özüm') $$, :worker)) like '%not_allowed%', 'B3 …nor his own task');
select tests.check(tests.err(format($$ select public.adbiz_company_show_target(%L, false) $$, :utep)) like '%not_allowed%', 'B4 …nor the switch');

-- ---- card payments ---------------------------------------------------------------------------
insert into t values ('d', public.adbiz_open_day());
insert into t values ('e1', public.adbiz_add_entry((select id from t where k = 'd'), 'Nömrə', 20, 'c1300000-0000-4000-8000-000000000001', true));
insert into t values ('e2', public.adbiz_add_entry((select id from t where k = 'd'), 'Kalçuk', 25, 'c1300000-0000-4000-8000-000000000002'));
insert into t values ('e3', public.adbiz_add_entry((select id from t where k = 'd'), 'Vitrin', 15));
select tests.check((select paid_card from public.adbiz_entries where id = (select id from t where k = 'e1'))
               and (select not paid_card from public.adbiz_entries where id = (select id from t where k = 'e2'))
               and (select not paid_card from public.adbiz_entries where id = (select id from t where k = 'e3')),
  'C1 a ticked job is a card job; the old 4- and 3-argument calls are cash');
select tests.check(public.adbiz_add_entry((select id from t where k = 'd'), 'Nömrə', 20, 'c1300000-0000-4000-8000-000000000001', true) = (select id from t where k = 'e1'),
  'C2 a double tap: still one job');
select public.adbiz_entry_set_card((select id from t where k = 'e2'), true);
select public.adbiz_entry_set_card((select id from t where k = 'e1'), false);
select tests.check((select paid_card from public.adbiz_entries where id = (select id from t where k = 'e2'))
               and (select not paid_card from public.adbiz_entries where id = (select id from t where k = 'e1')),
  'C3 the worker puts / takes off the tick on his open day (a mistake)');
select tests.check(tests.err(format($$ select public.adbiz_update_entry(%L, 'x', 99) $$, (select id from t where k = 'e2'))) like '%not_allowed%',
  'C4 …but still never changes the name / amount');
select public.adbiz_close_day((select id from t where k = 'd'));
select tests.check(tests.err(format($$ select public.adbiz_entry_set_card(%L, false) $$, (select id from t where k = 'e2'))) like '%day_closed%',
  'C5 a closed day: the worker''s tick stays');

select tests.login(:bwork);
select tests.check(tests.err(format($$ select public.adbiz_entry_set_card(%L, false) $$, (select id from t where k = 'e2'))) like '%not_allowed%',
  'C6 another company never touches it');

select tests.login(:owner);
select public.adbiz_entry_set_card((select id from t where k = 'e3'), true);
select tests.check((select paid_card from public.adbiz_entries where id = (select id from t where k = 'e3')), 'C7 the owner fixes a tick on a closed day');
select tests.check((select count(*) = 3 from public.adbiz_audit where action = 'entry.card'), 'C8 every tick change in the history');
select tests.check((public.adbiz_report(:utep, public._adbiz_today(), public._adbiz_today()) ->> 'income')::numeric = 60
               and (public.adbiz_report(:utep, public._adbiz_today(), public._adbiz_today()) ->> 'card')::numeric = 40
               and (public.adbiz_report(:utep, public._adbiz_today(), public._adbiz_today()) ->> 'cash')::numeric = 20,
  'C9 the report: income 60, by card 40, cash 20');
select tests.check((select (w ->> 'card')::numeric = 40 and w ->> 'task_note' = 'Gəncə yolunda 3 vitrin'
                    from jsonb_array_elements(public.adbiz_report(:utep, public._adbiz_today(), public._adbiz_today()) -> 'workers') w
                    where w ->> 'user_id' = :worker), 'C10 …and per worker, with his task');

select tests.login(:other);
select tests.check(tests.err(format($$ select public.adbiz_entry_set_card(%L, true) $$, (select id from t where k = 'e1'))) like '%not_allowed%',
  'C11 a stranger cannot');
select tests.check(tests.err(format($$ select public.adbiz_add_entry(%L, 'x', 5) $$, (select id from t where k = 'd'))) like '%not_allowed%'
               and tests.err(format($$ select public.adbiz_close_day(%L) $$, (select id from t where k = 'd'))) like '%not_allowed%'
               and tests.err(format($$ select public.adbiz_reopen_day(%L) $$, (select id from t where k = 'd'))) like '%not_allowed%'
               and tests.err(format($$ select public.adbiz_delete_entry(%L) $$, (select id from t where k = 'e1'))) like '%not_allowed%',
  'C11b an account in no company is refused everywhere (the null rights check, fixed in 0113)');
reset role;
select tests.check((select count(*) = 3 from public.adbiz_entries where day_id = (select id from t where k = 'd'))
               and (select status = 'closed' from public.adbiz_days where id = (select id from t where k = 'd')), 'C11c …nothing changed');
set role authenticated;
select tests.login(null);
select tests.check(tests.err(format($$ select public.adbiz_company_show_target(%L, true) $$, :utep)) is not null, 'C12 visitors cannot');

select tests.summary('UTEP REKLAM SÖZLƏR VƏ KART (0113)');
rollback;

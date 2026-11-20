-- 0132 UTEP Reklam: the worker changes a job's price on his own today's open
-- day with a note (Qeyd); kept: first price, note, history. Rolled back.
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
select public.adbiz_admin_member_set(:owner, :utep, 'owner');
select public.adbiz_admin_member_set(:worker, :utep, 'worker');
select public.adbiz_admin_member_set(:bwork, :utep, 'worker');

select tests.login(:worker);
insert into t values ('d', public.adbiz_open_day());
insert into t values ('e', public.adbiz_add_entry((select id from t where k = 'd'), 'Vizit kart', 40, gen_random_uuid()));
select tests.check(tests.err(format($$ select public.adbiz_entry_worker_fix(%L, 35, '  ') $$, (select id from t where k = 'e'))) like '%note_required%',
  'W1 the note (Qeyd) is required');
select tests.check(tests.err(format($$ select public.adbiz_entry_worker_fix(%L, 0, 'Endirim') $$, (select id from t where k = 'e'))) like '%invalid_argument%',
  'W2 a real amount');
select public.adbiz_entry_worker_fix((select id from t where k = 'e'), 35, '  Endirim  ');
select tests.check((select amount = 35 and fixed_from = 40 and fix_note = 'Endirim' and fixed_by = auth.uid() and title = 'Vizit kart'
                    from public.adbiz_entries where id = (select id from t where k = 'e')), 'W3 the worker changes the price; the first price and the note are kept');
select public.adbiz_entry_worker_fix((select id from t where k = 'e'), 30, 'Yenə endirim');
select tests.check((select amount = 30 and fixed_from = 40 from public.adbiz_entries where id = (select id from t where k = 'e')), 'W4 a second fix keeps the FIRST price');
reset role;
select tests.check((select count(*) = 2 and bool_and(new_value ->> 'note' is not null) from public.adbiz_audit
                     where action = 'entry.worker_fix' and actor_id = :worker), 'W5 every fix is in the history (with the note)');
set role authenticated;
select tests.login(:worker);
select tests.check(tests.err(format($$ select public.adbiz_update_entry(%L, 'Başqa ad', 30) $$, (select id from t where k = 'e'))) like '%not_allowed%',
  'W6 the worker still cannot rename / use the owner''s edit');

-- Another worker never; a closed day never.
select tests.login(:bwork);
select tests.check(tests.err(format($$ select public.adbiz_entry_worker_fix(%L, 10, 'Mənim') $$, (select id from t where k = 'e'))) like '%not_allowed%',
  'W7 not another worker''s job');
select tests.login(:worker);
select public.adbiz_close_day((select id from t where k = 'd'));
select tests.check(tests.err(format($$ select public.adbiz_entry_worker_fix(%L, 20, 'Gec') $$, (select id from t where k = 'e'))) like '%day_closed%',
  'W8 not on a closed day');
reset role;
update public.adbiz_days set status = 'open', closed_at = null, closed_by = null, work_date = work_date - 1 where id = (select id from t where k = 'd');
set role authenticated;
select tests.login(:worker);
select tests.check(tests.err(format($$ select public.adbiz_entry_worker_fix(%L, 20, 'Dünən') $$, (select id from t where k = 'e'))) like '%day_closed%',
  'W9 not on a past day');
select tests.check(tests.err($$ update public.adbiz_entries set amount = 1 $$) is not null or
                   (select count(*) = 0 from public.adbiz_entries where amount = 1), 'W10 no direct writes');
rollback;

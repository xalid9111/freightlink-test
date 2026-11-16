-- UTEP REKLAM — 0126: the Baş admin deletes a company (long press): off the
-- list, its people lose the module, its data stays, kept in the history.
-- Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000011'''
\set worker '''a0000000-0000-4000-8000-000000000012'''
\set w2     '''a0000000-0000-4000-8000-000000000013'''
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
insert into t values ('x', public.adbiz_admin_company_save(null, 'Test Reklam', 200));
select public.adbiz_admin_member_set(:owner, (select id from t where k = 'x'), 'owner');
select public.adbiz_admin_member_set(:worker, (select id from t where k = 'x'), 'worker');

select tests.login(:worker);
insert into t values ('d', public.adbiz_open_day());
select public.adbiz_add_entry((select id from t where k = 'd'), 'Banner', 40, gen_random_uuid());
select tests.check(public.adbiz_me() is not null, 'A1 before: the worker has the notebook');

select tests.login(:admin);
select tests.check(tests.err(format($$ select public.adbiz_admin_company_delete(%L) $$, (select id from t where k = 'x'))) like '%chief_admin_only%',
  'A2 an ordinary admin cannot delete a company');
select tests.login(:owner);
select tests.check(tests.err(format($$ select public.adbiz_admin_company_delete(%L) $$, (select id from t where k = 'x'))) like '%chief_admin_only%',
  'A3 the company''s owner cannot either');
select tests.login(null);
select tests.check(tests.err(format($$ select public.adbiz_admin_company_delete(%L) $$, (select id from t where k = 'x'))) is not null,
  'A4 visitors cannot');

select tests.login(:chief);
select public.adbiz_admin_company_delete((select id from t where k = 'x'));
select public.adbiz_admin_company_delete((select id from t where k = 'x')); -- a second tap
select tests.check((select deleted_at is not null and not is_active from public.adbiz_companies where id = (select id from t where k = 'x')),
  'B1 the company is marked deleted and switched off');
select tests.check(tests.err(format($$ select public.adbiz_admin_company_set_active(%L, true) $$, (select id from t where k = 'x'))) like '%company_deleted%',
  'B2 a deleted company is not switched on again');
select tests.check(tests.err(format($$ select public.adbiz_admin_member_set(%L, %L, 'worker') $$, :w2, (select id from t where k = 'x'))) like '%company_deleted%',
  'B3 …and gets no new people');
select tests.check((select count(*) = 1 from public.adbiz_audit where company_id = (select id from t where k = 'x') and action = 'company.delete'
                    and old_value ->> 'name' = 'Test Reklam'),
  'B4 one history row with the whole company (a second tap adds none)');

select tests.login(:worker);
select tests.check(public.adbiz_me() is null, 'C1 the worker has no notebook any more');
select tests.login(:owner);
select tests.check(public.adbiz_me() is null, 'C2 the owner has no business page any more');

reset role;
select tests.check((select count(*) = 1 from public.adbiz_days where id = (select id from t where k = 'd')),
  'D1 the day is kept');
select tests.check((select count(*) = 1 and sum(amount) = 40 from public.adbiz_entries where day_id = (select id from t where k = 'd')),
  'D2 the job is kept');
select tests.check((select count(*) = 2 from public.adbiz_members where company_id = (select id from t where k = 'x')),
  'D3 the people''s rows are kept');

select tests.summary('UTEP REKLAM ŞİRKƏTİ SİL (0126)');
rollback;

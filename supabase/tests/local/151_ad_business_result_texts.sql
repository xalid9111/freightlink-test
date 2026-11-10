-- UTEP REKLAM — 0114: the owner writes the day's result message. Rolled back.
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

select tests.login(:owner);
select tests.check((select result_miss_text is null and result_hit_text is null from public.adbiz_companies where id = :utep),
  'A1 at the start: the app''s own words');
select public.adbiz_company_result_texts_save(:utep, '  Bu gün {qalan} AZN çatmadı. Sabah daha güclü!  ', 'Əla! {gəlir}/{hədəf} AZN');
select tests.check((select result_miss_text = 'Bu gün {qalan} AZN çatmadı. Sabah daha güclü!' and result_hit_text = 'Əla! {gəlir}/{hədəf} AZN'
                    from public.adbiz_companies where id = :utep), 'A2 the owner writes both messages (trimmed)');
select tests.check(exists (select 1 from public.adbiz_audit where action = 'company.result_texts' and actor_id = :owner), 'A3 in the history');
select public.adbiz_company_result_texts_save(:utep, '   ', null);
select tests.check((select result_miss_text is null and result_hit_text is null from public.adbiz_companies where id = :utep),
  'A4 emptied = back to the app''s words');
select tests.check(tests.err(format($$ select public.adbiz_company_result_texts_save(%L, repeat('x', 201), null) $$, :utep)) like '%invalid_argument%',
  'A5 at most 200 letters');
select tests.check(tests.err(format($$ select public.adbiz_company_result_texts_save(%L, 'x', 'y') $$, (select id from t where k = 'b'))) like '%not_allowed%',
  'A6 not another company''s');

select tests.login(:worker);
select tests.check(tests.err(format($$ select public.adbiz_company_result_texts_save(%L, 'mən', null) $$, :utep)) like '%not_allowed%',
  'B1 the worker writes none');
select tests.check((select result_miss_text is null from public.adbiz_companies where id = :utep), 'B2 …but reads his company''s');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.adbiz_company_result_texts_save(%L, 'x', null) $$, :utep)) like '%not_allowed%',
  'B3 a stranger cannot');
select tests.login(:chief);
select public.adbiz_company_result_texts_save(:utep, null, 'Təbriklər, {gəlir} AZN!');
select tests.check((select result_hit_text = 'Təbriklər, {gəlir} AZN!' from public.adbiz_companies where id = :utep), 'B4 the Baş admin writes too');
select tests.login(null);
select tests.check(tests.err(format($$ select public.adbiz_company_result_texts_save(%L, 'x', null) $$, :utep)) is not null, 'B5 visitors cannot');

select tests.summary('UTEP REKLAM GÜNÜN NƏTİCƏ YAZISI (0114)');
rollback;

-- UTEP REKLAM — the owner panel's numbers checked end to end (owner,
-- 21.11.2026: "bütün gün, ay və il hesablamasını kontrol et … noyabrın 1-nə
-- 500 AZN yazdım"): a job / rasxod written on an OLD day counts in that day,
-- its month and its year; card money inside the income; the month card's net
-- = the panel's net + the old account. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000011'''
\set worker '''a0000000-0000-4000-8000-000000000012'''
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

-- The owner opens his worker's OLD day (1 November) and writes 500, 40 by card, and 60 rasxod.
select tests.login(:owner);
insert into t values ('d1', public.adbiz_open_day_for(:worker, '2026-11-01'));
select public.adbiz_add_entry((select id from t where k = 'd1'), 'Köhnə iş', 500, gen_random_uuid());
select public.adbiz_add_entry((select id from t where k = 'd1'), 'Kartla', 40, gen_random_uuid(), true);
select public.adbiz_add_day_expense((select id from t where k = 'd1'), 'Boya', 60, gen_random_uuid());
-- Another day in November.
insert into t values ('d2', public.adbiz_open_day_for(:worker, '2026-11-20'));
select public.adbiz_add_entry((select id from t where k = 'd2'), 'Vitrin', 100, gen_random_uuid());

select tests.check((select (j ->> 'income')::numeric = 540 and (j ->> 'card')::numeric = 40 and (j ->> 'expenses')::numeric = 60
                    and (j ->> 'net')::numeric = 480 from public.adbiz_report(:utep, '2026-11-01', '2026-11-01') j),
  'T1 Gün (1 noyabr): 540 income, 40 by card, 60 rasxod, 480 net');
select tests.check((select (j ->> 'income')::numeric = 640 and (j ->> 'card')::numeric = 40 and (j ->> 'expenses')::numeric = 60
                    and (j ->> 'net')::numeric = 580 from public.adbiz_report(:utep, '2026-11-01', '2026-11-30') j),
  'T2 Ay (noyabr): both days');
select tests.check((select (j ->> 'net')::numeric = (select (j2 ->> 'net')::numeric from public.adbiz_report(:utep, '2026-01-01', '2026-12-31') j2)
                    - (select coalesce(sum((j3 ->> 'net')::numeric), 0) from public.adbiz_report(:utep, '2026-01-01', '2026-10-31') j3)
                    - (select coalesce(sum((j4 ->> 'net')::numeric), 0) from public.adbiz_report(:utep, '2026-12-01', '2026-12-31') j4)
                    from public.adbiz_report(:utep, '2026-11-01', '2026-11-30') j),
  'T3 İl = its months');
select tests.check((select (m ->> 'net')::numeric = 580 + (select coalesce(net, 0) from public.adbiz_month_import
                                                          where company_id = :utep and year = 2026 and month = 11)
                    from public.adbiz_report_periods(:utep, 2026) p, jsonb_array_elements(p -> 'months') m where (m ->> 'key')::int = 11),
  'T4 the month card''s net = the panel''s net + the old account');
select tests.check((select (j ->> 'days_open')::int + (j ->> 'days_closed')::int = 2 from public.adbiz_report(:utep, '2026-11-01', '2026-11-30') j),
  'T5 both days are recorded');

select tests.summary('UTEP REKLAM HESABLAMA YOXLAMASI');
rollback;

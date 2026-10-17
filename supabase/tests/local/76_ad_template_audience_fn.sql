-- ADS — 0038: admin_set_ad_template_audience restored on a database where
-- 0029 only partly applied. Rolled back at the end.
-- Run with: psql -v mig38=<path to 0038_ad_template_audience_fn.sql>
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
-- Live situation: the function is missing.
drop function if exists public.admin_set_ad_template_audience(uuid, text);
select tests.check(to_regprocedure('public.admin_set_ad_template_audience(uuid,text)') is null, 'A0 function missing (live situation)');
\i :mig38
select tests.check(to_regprocedure('public.admin_set_ad_template_audience(uuid,text)') is not null, 'A1 0038 creates the missing function');
-- create_service_ad_order (newer version from 0032) is untouched.
select tests.check(to_regprocedure('public.create_service_ad_order(uuid,uuid,jsonb,jsonb,text,text,integer,text[],text)') is not null,
  'A2 create_service_ad_order (0032 version) untouched');

set role authenticated;
select tests.login(:admin);
create temp table t_t as select * from public.admin_save_ad_template_v2(null, 'Tent', 'https://x/storage/v1/object/public/ads/templates/t.png', true, 1);
grant select on t_t to authenticated;
select public.admin_set_ad_template_audience((select id from t_t), 'service');
select tests.check((select audience = 'service' from public.ad_templates where id = (select id from t_t)), 'A3 admin saves a template as "Servis"');
select public.admin_set_ad_template_audience((select id from t_t), 'all');
select tests.check((select audience = 'all' from public.ad_templates where id = (select id from t_t)), 'A4 … and as "Hər ikisi"');
select tests.check(tests.err(format($$ select public.admin_set_ad_template_audience(%L, 'x') $$, (select id from t_t))) like '%invalid_audience%',
  'A5 only cargo / service / all');

select tests.login(:other);
select tests.check(tests.err(format($$ select public.admin_set_ad_template_audience(%L, 'cargo') $$, (select id from t_t))) like '%admin_only%',
  'A6 non-admins are refused');
reset role;

-- Re-runnable.
\i :mig38
select tests.check(to_regprocedure('public.admin_set_ad_template_audience(uuid,text)') is not null, 'A7 second run is fine');

select tests.summary('AD TEMPLATE AUDIENCE FN (0038)');
rollback;

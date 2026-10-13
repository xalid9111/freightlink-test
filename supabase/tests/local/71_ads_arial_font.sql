-- ADS — 0033: font "Arial" accepted. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
create temp table t_tpl as select * from public.admin_save_ad_template_v2(null, 'Yük fonu', 'https://x/storage/v1/object/public/ads/templates/c.png', true, 1);
grant select on t_tpl to authenticated;
select public.admin_save_ad_package('d15', '15 gün', 15, 12, true);
select public.admin_set_ads_ordering_enabled(true);

select tests.login(:other);
create temp table t_o as select * from public.create_ad_order_v2((select id from t_tpl),
  '{"company":"ARIAL TEST","activity":"Yük","phone":"+994 50 000 00 00"}',
  '{"company":{"font":"Arial","size":1,"color":"#FFFFFF"},"activity":{"font":"Arial","size":0.8,"color":"#FFCC00"},"phone":{"font":"Arial","size":1,"color":"#FFFFFF"}}',
  null, 'dark', 15, null, 'profile', null, '{}', 'AZ', 'GE', 'sss');
grant select on t_o to authenticated;
select tests.check((select price = 12 and creative->'style'->'company'->>'font' = 'Arial' and route_from = 'AZ' and route_to = 'GE' from t_o),
  'F1 an ad with the Arial font (the app''s font) can be ordered');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}'::jsonb, '{"company":{"font":"Comic Sans"}}'::jsonb, null, 'dark', 15, null) $$,
  (select id from t_tpl))) like '%invalid_font%', 'F2 unknown fonts are still refused');
reset role;
select tests.summary('ADS ARIAL FONT (0033)');
rollback;

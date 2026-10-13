-- ADS — 0029: service ads. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
create temp table t_cargo as select * from public.admin_save_ad_template_v2(null, 'Yük fonu', 'https://x/storage/v1/object/public/ads/templates/c.png', true, 1);
create temp table t_svc as select * from public.admin_save_ad_template_v2(null, 'Servis fonu', 'https://x/storage/v1/object/public/ads/templates/s.png', true, 2);
grant select on t_cargo, t_svc to authenticated;
select public.admin_set_ad_template_audience((select id from t_svc), 'service');
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select public.admin_set_ads_ordering_enabled(true);
select tests.check((select audience = 'cargo' from public.ad_templates where id = (select id from t_cargo)), 'S1 existing / new templates are for loads by default');
select tests.check(tests.err(format($$ select public.admin_set_ad_template_audience(%L, 'everyone') $$, (select id from t_svc))) like '%invalid_audience%',
  'S2 audience must be cargo / service / all');

select tests.login(:other);
insert into public.service_providers (name, lat, lng, categories) values ('Utep Reklam', 40.44, 49.78, '{advertising}');
create temp table t_s as select id from public.service_providers where name = 'Utep Reklam';
grant select on t_s to authenticated;
select tests.check(tests.err($$ select public.admin_set_ad_template_audience((select id from t_svc), 'all') $$) like '%admin_only%',
  'S3 only admins set the audience');
select tests.check(tests.err(format($$ select public.create_service_ad_order(%L, %L, '{"company":"UTEP"}', '{}', null, 'dark', 5) $$,
  (select id from t_s), (select id from t_cargo))) like '%template_not_found%', 'S4 a service cannot use a load template');

create temp table t_o as select * from public.create_service_ad_order((select id from t_s), (select id from t_svc),
  jsonb_build_object('company', 'UTEP REKLAM', 'activity', 'TIR vinil dizayn', 'phone', '+994 51 551 91 49'),
  '{}', null, 'dark', 5, array['AZ','GE']);
grant select on t_o to authenticated;
select tests.check((select destination_type = 'service' and destination_url = (select id::text from t_s) and service_id = (select id from t_s)
                       and route_from is null and route_to is null and target_countries = array['AZ','GE'] and price = 20 from t_o),
  'S5 service ad: leads to the service page, countries only, normal price');

select tests.login(:owner1);
select tests.check(tests.err(format($$ select public.create_service_ad_order(%L, %L, '{"company":"HACK"}', '{}', null, 'dark', 5) $$,
  (select id from t_s), (select id from t_svc))) like '%service_not_found%', 'S6 nobody can advertise someone else''s service');

select tests.login(:other);
select public.submit_ad_receipt((select id from t_o), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_o) || '/r.jpg');
select tests.login(:admin);
select public.admin_review_ad_order((select id from t_o), true);
select tests.check((select destination_type = 'service' and destination_url = (select id::text from t_s) from public.ads where order_id = (select id from t_o)),
  'S7 the published ad keeps the service link');
select tests.check((select destination_type = 'service' and creative->'texts'->>'activity' = 'TIR vinil dizayn və çap'
                      from public.admin_update_ad_order_v2((select id from t_o), (select id from t_svc),
                        '{"company":"UTEP REKLAM","activity":"TIR vinil dizayn və çap"}', '{}', null, 'dark',
                        'profile', null, array['AZ'], null, null)),
  'S8 admin edit keeps a service ad pointing to the service');
reset role;
select tests.summary('SERVICE ADS (0029)');
rollback;

-- ADS — 0032: own picture as a service-ad background. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
create temp table t_pub as select * from public.admin_save_ad_template_v2(null, 'Servis fonu', 'https://x/storage/v1/object/public/ads/templates/s.png', true, 1);
grant select on t_pub to authenticated;
select public.admin_set_ad_template_audience((select id from t_pub), 'service');
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select public.admin_set_ads_ordering_enabled(true);

select tests.login(:other);
insert into public.service_providers (name, lat, lng, categories) values ('Own Bg Servis', 40.44, 49.78, '{advertising}');
create temp table t_s as select id from public.service_providers where name = 'Own Bg Servis';
grant select on t_s to authenticated;

select tests.check(tests.err($$ select public.create_own_ad_background('https://evil.example/x.png') $$) like '%invalid_image%',
  'B1 picture must be in our ads bucket');
select tests.check(tests.err($$ select public.create_own_ad_background('https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000011/x.png') $$) like '%invalid_image%',
  'B2 …and in my own folder, not someone else''s');
create temp table t_mine as select * from public.create_own_ad_background('https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000021/1.png');
grant select on t_mine to authenticated;
select tests.check((select owner_id = :other and is_active and layout = 'standard_v2' and audience = 'service' from t_mine),
  'B3 own background = private, active, standard 1200x400 service template');
select tests.check((select count(*) = 2 from public.ad_templates where id in ((select id from t_pub), (select id from t_mine))),
  'B4 I see the admin template and my own one');

create temp table t_o as select * from public.create_service_ad_order((select id from t_s), (select id from t_mine),
  jsonb_build_object('company', 'OWN BG'), '{}', null, 'dark', 5, array['AZ']);
grant select on t_o to authenticated;
select tests.check((select status = 'pending_payment' and price = 20 and template_id = (select id from t_mine)
                      and creative->>'image_url' like '%/ads/requests/a0000000-0000-4000-8000-000000000021/1.png' from t_o),
  'B5 ordering with my own picture works like a normal service ad (price, review)');

select tests.login(:owner1);
select tests.check((select count(*) = 0 from public.ad_templates where id = (select id from t_mine)),
  'B6 other users cannot see my private background');
insert into public.service_providers (name, lat, lng, categories)
select 'Owner1 Servis', 40.4, 49.8, '{advertising}'
where not exists (select 1 from public.service_providers where owner_id = :owner1);
select tests.check(tests.err(format($$ select public.create_service_ad_order(%L, %L, '{"company":"X"}', '{}', null, 'dark', 5) $$,
  (select id from public.service_providers where owner_id = :owner1 limit 1), (select id from t_mine))) like '%template_not_found%',
  'B7 nobody else can order with my private background');

select tests.login(:admin);
select tests.check((select count(*) = 1 from public.ad_templates where id = (select id from t_mine)), 'B8 admins can still see it (order review)');
reset role;
select tests.summary('OWN AD BACKGROUND (0032)');
rollback;

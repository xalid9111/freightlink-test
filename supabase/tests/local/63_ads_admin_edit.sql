-- =====================================================================
-- ADS — 0024: admin edit, text cleaning, country routes, no start date.
-- Everything is rolled back at the end.
-- =====================================================================
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
create temp table t_tpl as select * from public.admin_save_ad_template_v2(null, 'Fon A',
  'https://x/storage/v1/object/public/ads/templates/a.png', true, 1);
create temp table t_tplb as select * from public.admin_save_ad_template_v2(null, 'Fon B',
  'https://x/storage/v1/object/public/ads/templates/b.png', true, 2);
grant select on t_tpl, t_tplb to authenticated;
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select public.admin_set_ads_ordering_enabled(true);
select public.admin_set_home_ads_enabled(true);

-- 1) phone pasted on iPhone (hidden U+202A / U+202C, non-breaking space)
select tests.login(:other);
create temp table t_o as select * from public.create_ad_order_v2((select id from t_tpl),
  jsonb_build_object('company', E'DELTA-GEO‎', 'activity', 'Logistics', 'phone', E'‪+994 515519149‬'),
  '{}', null, 'dark', 5, null, 'profile', null, array['AZ','GE'], 'az', 'GE', null);
grant select on t_o to authenticated;
select tests.check((select creative->'texts'->>'phone' = '+994 515519149' and creative->'texts'->>'company' = 'DELTA-GEO' from t_o),
  'E1 hidden characters removed, pasted phone accepted');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X","phone":"call me"}', '{}', null, 'dark', 5, null) $$,
  (select id from t_tpl))) like '%invalid_phone%', 'E2 a real non-number is still rejected');

-- 2) no start date → today (starts on approval)
select tests.check((select starts_on = (now() at time zone 'Asia/Baku')::date from t_o), 'E3 no date from the customer → today');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{}', null, 'dark', 5, current_date - 3) $$,
  (select id from t_tpl))) like '%invalid_start_date%', 'E4 an old app sending a past date is still checked');

-- 3) route = countries only
select tests.check((select route_from = 'AZ' and route_to = 'GE' from t_o), 'E5 route stored as country codes');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{}', null, 'dark', 5, null, 'profile', null, '{}', 'baki', 'gurcustan') $$,
  (select id from t_tpl))) like '%invalid_route%', 'E6 free text like "baki" is refused');

-- 4) admin edit — only admins
select tests.check(tests.err(format($$ select public.admin_update_ad_order_v2(%L, %L, '{"company":"HACK"}', '{}', null, 'dark', 'profile', null, '{}', null, null) $$,
  (select id from t_o), (select id from t_tpl))) like '%admin_only%', 'E7 customer cannot use the admin editor');

-- before payment: admin edits the order, status untouched
select tests.login(:admin);
select tests.check((select creative->'texts'->>'activity' = 'Logistics & Customs' and status = 'pending_payment'
                       and route_from is null and route_to is null and target_countries = array['AZ']
                      from public.admin_update_ad_order_v2((select id from t_o), (select id from t_tpl),
                        '{"company":"DELTA-GEO","activity":"Logistics & Customs","phone":"+994 51 551 91 49"}', '{}', null, 'dark',
                        'profile', null, array['AZ'], '', null)),
  'E8 admin edits a pending order (texts, countries, route cleared), status unchanged');

-- approve → ad; admin edits the published ad
select tests.login(:other);
select public.submit_ad_receipt((select id from t_o), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_o) || '/r.jpg');
select tests.login(:admin);
select public.admin_review_ad_order((select id from t_o), true);
select tests.check((select route_from is null and creative->'texts'->>'activity' = 'Logistics & Customs' from public.ads where order_id = (select id from t_o)),
  'E9 the approved ad carries the admin''s corrections');

select tests.check((select creative->>'image_url' like '%b.png' and creative->'style'->'company'->>'color' = '#FF6B33'
                       and creative->>'logo_url' like '%/requests/a0000000-0000-4000-8000-000000000001/%'
                       and destination_type = 'external' and route_from = 'AZ' and route_to = 'TR'
                      from public.admin_update_ad_order_v2((select id from t_o), (select id from t_tplb),
                        '{"company":"DELTA-GEO","activity":"Logistics","phone":"+994 51 551 91 49"}',
                        '{"company":{"font":"Inter","size":0.9,"color":"#ff6b33"}}',
                        'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000001/logo.png', 'light',
                        'external', 'https://delta-geo.az', array['AZ','TR'], 'az', 'tr',
                        now() - interval '1 hour', now() + interval '9 days')),
  'E10 admin changes background, style, logo (own upload), link, route');
select tests.check((select creative->>'image_url' like '%b.png' and route_to = 'TR' and destination_url = 'https://delta-geo.az'
                       and ends_at::date = (now() + interval '9 days')::date
                      from public.ads where order_id = (select id from t_o)),
  'E11 the published ad is updated too (banner, route, link, dates)');
select tests.check((select ad_ends_at::date = (now() + interval '9 days')::date and status = 'active' and payment_status = 'paid'
                      from public.ad_orders where id = (select id from t_o)),
  'E12 order shows the new dates; status / payment untouched');
select tests.login(:other);
select tests.check(public.home_feed_ads()->0->'creative'->'style'->'company'->>'color' = '#FF6B33', 'E13 the feed shows the edited banner');

select tests.login(:admin);
select tests.check(tests.err(format($$ select public.admin_update_ad_order_v2(%L, %L, '{"company":"X"}', '{}',
    'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000011/l.png', 'dark', 'profile', null, '{}', null, null) $$,
  (select id from t_o), (select id from t_tpl))) like '%invalid_logo%', 'E14 logo only from the advertiser''s or the admin''s folder');
select tests.check(tests.err(format($$ select public.admin_update_ad_order_v2(%L, %L, '{"company":"X"}', '{}', null, 'dark', 'profile', null, '{}', 'Bakı', null) $$,
  (select id from t_o), (select id from t_tpl))) like '%invalid_route%', 'E15 admin route also countries only');
select tests.check(tests.err(format($$ select public.admin_update_ad_order_v2(%L, %L, '{"company":"X"}', '{}', null, 'dark', 'profile', null, '{}', null, null, now(), now() - interval '1 day') $$,
  (select id from t_o), (select id from t_tpl))) like '%invalid_dates%', 'E16 end must be after start');

-- template switched off / deleted → admin can still edit, background kept
select public.admin_delete_ad_template((select id from t_tplb));
select tests.check((select creative->>'image_url' like '%b.png' and creative->'texts'->>'company' = 'DELTA-GEO 2'
                      from public.admin_update_ad_order_v2((select id from t_o), (select id from t_tplb),
                        '{"company":"DELTA-GEO 2"}', '{}', null, 'dark', 'profile', null, '{}', null, null)),
  'E17 deleted template → current background kept');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'ad_order.admin_edit' and entity_id = (select id::text from t_o)),
  'E18 every admin edit is in the audit log');

-- customer edit path also cleans text
select tests.login(:other);
create temp table t_o3 as select * from public.create_ad_order_v2((select id from t_tpl), '{"company":"Üç"}', '{}', null, 'dark', 5, null);
grant select on t_o3 to authenticated;
select tests.check((select creative->'texts'->>'phone' = '+994 55 000 00 00'
                      from public.update_my_ad_order_v2((select id from t_o3), (select id from t_tpl),
                        jsonb_build_object('company', 'Üç', 'phone', E'‪+994 55 000 00 00‬'), '{}', null, 'dark')),
  'E19 customer edit cleans the phone as well');

reset role;
select tests.summary('ADS ADMIN EDIT (0024)');
rollback;

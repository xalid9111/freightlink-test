-- ADS — 0026: admin order (priority), no-repeat setting. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
create temp table t_tpl as select * from public.admin_save_ad_template_v2(null, 'Fon', 'https://x/storage/v1/object/public/ads/templates/a.png', true, 1);
grant select on t_tpl to authenticated;
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select public.admin_set_ads_ordering_enabled(true);
select public.admin_set_home_ads_enabled(true);

select tests.login(:other);
create temp table t_a as select * from public.create_ad_order_v2((select id from t_tpl), '{"company":"BİRİNCİ"}', '{}', null, 'dark', 5, null);
create temp table t_b as select * from public.create_ad_order_v2((select id from t_tpl), '{"company":"İKİNCİ"}', '{}', null, 'dark', 5, null);
grant select on t_a, t_b to authenticated;
select public.submit_ad_receipt((select id from t_a), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_a) || '/r.jpg');
select public.submit_ad_receipt((select id from t_b), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_b) || '/r.jpg');
select tests.login(:admin);
select public.admin_review_ad_order((select id from t_a), true);
select public.admin_review_ad_order((select id from t_b), true);

select tests.login(:other);
select tests.check(public.home_feed_ads()->0->'creative'->'texts'->>'company' = 'BİRİNCİ', 'O1 default order = oldest first');
select tests.check((public.ads_feed_layout()->>'repeat')::boolean = false, 'O2 default: the same ad is never repeated');
select tests.check(tests.err(format($$ select public.admin_set_ads_order(array[%L]::uuid[]) $$,
  (select id from public.ads where order_id = (select id from t_b)))) like '%admin_only%', 'O3 only admins change the order');

select tests.login(:admin);
select public.admin_set_ads_order(array[(select id from public.ads where order_id = (select id from t_b)),
                                        (select id from public.ads where order_id = (select id from t_a))]);
select tests.login(:other);
select tests.check(public.home_feed_ads()->0->'creative'->'texts'->>'company' = 'İKİNCİ'
                   and public.home_feed_ads()->1->'creative'->'texts'->>'company' = 'BİRİNCİ', 'O4 admin puts the second ad first');

select tests.login(:admin);
select tests.check(tests.err(format($$ select public.admin_set_ads_order(array[%L, %L]::uuid[]) $$,
  (select id from public.ads where order_id = (select id from t_a)), (select id from public.ads where order_id = (select id from t_a))))
  like '%invalid_order%', 'O5 the same ad twice in the order is refused');
select tests.check(public.admin_set_ads_feed_layout(4, 5, 15, true) @> '{"first_after":4,"every":5,"rotate_minutes":15,"repeat":true}'::jsonb,
  'O6 admin saves position, minutes and repeat');
select tests.check((public.admin_set_ads_feed_layout(4, 5, 20)->>'repeat')::boolean = true, 'O7 the old 3-value save keeps "repeat"');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'ads.reorder'), 'O8 order change is in the audit log');

reset role;
select tests.summary('ADS ORDER / NO REPEAT (0026)');
rollback;

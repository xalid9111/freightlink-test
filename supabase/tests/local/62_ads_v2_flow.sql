-- =====================================================================
-- ADS — STANDARD LAYOUT (0023): the whole flow on 0001–0023.
-- template (admin) → order (customer, texts / fonts / sizes / colours /
-- logo) → edit → receipt → edit after receipt → approve / reject →
-- scheduled → live → ended; both switches; old-format ads.
-- Everything is rolled back at the end.
-- =====================================================================
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''

begin;
-- a legacy (old-format) ad that was live before 0023 is now switched off
select tests.check(not exists (select 1 from public.ads where is_active and coalesce(creative->>'version','') <> '2'),
  'V1 no old-format ad is active after 0023');

set role authenticated;
select tests.login(:admin);
create temp table t_tpl as select * from public.admin_save_ad_template_v2(null, 'Gün batımı',
  'https://x/storage/v1/object/public/ads/templates/sunset.png', true, 1);
grant select on t_tpl to authenticated;
select tests.check((select layout = 'standard_v2' and is_active from t_tpl), 'V2 admin adds a standard template');
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select public.admin_save_ad_package('d15', '15 gün', 15, 50, true);

-- ordering switch OFF by default
select tests.login(:other);
select tests.check(public.ads_ordering_enabled() = false, 'V3 "Reklam ver" switch is OFF by default');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"DELTA-GEO"}', '{}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%ordering_disabled%', 'V4 no orders while "Reklam ver" is OFF');
select tests.check(tests.err($$ select public.admin_set_ads_ordering_enabled(true) $$) like '%admin_only%',
  'V5 only admins switch ordering on');
select tests.login(:admin);
select public.admin_set_ads_ordering_enabled(true);
select tests.check(public.home_ads_enabled() = false, 'V6 the two switches are independent (feed still OFF)');

select tests.login(:other);
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{"company":{"font":"Comic Sans"}}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%invalid_font%', 'V7 only the offered fonts');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{"company":{"size":1.4}}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%invalid_size%', 'V8 size cannot exceed the fixed box');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{"phone":{"color":"red"}}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%invalid_color%', 'V9 colour must be #RRGGBB');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X","phone":"call me"}', '{}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%invalid_phone%', 'V10 phone must be a number');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":""}', '{}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%text_required%', 'V11 company name required');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{}', 'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000011/l.png', 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%invalid_logo%', 'V12 logo only from own folder');
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"X"}', '{}', 'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000021/l.svg', 'dark', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%invalid_logo%', 'V13 logo must be png / jpg / webp');
select tests.check(tests.err(format($$ select public.create_ad_order_from_template(%L, '{"t":"A"}', '#FFFFFF', 5, current_date + 1) $$,
  (select id from t_tpl))) like '%use_new_editor%', 'V14 old free-layout ordering retired');

create temp table t_o as select * from public.create_ad_order_v2((select id from t_tpl),
  '{"company":"DELTA-GEO","activity":"Logistics","phone":"+994 55 959 18 81"}',
  '{"company":{"font":"Montserrat","size":1,"color":"#ffffff"},"activity":{"font":"Inter","size":0.8,"color":"#FFCC00"},"phone":{"font":"Roboto Condensed","size":0.9,"color":"#E6F0EA"}}',
  'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000021/logo.png', 'none',
  15, (now() at time zone 'Asia/Baku')::date, 'external', 'https://delta-geo.az', array['AZ','GE'], null, null, null);
grant select on t_o to authenticated;
select tests.check((select status = 'pending_payment' and price = 50 and creative->>'version' = '2'
                       and creative->'texts'->>'company' = 'DELTA-GEO' and creative->'style'->'company'->>'color' = '#FFFFFF'
                       and creative->'style'->'activity'->>'size' = '0.80' and creative->>'logo_bg' = 'none'
                       and creative->>'image_url' like '%sunset.png' and not (creative ? 'fields') from t_o),
  'V15 order: standard creative (texts, styles, logo) without positions, price from admin');

-- edit before receipt: saved, no flag
select tests.check((select creative->'texts'->>'activity' = 'Logistics & Customs' and edited_after_receipt_at is null and status = 'pending_payment'
                      from public.update_my_ad_order_v2((select id from t_o), (select id from t_tpl),
                        '{"company":"DELTA-GEO","activity":"Logistics & Customs","phone":"+994 55 959 18 81"}', '{}', null, 'dark')),
  'V16 customer edits own order before paying');
select tests.login(:owner1);
select tests.check(tests.err(format($$ select public.update_my_ad_order_v2(%L, %L, '{"company":"HACK"}', '{}', null, 'dark') $$,
  (select id from t_o), (select id from t_tpl))) like '%not_found%', 'V17 nobody else can edit the order');

select tests.login(:other);
select public.submit_ad_receipt((select id from t_o), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_o) || '/r.jpg');
select tests.check((select status = 'awaiting_approval' and edited_after_receipt_at is not null
                      from public.update_my_ad_order_v2((select id from t_o), (select id from t_tpl),
                        '{"company":"DELTA-GEO LLC","activity":"Logistics","phone":"+994 55 959 18 81"}', '{}', null, 'dark')),
  'V18 edit after the receipt → flagged, back to admin review');

select tests.login(:admin);
select tests.check((select status = 'active' and payment_status = 'paid' and ad_ends_at = ad_starts_at + interval '15 days'
                      from public.admin_review_ad_order((select id from t_o), true)), 'V19 admin approves after checking the bank');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.update_my_ad_order_v2(%L, %L, '{"company":"CHANGED"}', '{}', null, 'dark') $$,
  (select id from t_o), (select id from t_tpl))) like '%order_locked%', 'V20 approved ad cannot be changed by the customer');

-- feed switch
select tests.check(public.home_feed_ads() = '[]'::jsonb, 'V21 feed switch OFF → no ads');
select tests.login(:admin);
select public.admin_set_home_ads_enabled(true);
select tests.login(:other);
select tests.check(jsonb_array_length(public.home_feed_ads()) = 1
                   and public.home_feed_ads()->0->'creative'->'texts'->>'company' = 'DELTA-GEO LLC',
  'V22 feed switch ON → the approved, started ad with its latest content');

-- old-format ad (paid) never goes live again
reset role;
insert into public.ad_orders (id, advertiser_id, package_name, days, price, status, payment_status)
values ('f0000000-0000-4000-8000-0000000000f9', 'a0000000-0000-4000-8000-000000000011', 'x', 5, 1, 'active', 'paid');
insert into public.ads (id, order_id, advertiser_id, image_url, starts_at, ends_at, is_active)
values ('ad000000-0000-4000-8000-0000000000a9', 'f0000000-0000-4000-8000-0000000000f9', 'a0000000-0000-4000-8000-000000000011', 'u',
        now() - interval '1 hour', now() + interval '1 day', true);
set role authenticated;
select tests.check(jsonb_array_length(public.home_feed_ads()) = 1, 'V23 old 1350×300 ad not published even if switched on');
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_set_ad_active('ad000000-0000-4000-8000-0000000000a9', true) $$) like '%old_format%',
  'V24 admin cannot re-activate an old-format ad');

-- admin: link + dates
select tests.check(tests.err(format($$ select public.admin_update_ad_link_dates((select id from public.ads where order_id = %L), 'external', 'http://x.az', now(), now() + interval '1 day') $$,
  (select id from t_o))) like '%invalid_external_url%', 'V25 admin link must be https');
select tests.check((select destination_url = 'https://delta-geo.az/kampaniya' and ends_at > starts_at
                      from public.admin_update_ad_link_dates((select id from public.ads where order_id = (select id from t_o)),
                        'external', 'https://delta-geo.az/kampaniya', now() - interval '1 hour', now() + interval '10 days')),
  'V26 admin changes link and dates');
select tests.check((select ad_ends_at::date = (now() + interval '10 days')::date from public.ad_orders where id = (select id from t_o)),
  'V27 order shows the new dates to the customer');

-- scheduled / ended
reset role;
update public.ads set starts_at = now() + interval '2 days', ends_at = now() + interval '7 days' where order_id = (select id from t_o);
set role authenticated;
select tests.login(:other);
select tests.check(jsonb_array_length(public.home_feed_ads()) = 0, 'V28 scheduled ad not shown before its start');
reset role;
update public.ads set starts_at = now() - interval '6 days', ends_at = now() - interval '1 minute' where order_id = (select id from t_o);
set role authenticated;
select tests.check(jsonb_array_length(public.home_feed_ads()) = 0, 'V29 ad stops by itself after its end');

-- pause / resume by admin
reset role;
update public.ads set starts_at = now() - interval '1 hour', ends_at = now() + interval '5 days' where order_id = (select id from t_o);
set role authenticated;
select tests.login(:admin);
select public.admin_set_ad_active((select id from public.ads where order_id = (select id from t_o)), false);
select tests.login(:other);
select tests.check(jsonb_array_length(public.home_feed_ads()) = 0, 'V30 admin pauses an ad');
select tests.login(:admin);
select public.admin_set_ad_active((select id from public.ads where order_id = (select id from t_o)), true);
select tests.login(:other);
select tests.check(jsonb_array_length(public.home_feed_ads()) = 1, 'V31 admin resumes it');

-- switches off: data untouched
select tests.login(:admin);
select public.admin_set_home_ads_enabled(false);
select public.admin_set_ads_ordering_enabled(false);
select tests.check((select payment_status = 'paid' and status = 'active' from public.ad_orders where id = (select id from t_o))
                   and exists (select 1 from public.ads where order_id = (select id from t_o) and is_active),
  'V32 switching both OFF keeps orders, payments and ads');

-- template delete keeps the ordered banner
select public.admin_delete_ad_template((select id from t_tpl));
select tests.check((select creative->>'image_url' like '%sunset.png' from public.ad_orders where id = (select id from t_o)),
  'V33 deleting a template never changes an ordered banner');

-- reject path + blocked
select public.admin_set_ads_ordering_enabled(true);
create temp table t_tpl2 as select * from public.admin_save_ad_template_v2(null, 'Gecə', 'https://x/storage/v1/object/public/ads/templates/night.png', true, 2);
grant select on t_tpl2 to authenticated;
select tests.login(:other);
create temp table t_o2 as select * from public.create_ad_order_v2((select id from t_tpl2), '{"company":"İkinci"}', '{}', null, 'light', 5,
  (now() at time zone 'Asia/Baku')::date + 2);
select public.submit_ad_receipt((select id from t_o2), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_o2) || '/r.jpg');
select tests.login(:admin);
select tests.check((select status = 'rejected' and admin_note = 'Pul daxil olmayıb'
                      from public.admin_review_ad_order((select id from t_o2), false, 'Pul daxil olmayıb')),
  'V34 reject with reason');
select tests.login(:blocked);
select tests.check(tests.err(format($$ select public.create_ad_order_v2(%L, '{"company":"B"}', '{}', null, 'dark', 5, current_date + 1) $$,
  (select id from t_tpl2))) like '%account_blocked%', 'V35 blocked user cannot order');
select tests.login(null);
reset role;
set role anon;
select tests.check(tests.err($$ select public.home_feed_ads() $$) is not null, 'V36 not callable without login');

reset role;
select tests.summary('ADS STANDARD LAYOUT (0023)');
rollback;

-- =====================================================================
-- ADS FLOW (0021): template → order → receipt → admin approve / reject →
-- scheduled → live → ended, plus the home-feed switch. Runs on 0001–0021.
-- Everything is rolled back at the end.
-- =====================================================================
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''
\set tpl     '''e0000000-0000-4000-8000-0000000000a1'''

begin;

-- ---- admin: prices + template ---------------------------------------------
set role authenticated;
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_save_ad_template(null, '{"name":"x","image_url":"u","fields":[],"colors":["#FFFFFF"]}') $$) like '%invalid_fields%',
  'T1 template without text fields is refused');
select tests.check(tests.err($$ select public.admin_save_ad_template(null, '{"name":"x","image_url":"u","fields":[{"key":"t","label":"Başlıq","x":0.1,"y":0.2,"w":0.5,"size":60,"max":30}],"colors":["red"]}') $$) like '%invalid_colors%',
  'T2 colour must be #RRGGBB');
reset role;
insert into public.ad_templates (id, name, image_url, fields, colors, is_active)
values (:tpl, 'Mavi', 'https://x/storage/v1/object/public/ads/templates/a.png',
        '[{"key":"title","label":"Başlıq","default":"","x":0.05,"y":0.2,"w":0.6,"size":64,"max":30,"align":"left","bold":true},
          {"key":"phone","label":"Telefon","default":"","x":0.05,"y":0.6,"w":0.6,"size":40,"max":20,"align":"left","bold":false}]',
        array['#FFFFFF','#FFCC00'], false);
set role authenticated;
select tests.check((select (public.admin_save_ad_template(:tpl, jsonb_build_object(
          'name','Mavi şablon','image_url','https://x/storage/v1/object/public/ads/templates/a.png',
          'fields', (select fields from public.ad_templates where id = :tpl), 'colors', '["#ffffff","#ffcc00"]'::jsonb))).colors
        = array['#FFFFFF','#FFCC00']), 'T3 admin edits a template (colours normalised)');
select public.admin_set_ad_template_active(:tpl, true);
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select public.admin_save_ad_package('d15', '15 gün', 15, 50, true);

-- ---- customer: create order ------------------------------------------------
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_save_ad_template(null, '{}') $$) like '%admin_only%',
  'T4 customer cannot edit templates');
select tests.check((select count(*) from public.ad_templates) = 1, 'T5 customer sees the active template');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"Yük daşıma"}', '#000000', 5, current_date + 1) $$) like '%invalid_color%',
  'T6 colour outside the template palette refused');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"Yük daşıma"}', '#FFFFFF', 7, current_date + 1) $$) like '%invalid_duration%',
  'T7 only 5 / 15 / 30 days');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"Yük daşıma"}', '#FFFFFF', 30, current_date + 1) $$) like '%package_not_found%',
  'T8 30 days refused while the admin has not priced it');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"Bu mətn otuz simvoldan çox uzundur, çox"}', '#FFFFFF', 5, current_date + 1) $$) like '%text_too_long%',
  'T9 text longer than the field limit refused');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"  "}', '#FFFFFF', 5, current_date + 1) $$) like '%text_required%',
  'T10 empty banner refused');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"A"}', '#FFFFFF', 5, current_date - 3) $$) like '%invalid_start_date%',
  'T11 start date in the past refused');
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"A"}', '#FFFFFF', 5, current_date + 1, 'external', 'http://x.az') $$) like '%invalid_external_url%',
  'T12 external link must be https');

create temp table t_o as
select * from public.create_ad_order_from_template(:tpl, '{"title":"Sürətli daşıma","phone":"+994501234567","hack":"x"}',
  '#ffcc00', 15, (now() at time zone 'Asia/Baku')::date, 'external', 'https://example.az', array['AZ','GE'], 'Baku', 'Tbilisi');
grant select on t_o to authenticated;
select tests.check((select status = 'pending_payment' and payment_status = 'unpaid' and price = 50 and days = 15
                       and order_no >= 1001 and creative->>'color' = '#FFCC00'
                       and creative->'texts' ? 'title' and not (creative->'texts' ? 'hack')
                       and creative->>'image_url' like '%templates/a.png' from t_o),
  'T13 order: price from admin package, order number, snapshot without foreign keys');
select tests.check(tests.err(format($$ select public.submit_ad_receipt(%L, 'a0000000-0000-4000-8000-000000000011/x/r.jpg') $$, (select id from t_o))) like '%invalid_receipt%',
  'T14 receipt path must be in the customer''s own folder');

-- not paid yet: admin cannot approve
select tests.login(:admin);
select tests.check(tests.err(format($$ select public.admin_review_ad_order(%L, true) $$, (select id from t_o))) like '%invalid_order_state%',
  'T15 no approval without a receipt');

select tests.login(:other);
select tests.check((select status = 'awaiting_approval' and payment_status = 'submitted' and receipt_path is not null
                      from public.submit_ad_receipt((select id from t_o),
                        'a0000000-0000-4000-8000-000000000021/' || (select id from t_o) || '/r1.jpg')),
  'T16 receipt → "Yoxlanılır" (submitted, NOT paid)');
select tests.check(not exists (select 1 from public.ads where order_id = (select id from t_o)),
  'T17 receipt alone publishes nothing');

-- ---- admin: approve ---------------------------------------------------------
select tests.login(:admin);
select tests.check(tests.err(format($$ select public.admin_review_ad_order(%L, false, '  ') $$, (select id from t_o))) like '%reason_required%',
  'T18 reject needs a reason');
select tests.check((select payment_status = 'paid' and status = 'active' and ad_starts_at is not null
                       and ad_ends_at = ad_starts_at + interval '15 days'
                      from public.admin_review_ad_order((select id from t_o), true, 'ok')),
  'T19 approve: paid, ad created, ends after exactly 15 days');
select tests.check((select a.is_active and a.creative->>'color' = '#FFCC00' and a.destination_url = 'https://example.az'
                       and a.target_countries = array['AZ','GE']
                      from public.ads a where a.order_id = (select id from t_o)),
  'T20 ad carries the banner, link and targeting');

-- ---- home switch -------------------------------------------------------------
select tests.login(:other);
select tests.check(public.home_ads_enabled() = false and public.home_feed_ads() = '[]'::jsonb,
  'T21 switch OFF by default → no ads in the feed');
select tests.check(tests.err($$ select public.admin_set_home_ads_enabled(true) $$) like '%admin_only%',
  'T22 only admins switch ads on');
select tests.login(:admin);
select public.admin_set_home_ads_enabled(true);
select tests.login(:other);
select tests.check(jsonb_array_length(public.home_feed_ads()) = 1,
  'T23 switch ON → the approved, started ad is shown');

-- not-yet-started (scheduled) ad and an unpaid legacy ad are not shown
reset role;
update public.ads set starts_at = now() + interval '2 days', ends_at = now() + interval '17 days' where order_id = (select id from t_o);
set role authenticated;
select tests.check(jsonb_array_length(public.home_feed_ads()) = 0, 'T24 scheduled ad not shown before its start');
reset role;
update public.ads set starts_at = now() - interval '16 days', ends_at = now() - interval '1 day' where order_id = (select id from t_o);
set role authenticated;
select tests.check(jsonb_array_length(public.home_feed_ads()) = 0, 'T25 ad stops by itself after its end date');
reset role;
update public.ads set starts_at = now() - interval '1 day', ends_at = now() + interval '14 days' where order_id = (select id from t_o);
insert into public.ad_orders (id, advertiser_id, package_name, days, price, status, payment_status)
values ('f0000000-0000-4000-8000-0000000000f1', 'a0000000-0000-4000-8000-000000000011', 'x', 5, 1, 'approved', 'submitted');
insert into public.ads (order_id, advertiser_id, image_url, starts_at, ends_at, is_active)
values ('f0000000-0000-4000-8000-0000000000f1', 'a0000000-0000-4000-8000-000000000011', 'u', now() - interval '1 hour', now() + interval '1 day', true);
set role authenticated;
select tests.check(jsonb_array_length(public.home_feed_ads()) = 1, 'T26 ad of an unpaid order never shown');

select tests.login(:admin);
select public.admin_set_home_ads_enabled(false);
select tests.check((select payment_status = 'paid' and status = 'active' from public.ad_orders where id = (select id from t_o))
                   and exists (select 1 from public.ads where order_id = (select id from t_o) and is_active),
  'T27 switching OFF keeps orders, payments and ads unchanged');
select tests.login(:other);
select tests.check(public.home_feed_ads() = '[]'::jsonb, 'T28 switch OFF hides every ad again');

-- ---- reject path ----------------------------------------------------------------
create temp table t_o2 as
select * from public.create_ad_order_from_template(:tpl, '{"title":"İkinci"}', '#FFFFFF', 5, (now() at time zone 'Asia/Baku')::date + 3);
select public.submit_ad_receipt((select id from t_o2), 'a0000000-0000-4000-8000-000000000021/' || (select id from t_o2) || '/r.jpg');
select tests.login(:admin);
select tests.check((select status = 'rejected' and admin_note = 'Pul daxil olmayıb' and payment_status <> 'paid'
                      from public.admin_review_ad_order((select id from t_o2), false, 'Pul daxil olmayıb')),
  'T29 reject with reason (customer sees it), not paid');
select tests.check(not exists (select 1 from public.ads where order_id = (select id from t_o2)), 'T30 rejected order has no ad');

-- ---- other users / blocked --------------------------------------------------------
select tests.login(:owner1);
select tests.check(not exists (select 1 from public.ad_orders where advertiser_id = :other), 'T31 nobody else sees the order');
select tests.check(tests.err(format($$ select public.submit_ad_receipt(%L, 'a0000000-0000-4000-8000-000000000011/' || %L || '/r.jpg') $$, (select id from t_o2), (select id from t_o2))) like '%order_not_payable%',
  'T32 receipt cannot be attached to someone else''s order');
select tests.login(:blocked);
select tests.check(tests.err($$ select public.create_ad_order_from_template('e0000000-0000-4000-8000-0000000000a1', '{"title":"A"}', '#FFFFFF', 5, current_date + 1) $$) like '%account_blocked%',
  'T33 blocked user cannot order');

-- ---- template off ---------------------------------------------------------------------
select tests.login(:admin);
select public.admin_set_ad_template_active(:tpl, false);
select tests.login(:other);
select tests.check((select count(*) from public.ad_templates) = 0
                   and exists (select 1 from public.ad_orders where id = (select id from t_o) and creative is not null),
  'T34 deactivated template hidden from customers; existing orders keep their banner');

reset role;
select tests.summary('ADS FLOW (0021)');
rollback;

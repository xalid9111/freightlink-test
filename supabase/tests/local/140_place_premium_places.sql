-- Premium places for Parklar · Servislər · Mağazalar; no advertising from /
-- in Yüklər — 0102. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set svcown  '''a0000000-0000-4000-8000-000000000011'''
\set shopown '''a0000000-0000-4000-8000-000000000012'''
\set parkown '''a0000000-0000-4000-8000-000000000013'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set svc     '''5e000000-0000-4000-8000-000000000001'''
\set shop    '''5e000000-0000-4000-8000-000000000002'''
\set c1      '''c1020000-0000-4000-8000-000000000001'''
\set m1      '''aa102000-0000-4000-8000-000000000001'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
create temp table o (k text primary key, id uuid, amount numeric, places text[]) on commit drop;
grant all on ids, o to authenticated, service_role;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
-- Prices told apart: 5 days of Premium = 20 (Servis) and 30 (TIRPark); 30 days only for Servis.
update public.place_promo_plans set price = 20, is_active = true where target = 'service' and kind = 'premium' and qty = 5;
update public.place_promo_plans set price = 30, is_active = true where target = 'tirpark' and kind = 'premium' and qty = 5;
update public.place_promo_plans set is_active = false where target = 'tirpark' and kind = 'premium' and qty = 30;
-- owner2's garage becomes a shop (spare_parts + shop_* only), approved, on the map.
update public.service_providers set categories = array['spare_parts', 'shop_new'], lat = 40.41, lng = 49.86, name = 'Hissə Mağazası' where id = :shop;
update public.service_providers set status = 'approved', is_active = true where id in (:svc, :shop);
update public.service_providers set lat = 40.40, lng = 49.85 where id = :svc;

-- A park with an approved manager (as 131).
set role authenticated;
select tests.login(:parkown);
insert into ids values ('r', public.tir_park_owner_apply('Premium Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:parkown);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.42, 49.84, null, 10, 3, '+994501112233'));
reset role;
select tests.check(public._place_home('service', :svc) = 'services' and public._place_home('service', :shop) = 'shops'
                   and public._place_home('tirpark', (select id from ids where k='p')) = 'parks', 'H1 own sections: service → Servislər, shop → Mağazalar, park → Parklar');

-- ---- orders and prices ----------------------------------------------------------
set role authenticated;
select tests.login(:svcown);
insert into o select 's-own', id, amount, places from public.place_promo_order_create('service', :svc, 'premium', 5, array['services']);
insert into o select 's-all', id, amount, places from public.place_promo_order_create('service', :svc, 'premium', 5, array['shops', 'parks', 'services']);
select tests.login(:shopown);
insert into o select 'sh-parks', id, amount, places from public.place_promo_order_create('service', :shop, 'premium', 5, array['parks']);
select tests.login(:parkown);
insert into o select 'p-svc-shop', id, amount, places from public.place_promo_order_create('tirpark', (select id from ids where k='p'), 'premium', 5, array['services', 'shops']);
select tests.check((select amount = 20 and places = array['services'] from o where k = 's-own'), 'Q1 own section only: its own Premium price');
select tests.check((select amount = 70 and places = array['parks', 'services', 'shops'] from o where k = 's-all'), 'Q2 all three: 30 + 20 + 20 (each section''s price), places in a fixed order');
select tests.check((select amount = 30 from o where k = 'sh-parks'), 'Q3 a shop shown on Parklar only: the Parklar price');
select tests.check((select amount = 40 from o where k = 'p-svc-shop'), 'Q4 a park on Servislər + Mağazalar: 20 + 20');
select tests.login(:svcown);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 5, '{}'::text[]) $$, :svc)) like '%invalid_places%',
  'Q5 nothing chosen: refused');
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 5, array['loads']) $$, :svc)) like '%invalid_places%',
  'Q6 Yüklər (or anything else) is not a place here');
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 30, array['services', 'parks']) $$, :svc)) like '%places_not_available%',
  'Q7 a section without that pack: refused, no made-up price');
select tests.check((select id from public.place_promo_order_create('service', :svc, 'premium', 5, array['parks', 'services', 'shops'])) = (select id from o where k = 's-all'),
  'Q8 a double tap re-uses the unpaid order');
select tests.check((select id from public.place_promo_order_create('service', :svc, 'premium', 5)) = (select id from o where k = 's-own'),
  'Q9 the 4-argument call (older app) = its own section: the same order as Servislər alone');
select tests.login(:shopown);
select tests.check((select places = array['shops'] and amount = 20 from public.place_promo_order_create('service', :shop, 'premium', 5)),
  'Q9b …a shop''s own section is Mağazalar (never re-uses its Parklar order)');
select tests.login(:svcown);
select tests.check((select kind = 'bump' and places is null from public.place_promo_order_create('service', :svc, 'bump', 3, array['parks'])), 'Q10 İrəli çək ignores places');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 5, array['services']) $$, :svc)) like '%not_found%',
  'Q11 only my own service / park');

-- ---- payment applies the places ----------------------------------------------------
reset role;
select pg_temp.as_service();
select public._place_promo_apply(id) from o where k in ('s-all', 'sh-parks', 'p-svc-shop');
select tests.check((select promo_premium_until > now() + interval '4 days' from public.service_providers where id = :svc)
                   and (select count(*) = 2 from public.place_promo_cross where source_id = :svc and place in ('parks', 'shops') and until > now() + interval '4 days')
                   and not exists (select 1 from public.place_promo_cross where source_id = :svc and place = 'services'),
  'A1 all three: Premium on its own map + Parklar and Mağazalar strips');
select tests.check((select promo_premium_until is null and promo_vip_until is null from public.service_providers where id = :shop)
                   and exists (select 1 from public.place_promo_cross where source_id = :shop and place = 'parks'),
  'A2 Parklar only: nothing on its own map, shown on Parklar');
select tests.check((select promo_premium_until is null from public.tir_parks where id = (select id from ids where k='p'))
                   and (select count(*) = 2 from public.place_promo_cross where source_kind = 'tirpark' and place in ('services', 'shops')),
  'A3 a park on Servislər + Mağazalar');
select public._place_promo_apply(id) from o where k = 's-own';
select tests.check((select promo_premium_until > now() + interval '9 days' from public.service_providers where id = :svc), 'A4 own section again: the days add up');

-- ---- what each section shows ---------------------------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check((select array_agg(source_id order by source_id) from public.place_cross_latest('parks')) = array[:svc, :shop]::uuid[],
  'S1 Parklar shows the service and the shop that chose it');
select tests.check((select bool_and(shop = (source_id = :shop)) from public.place_cross_latest('parks')), 'S2 …and knows which one is a shop');
select tests.check((select count(*) = 2 from public.place_cross_latest('shops', 40.4, 49.85)), 'S3 Mağazalar around Baku: the service and the park');
select tests.check(not exists (select 1 from public.place_cross_latest('shops', 41.7, 44.8)), 'S4 …not around Tbilisi (100 km)');
select tests.check(tests.err($$ insert into public.place_promo_cross (source_kind, source_id, place, until) values ('service', gen_random_uuid(), 'parks', now() + interval '9 days') $$)
  like '%permission denied%', 'S5 nobody writes Premium places himself');
reset role;
update public.service_providers set is_active = false where id = :shop;
set role authenticated;
select tests.check((select array_agg(source_id) from public.place_cross_latest('parks')) = array[:svc]::uuid[], 'S6 a closed shop leaves the strip');

-- ---- Yüklər: no advertising from / in it ---------------------------------------------
select tests.login(:shopown);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c1, :shopown, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date + 3);
insert into public.market_listings (id, category, brand, model, price, currency, status) values (:m1, 'truck', 'DAF', 'XF', 100, 'AZN', 'pending');
reset role;
update public.market_listings set status = 'active' where id = :m1;
set role authenticated;
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'premium', 5, array['loads']) $$, :c1)) like '%not_available%',
  'Y1 a load''s Premium with places: refused');
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'premium', 5, array['loads', 'market']) $$, :m1)) like '%invalid_places%',
  'Y2 a TIR Bazarı ad cannot pick Yüklər');
select tests.check((select places is null and kind = 'premium' from public.market_promo_order_create(:m1, 'premium', 5, array['market'])),
  'Y3 TIR Bazarı alone works as before');
reset role;
select tests.summary('PARK · SERVİS · MAĞAZA PREMIUM YERİ (0102)');
rollback;

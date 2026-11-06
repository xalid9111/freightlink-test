-- Premium of a park / service / shop also in TIR Bazarı and / or Yüklər —
-- 0102 + 0103 (0103 replaced 0102's Parklar · Servislər · Mağazalar
-- cards); no advertising from a load. Rolled back.
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
-- Prices told apart (5 days): Servis Premium 20, TIRPark Premium 30, Yüklər Premium 25; Yüklər has no 30-day pack.
update public.place_promo_plans set price = 20, is_active = true where target = 'service' and kind = 'premium' and qty = 5;
update public.place_promo_plans set price = 30, is_active = true where target = 'tirpark' and kind = 'premium' and qty = 5;
update public.place_promo_plans set is_active = true where target = 'service' and kind = 'premium' and qty = 30;
update public.cargo_promo_plans set price = 25, is_active = true where kind = 'premium' and qty = 5;
update public.cargo_promo_plans set is_active = false where kind = 'premium' and qty = 30;
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
                   and public._place_home('tirpark', (select id from ids where k='p')) = 'parks', 'H1 own maps: service → Servislər, shop → Mağazalar, park → Parklar');

-- ---- orders and prices ----------------------------------------------------------
set role authenticated;
select tests.login(:svcown);
insert into o select 's-market', id, amount, places from public.place_promo_order_create('service', :svc, 'premium', 5, array['market']);
insert into o select 's-both', id, amount, places from public.place_promo_order_create('service', :svc, 'premium', 5, array['loads', 'market']);
select tests.login(:shopown);
insert into o select 'sh-loads', id, amount, places from public.place_promo_order_create('service', :shop, 'premium', 5, array['loads']);
select tests.login(:parkown);
insert into o select 'p-both', id, amount, places from public.place_promo_order_create('tirpark', (select id from ids where k='p'), 'premium', 5, array['market', 'loads']);
select tests.check((select amount = 20 and places = array['market'] from o where k = 's-market'), 'Q1 TIR Bazarı only: the service''s own Premium price');
select tests.check((select amount = 45 and places = array['market', 'loads'] from o where k = 's-both'), 'Q2 both: 20 + the Yüklər Premium 25, places in a fixed order');
select tests.check((select amount = 20 from o where k = 'sh-loads'), 'Q3 a shop, Yüklər only: its own price');
select tests.check((select amount = 55 from o where k = 'p-both'), 'Q4 a park, both: 30 + 25');
select tests.login(:svcown);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 5, '{}'::text[]) $$, :svc)) like '%invalid_places%',
  'Q5 nothing chosen: refused');
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 5, array['parks']) $$, :svc)) like '%invalid_places%',
  'Q6 only TIR Bazarı / Yüklər are places (0102''s map cards are gone)');
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 30, array['market', 'loads']) $$, :svc)) like '%places_not_available%',
  'Q7 both without a Yüklər pack for those days: refused, no made-up price');
select tests.check((select id from public.place_promo_order_create('service', :svc, 'premium', 5, array['loads', 'market'])) = (select id from o where k = 's-both'),
  'Q8 a double tap re-uses the unpaid order');
select tests.check((select places is null from public.place_promo_order_create('service', :svc, 'premium', 1)),
  'Q9 the 4-argument call (older app) still works: own map only');
select tests.check((select kind = 'bump' and places is null from public.place_promo_order_create('service', :svc, 'bump', 3, array['market'])), 'Q10 İrəli çək ignores places');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.place_promo_order_create('service', %L, 'premium', 5, array['market']) $$, :svc)) like '%not_found%',
  'Q11 only my own service / park');

-- ---- payment: own map always + the chosen sections ---------------------------------
reset role;
select pg_temp.as_service();
select public._place_promo_apply(id) from o where k in ('s-both', 'sh-loads', 'p-both');
select tests.check((select promo_premium_until > now() + interval '4 days' and promo_vip_until >= promo_premium_until from public.service_providers where id = :svc)
                   and (select count(*) = 2 from public.place_promo_cross where source_id = :svc and place in ('market', 'loads') and until > now() + interval '4 days'),
  'A1 both: Premium on its own map and in TIR Bazarı + Yüklər');
select tests.check((select promo_premium_until > now() + interval '4 days' from public.service_providers where id = :shop)
                   and exists (select 1 from public.place_promo_cross where source_id = :shop and place = 'loads')
                   and not exists (select 1 from public.place_promo_cross where source_id = :shop and place = 'market'),
  'A2 Yüklər only: own map + Yüklər, not TIR Bazarı');
select tests.check((select promo_premium_until is not null from public.tir_parks where id = (select id from ids where k='p'))
                   and (select count(*) = 2 from public.place_promo_cross where source_kind = 'tirpark'), 'A3 a park, both');
select public._place_promo_apply(id) from o where k = 's-market';
select tests.check((select promo_premium_until > now() + interval '9 days' from public.service_providers where id = :svc)
                   and (select until > now() + interval '9 days' from public.place_promo_cross where source_id = :svc and place = 'market'),
  'A4 again: the days add up on the map and in the strip');

-- ---- what TIR Bazarı / Yüklər show -----------------------------------------------------
set role authenticated;
select tests.login(:other);
select tests.check((select array_agg(source_id order by source_id) from public.place_cross_latest('loads'))
                   = (select array_agg(x order by x) from unnest(array[:svc, :shop, (select id from ids where k='p')]::uuid[]) x),
  'S1 Yüklər shows the service, the shop and the park that chose it');
select tests.check((select bool_and(shop = (source_id = :shop)) from public.place_cross_latest('loads')), 'S2 …and knows which one is a shop');
select tests.check((select count(*) = 2 from public.place_cross_latest('market')), 'S3 TIR Bazarı: the service and the park');
select tests.check(not exists (select 1 from public.place_cross_latest('loads', 41.7, 44.8)), 'S4 with a map centre: only within 100 km');
select tests.check(tests.err($$ insert into public.place_promo_cross (source_kind, source_id, place, until) values ('service', gen_random_uuid(), 'loads', now() + interval '9 days') $$)
  like '%permission denied%', 'S5 nobody writes Premium places himself');
reset role;
update public.service_providers set is_active = false where id = :shop;
set role authenticated;
select tests.check(not exists (select 1 from public.place_cross_latest('loads') where source_id = :shop), 'S6 a closed shop leaves the strip');

-- ---- a load takes no advertising; a TIR Bazarı ad never picks Yüklər --------------------
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
select tests.check((select kind = 'premium' from public.market_promo_order_create(:m1, 'premium', 5, array['market'])),
  'Y3 TIR Bazarı alone works as before');
reset role;
select tests.summary('PARK · SERVİS · MAĞAZA PREMIUM: TIR BAZARI · YÜKLƏR (0102 + 0103)');
rollback;

-- Premium: where it is shown — 0101. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c1010000-0000-4000-8000-000000000001'''
\set c2 '''c1010000-0000-4000-8000-000000000002'''
\set c3 '''c1010000-0000-4000-8000-000000000003'''
\set m1 '''aa101000-0000-4000-8000-000000000001'''
\set m2 '''aa101000-0000-4000-8000-000000000002'''

begin;
create or replace function pg_temp.as_service() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', false), set_config('request.jwt.claim.sub', '', false);
$$;
create temp table o (k text primary key, id uuid, amount numeric, places text[]) on commit drop;
grant all on o to authenticated;
-- Prices of the two sections (5 days = 20 AZN each by default; changed to tell them apart).
update public.cargo_promo_plans set price = 20 where kind = 'premium' and qty = 5;
update public.market_promo_plans set price = 25 where kind = 'premium' and qty = 5;
update public.market_promo_plans set is_active = false where kind = 'premium' and qty = 30;

set role authenticated;
select tests.login(:owner);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date + 3),
       (:c2, :owner, 'Azerbaijan', 'Baku', 'Russia', 'Moscow', 20000, 1500, current_date + 3),
       (:c3, :owner, 'Azerbaijan', 'Ganja', 'Turkey', 'Istanbul', 20000, 1500, current_date + 3);
insert into public.market_listings (id, category, brand, model, price, currency, status)
values (:m1, 'truck', 'DAF', 'XF', 100, 'AZN', 'pending'), (:m2, 'truck', 'MAN', 'TGX', 100, 'AZN', 'pending');
update public.market_listings set status = 'active' where id in (:m1, :m2);

-- Orders and prices.
insert into o select 'c-loads', id, amount, places from public.cargo_promo_order_create(:c1, 'premium', 5, array['loads']);
insert into o select 'c-market', id, amount, places from public.cargo_promo_order_create(:c2, 'premium', 5, array['market']);
insert into o select 'c-both', id, amount, places from public.cargo_promo_order_create(:c3, 'premium', 5, array['market', 'loads']);
insert into o select 'm-both', id, amount, places from public.market_promo_order_create(:m1, 'premium', 5, array['loads', 'market']);
insert into o select 'm-loads', id, amount, places from public.market_promo_order_create(:m2, 'premium', 5, array['loads']);
select tests.check((select amount = 20 and places = array['loads'] from o where k = 'c-loads'), 'Q1 a load, Yüklər only: the Loads Premium price');
select tests.check((select amount = 20 and places = array['market'] from o where k = 'c-market'), 'Q2 a load, TIR Bazarı only: the same current price');
select tests.check((select amount = 45 and places = array['loads', 'market'] from o where k = 'c-both'), 'Q3 both places: 20 + 25 (the two sections'' prices)');
select tests.check((select amount = 45 from o where k = 'm-both'), 'Q4 a TIR Bazarı ad, both places: 25 + 20');
select tests.check((select amount = 25 from o where k = 'm-loads'), 'Q5 an ad, Yüklər only: the TIR Bazarı Premium price');
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'premium', 5, '{}'::text[]) $$, :c1)) like '%invalid_places%',
  'Q6 no place chosen: refused');
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'premium', 5, array['moon']) $$, :c1)) like '%invalid_places%',
  'Q7 an unknown place: refused');
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'premium', 30, array['loads','market']) $$, :c1)) like '%both_not_available%',
  'Q8 both places without a TIR Bazarı pack for those days: refused, no made-up price');
select tests.check((select id from public.cargo_promo_order_create(:c3, 'premium', 5, array['loads','market'])) = (select id from o where k = 'c-both'),
  'Q9 a double tap re-uses the unpaid order');
select tests.check((select count(*) = 1 from public.cargo_promo_order_create(:c1, 'premium', 5)), 'Q10 the old 3-argument call still works');

-- Payment applied (the verified-payment path calls these, as the payment service).
reset role;
select pg_temp.as_service();
select public._cargo_promo_apply(id) from o where k in ('c-loads', 'c-market', 'c-both');
select public._market_promo_apply(id) from o where k in ('m-both', 'm-loads');
select tests.check((select premium_until > now() + interval '4 days' from public.cargo where id = :c1)
                   and not exists (select 1 from public.promo_cross where source_id = :c1), 'A1 Yüklər only: Premium on the Loads page only');
select tests.check((select premium_until is null from public.cargo where id = :c2)
                   and exists (select 1 from public.promo_cross where source_kind = 'cargo' and source_id = :c2 and place = 'market' and until > now() + interval '4 days'),
  'A2 TIR Bazarı only: not on top of Loads, Premium in TIR Bazarı');
select tests.check((select premium_until is not null from public.cargo where id = :c3)
                   and exists (select 1 from public.promo_cross where source_id = :c3 and place = 'market'), 'A3 both: in both sections');
select tests.check((select premium_until is not null from public.market_listings where id = :m1)
                   and exists (select 1 from public.promo_cross where source_kind = 'market' and source_id = :m1 and place = 'loads'), 'A4 an ad, both: in both');
select tests.check((select premium_until is null from public.market_listings where id = :m2)
                   and exists (select 1 from public.promo_cross where source_id = :m2 and place = 'loads'), 'A5 an ad, Yüklər only');

set role authenticated;
select tests.login(:other);
select tests.check((select array_agg(source_id order by source_id) from public.promo_cross_latest('market')) = array[:c2, :c3]::uuid[],
  'S1 TIR Bazarı shows the loads that chose it');
select tests.check((select array_agg(source_id order by source_id) from public.promo_cross_latest('loads')) = array[:m1, :m2]::uuid[],
  'S2 Yüklər shows the ads that chose it');
select tests.check(tests.err($$ insert into public.promo_cross (source_kind, source_id, place, until) values ('cargo', gen_random_uuid(), 'market', now() + interval '9 days') $$)
  like '%permission denied%', 'S3 nobody writes Premium places himself');
reset role;
set local app.cargo_trusted = '1';
update public.cargo set status = 'cancelled' where id = :c2;
set local app.cargo_trusted = '';
set role authenticated;
select tests.check((select array_agg(source_id) from public.promo_cross_latest('market')) = array[:c3]::uuid[], 'S4 a closed load leaves TIR Bazarı');
reset role;
select tests.summary('PREMIUM YAYIM YERİ (0101)');
rollback;

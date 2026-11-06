-- Premium: where it is shown — 0101 (new orders with Yüklər refused by 0102). Rolled back.
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

-- Orders made while 0101 took them (0102 refuses new ones with Yüklər, see
-- 140): written directly, as they are in the database; the payment of such
-- an order still applies it.
reset role;
insert into o values
  ('c-loads', gen_random_uuid(), 20, array['loads']), ('c-market', gen_random_uuid(), 20, array['market']),
  ('c-both', gen_random_uuid(), 45, array['loads', 'market']);
insert into o values ('m-both', gen_random_uuid(), 45, array['loads', 'market']), ('m-loads', gen_random_uuid(), 25, array['loads']);
insert into public.cargo_promo_orders (id, cargo_id, user_id, kind, qty, amount, currency, places)
select o.id, x.c, :owner, 'premium', 5, o.amount, 'AZN', o.places
  from o join (values ('c-loads', :c1::uuid), ('c-market', :c2::uuid), ('c-both', :c3::uuid)) x(k, c) on x.k = o.k;
insert into public.market_promo_orders (id, listing_id, user_id, kind, qty, amount, currency, places)
select o.id, x.l, :owner, 'premium', 5, o.amount, 'AZN', o.places
  from o join (values ('m-both', :m1::uuid), ('m-loads', :m2::uuid)) x(k, l) on x.k = o.k;
set role authenticated;
select tests.login(:owner);
select tests.check(tests.err(format($$ select public.cargo_promo_order_create(%L, 'premium', 5, array['loads','market']) $$, :c3)) like '%not_available%',
  'Q1 0102: a load''s Premium with places is no longer taken');
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'premium', 5, array['loads']) $$, :m2)) like '%invalid_places%',
  'Q2 0102: a TIR Bazarı ad cannot pick Yüklər');
select tests.check((select kind = 'premium' and amount = 25 from public.market_promo_order_create(:m2, 'premium', 5, array['market'])), 'Q3 TIR Bazarı alone: as before');

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
select tests.check((select premium_until > now() + interval '4 days' from public.market_listings where id = :m1)
                   and (select premium_until > now() + interval '4 days' from public.market_listings where id = :m2)
                   and not exists (select 1 from public.promo_cross where source_kind = 'market'),
  'A4 0102: an ad''s paid Premium is TIR Bazarı''s (Yüklər shows no ads), also an order made with Yüklər');

set role authenticated;
select tests.login(:other);
select tests.check((select array_agg(source_id order by source_id) from public.promo_cross_latest('market')) = array[:c2, :c3]::uuid[],
  'S1 TIR Bazarı shows the loads that chose it');
select tests.check(not exists (select 1 from public.promo_cross_latest('loads')), 'S2 Yüklər: no ads');
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

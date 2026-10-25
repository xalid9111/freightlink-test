-- TIR BAZARI "Satışdadır" / "Sifarişlə", wheel formula, equipment,
-- damage — 0065. Rolled back.
\set seller '''a0000000-0000-4000-8000-000000000012'''
\set buyer  '''a0000000-0000-4000-8000-000000000021'''
\set o1 '''aa650000-0000-4000-8000-000000000001'''
\set o2 '''aa650000-0000-4000-8000-000000000002'''
\set o3 '''aa650000-0000-4000-8000-000000000003'''

begin;
set role authenticated;
select tests.login(:seller);
-- o1: an older ad (no value) · o2: in stock · o3: brought on order.
insert into public.market_listings (id, category, brand, model, year, price, currency, city, photos, availability)
values (:o1, 'truck', 'DAF', 'XF', 2019, 50000, 'EUR', 'Baku', '{a.jpg}', null),
       (:o2, 'truck', 'Scania', 'R450', 2020, 60000, 'EUR', 'Baku', '{a.jpg}', 'in_stock'),
       (:o3, 'trailer', 'Krone', 'Profi Liner', 2025, 30000, 'EUR', 'Baku', '{a.jpg}', 'on_order');
update public.market_listings set status = 'active' where id in (:o1, :o2, :o3);
select tests.check((select count(*) = 3 from public.market_listings where id in (:o1, :o2, :o3) and status = 'active'),
  'O1 ads with and without in stock / on order are published');
select tests.check(tests.err($$ insert into public.market_listings (category, brand, availability) values ('truck', 'X', 'soon') $$)
  like '%market_listings_availability_check%', 'O2 an unknown value is refused');
update public.market_listings set availability = 'on_order' where id = :o2;
select tests.check((select availability = 'on_order' from public.market_listings where id = :o2),
  'O3 the seller can change it');
update public.market_listings set availability = 'in_stock' where id = :o2;

select tests.login(:buyer);
select tests.check((select array_agg(id) = array[:o3]::uuid[] from public.market_search(p_availability => 'on_order')
                     where id in (:o1, :o2, :o3)),
  'O4 "Sifarişlə" finds only the ad on order');
select tests.check((select count(*) = 2 from public.market_search(p_availability => 'in_stock')
                     where id in (:o1, :o2, :o3)),
  'O5 "Satışdadır" finds the in-stock ad and the older ad without a value');
select tests.check((select count(*) = 3 from public.market_search() where id in (:o1, :o2, :o3)),
  'O6 no choice = all ads');
select tests.check((select count(*) = 1 from public.market_search(p_category => 'trailer', p_brand => 'Krone',
                      p_availability => 'on_order')),
  'O7 works together with category and brand');
select tests.check((select count(*) >= 3 from public.market_search(null, null, null, null, null, null, null, null, null, null, false, 20, 0)),
  'O8 the old 13-parameter call (app already on phones) still works');
select tests.check((select count(*) >= 1 from public.market_search(p_brand => 'DAF', p_brands => array['DAF'], p_body_type => null)),
  'O9 the 0064 call (16 parameters by name) still works');
reset role;
set role authenticated;
select tests.login(:seller);
update public.market_listings set axle_formula = '6x4', equipment = array['retarder', 'adr'], damaged = false where id = :o1;
update public.market_listings set axle_formula = '4x2', equipment = array['sleeper'], damaged = true where id = :o2;
select tests.check(tests.err($$ update public.market_listings set axle_formula = '10x10' where id = 'aa650000-0000-4000-8000-000000000001' $$)
  like '%market_listings_axle_formula_check%', 'O13 an unknown wheel formula is refused');
select tests.check(tests.err($$ update public.market_listings set equipment = array['jacuzzi'] where id = 'aa650000-0000-4000-8000-000000000001' $$)
  like '%market_listings_equipment_check%', 'O14 unknown equipment is refused');
select tests.login(:buyer);
select tests.check((select array_agg(id) = array[:o1]::uuid[] from public.market_search(p_axle_formula => '6x4')
                     where id in (:o1, :o2, :o3)),
  'O15 search by wheel formula');
select tests.check((select array_agg(id) = array[:o1]::uuid[] from public.market_search(p_equipment => array['adr', 'retarder'])
                     where id in (:o1, :o2, :o3)),
  'O16 equipment: the ad has every chosen item');
select tests.check((select count(*) = 0 from public.market_search(p_equipment => array['adr', 'sleeper'])
                     where id in (:o1, :o2, :o3)),
  'O17 equipment: an ad missing one chosen item is not shown');
select tests.check((select array_agg(id) = array[:o1]::uuid[] from public.market_search(p_damaged => false)
                     where id in (:o1, :o2, :o3)),
  'O18 "Vuruğu yoxdur" finds only ads marked without damage');
select tests.check((select array_agg(id) = array[:o2]::uuid[] from public.market_search(p_damaged => true)
                     where id in (:o1, :o2, :o3)),
  'O19 "Vuruğu var" finds only ads marked with damage');
select tests.check((select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'market_search'),
  'O10 exactly one market_search (no overload conflict)');
select tests.check((select availability is null and brand = 'DAF' from public.market_listings where id = :o1),
  'O11 the older ad keeps its values (no value = in stock)');
reset role;
set role anon;
select tests.check(tests.err($$ select * from public.market_search(p_availability => 'on_order') $$) like '%permission denied%',
  'O12 still not for anon');
reset role;
rollback;

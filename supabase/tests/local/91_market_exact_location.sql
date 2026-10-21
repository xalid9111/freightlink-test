-- TIR BAZARI EXACT PLACE — 0053. Rolled back.
\set seller  '''a0000000-0000-4000-8000-000000000012'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set l1 '''aa530000-0000-4000-8000-000000000001'''

begin;
set role authenticated;
select tests.login(:seller);
insert into public.market_listings (id, owner_id, category, brand, model, year, price, currency, city, country, lat, lng, location_exact, photos, status)
values (:l1, :seller, 'truck', 'Volvo', 'FH', 2018, 50000, 'USD', 'Baku', 'AZ', 40.41, 49.86, true, array['https://x/1.jpg'], 'draft');
select tests.check((select location_exact and lat = 40.41 from public.market_listings where id = :l1), 'L1 the seller marks the exact place');
select tests.check((select count(*) = 0 from public.market_listings where location_exact and id <> :l1), 'L2 existing ads stay "city centre"');
select tests.login(:other);
update public.market_listings set lat = 1, lng = 1, location_exact = false where id = :l1;
reset role;
select tests.check((select location_exact and lat = 40.41 from public.market_listings where id = :l1), 'L3 nobody else moves it');
select tests.summary('TIR BAZARI EXACT PLACE (0053)');
rollback;

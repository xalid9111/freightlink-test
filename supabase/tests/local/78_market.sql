-- TIR BAZARI — 0040: sale ads, admin approval, VIP, views, favourites,
-- similar ads, reports. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set seller  '''a0000000-0000-4000-8000-000000000012'''
\set buyer   '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''
\set l1 '''aa400000-0000-4000-8000-000000000001'''
\set l2 '''aa400000-0000-4000-8000-000000000002'''
\set l3 '''aa400000-0000-4000-8000-000000000003'''

begin;
set role authenticated;
select tests.login(:seller);
-- A seller cannot make his ad VIP / active / counted by himself.
insert into public.market_listings (id, category, brand, model, year, mileage_km, price, currency, country, city, status, is_vip, views, photos)
values (:l1, 'truck', 'DAF', 'XF 106', 2017, 420000, 32500, 'EUR', 'Azerbaijan', 'Baku', 'active', true, 999, '{a.jpg,b.jpg}');
select tests.check((select status = 'draft' and not is_vip and views = 0 and owner_id = :seller and listing_no >= 10001
                    from public.market_listings where id = :l1), 'M1 new ad = draft, no VIP, no fake views, own owner');
select tests.check(tests.err($$ insert into public.market_listings (category, brand, photos)
  values ('truck', 'X', array_fill('p'::text, array[21])) $$) like '%market_listings_photos_check%', 'M1b at most 20 photos');

select tests.login(:buyer);
select tests.check(not exists (select 1 from public.market_listings where id = :l1), 'M2 a draft is private');

select tests.login(:seller);
update public.market_listings set status = 'pending' where id = :l1;           -- "Elanı dərc et"
select tests.check((select status from public.market_listings where id = :l1) = 'pending', 'M3 publish → waits for the admin');
select tests.check(tests.err(format($$ update public.market_listings set status = 'active' where id = %L $$, :l1)) like '%invalid_status_change%',
  'M4 the owner cannot approve himself');

select tests.login(:buyer);
select tests.check(not exists (select 1 from public.market_listings where id = :l1)
                   and (select count(*) = 0 from public.market_search()), 'M4b pending ad not shown to others / in the feed');
select tests.check(tests.err(format($$ select public.admin_market_set_status(%L, 'active') $$, :l1)) like '%admin_only%', 'M4c only admins approve');

select tests.login(:admin);
select public.admin_market_set_status(:l1, 'active');
select tests.check((select status = 'active' and published_at is not null from public.market_listings where id = :l1), 'M5 admin approves');

select tests.login(:buyer);
select tests.check((select count(*) = 1 from public.market_search()), 'M5b approved ad is in the feed');
update public.market_listings set price = 1 where id = :l1;
select tests.check((select price = 32500 from public.market_listings where id = :l1), 'M6 nobody else can edit it');
select tests.check(public.market_record_view(:l1) = 1, 'M7 a real view is counted');
select tests.check(public.market_record_view(:l1) = 1, 'M7b same viewer same day counted once');
insert into public.market_favorites (user_id, listing_id) values (:buyer, :l1);
select tests.check((select count(*) = 1 from public.market_favorites), 'M8 favourite saved');
insert into public.reports (reporter_id, target_type, target_id, reason) values (:buyer, 'market_listing', :l1, 'fake');
select tests.check((select count(*) = 1 from public.reports where target_type = 'market_listing'), 'M9 a sale ad can be reported');

select tests.login(:seller);
select tests.check(public.market_record_view(:l1) = 1, 'M7c the owner''s own views are not counted');
select tests.check((select count(*) = 0 from public.market_favorites), 'M8b favourites are private');
update public.market_listings set views = 5000, is_vip = true where id = :l1;
select tests.check((select views = 1 and not is_vip from public.market_listings where id = :l1), 'M10 owner cannot change views / VIP');
update public.market_listings set price = 31000 where id = :l1;
select tests.check((select status = 'pending' and price = 31000 from public.market_listings where id = :l1), 'M11 editing a published ad → admin again');

-- Two more ads for order / similar checks.
insert into public.market_listings (id, category, brand, model, year, price, status) values
  (:l2, 'truck', 'DAF', 'XF 105', 2016, 28000, 'pending'),
  (:l3, 'truck', 'Volvo', 'FH 500', 2019, 67000, 'pending');
select tests.login(:admin);
select public.admin_market_set_status(:l1, 'active');
select public.admin_market_set_status(:l2, 'active');
select public.admin_market_set_status(:l3, 'active');
select public.admin_market_set_vip(:l3, true, 7);
select tests.check((select is_vip and vip_until > now() + interval '6 days' from public.market_listings where id = :l3), 'M12 admin: VIP for 7 days');

select tests.login(:buyer);
select tests.check((select id from public.market_search() limit 1) = :l3, 'M13 VIP first in the feed');
select tests.check((select count(*) = 1 from public.market_search(p_vip_only => true)), 'M13b VIP-only list');
select tests.check((select count(*) = 2 from public.market_search(p_brand => 'daf')), 'M14 filter by brand');
select tests.check((select count(*) = 1 from public.market_search(p_q => 'XF 106')), 'M14b search brand / model text');
select tests.check((select count(*) = 1 from public.market_search(p_min_price => 30000, p_max_price => 40000)), 'M14c price range');
select tests.check((select array_agg(id) from public.market_similar(:l1)) = array[:l2::uuid], 'M15 similar: same brand (Volvo not shown, self not shown)');

select tests.login(:admin);
select public.admin_market_set_vip(:l3, false);
select public.admin_market_set_status(:l2, 'inactive', 'duplicate');
select tests.login(:buyer);
select tests.check((select count(*) = 2 from public.market_search()) and not exists (select 1 from public.market_listings where id = :l2),
  'M16 deactivated ad disappears');

select tests.login(:seller);
select tests.check((select admin_note = 'duplicate' from public.market_listings where id = :l2), 'M16b owner sees why');
update public.market_listings set status = 'sold' where id = :l1;
select tests.check((select status = 'sold' and sold_at is not null from public.market_listings where id = :l1), 'M17 owner marks sold');
select tests.login(:buyer);
select tests.check((select count(*) = 1 from public.market_search()), 'M17b sold ad leaves the feed');

select tests.login(:blocked);
select tests.check(tests.err($$ insert into public.market_listings (category, brand) values ('truck', 'MAN') $$) like '%row-level security%',
  'M18 blocked accounts cannot post');

select tests.login(:seller);
delete from public.market_listings where id = :l2;
select tests.check(not exists (select 1 from public.market_listings where id = :l2), 'M19 owner deletes their own ad');
select tests.login(:admin);
select public.admin_market_delete(:l3, 'test');
select tests.check(not exists (select 1 from public.market_listings where id = :l3)
                   and exists (select 1 from public.admin_audit_log where action = 'market.delete'), 'M20 admin delete is logged');
reset role;

select tests.summary('TIR BAZARI (0040)');
rollback;

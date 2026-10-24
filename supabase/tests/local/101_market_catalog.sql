-- TIR BAZARI CATALOGUE — 0064: medium / light trucks, body type, search by
-- every spelling of a brand / model. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set seller '''a0000000-0000-4000-8000-000000000012'''
\set buyer  '''a0000000-0000-4000-8000-000000000021'''
\set m1 '''aa640000-0000-4000-8000-000000000001'''
\set m2 '''aa640000-0000-4000-8000-000000000002'''
\set m3 '''aa640000-0000-4000-8000-000000000003'''
\set m4 '''aa640000-0000-4000-8000-000000000004'''

begin;
select tests.check((select pg_get_constraintdef(oid) like '%''light_truck''%' from pg_constraint
                     where conrelid = 'public.market_listings'::regclass and conname = 'market_listings_category_check'),
  'C1 the 0040 category check now has 7 classes');
select tests.check((select count(*) = 1 from pg_constraint
                     where conrelid = 'public.market_listings'::regclass and contype = 'c'
                       and pg_get_constraintdef(oid) like '%''semitrailer''%'),
  'C1b one category check (replaced, not doubled)');
select tests.check((select count(*) = 20 from pg_constraint
                     where conrelid = 'public.market_listings'::regclass and contype = 'c'),
  'C1c the 19 checks of 0040 are all still there, + body type = 20');

set role authenticated;
select tests.login(:seller);
insert into public.market_listings (id, category, brand, model, year, price, currency, city, photos, body_type)
values (:m1, 'light_truck', 'GAZ', 'GAZelle Next', 2021, 18000, 'USD', 'Baku', '{a.jpg}', 'van'),
       (:m2, 'medium_truck', 'Hyundai', 'HD78', 2019, 30000, 'USD', 'Baku', '{a.jpg}', 'tow_truck'),
       (:m3, 'truck', 'Mercedes', 'Actros', 2018, 60000, 'EUR', 'Baku', '{a.jpg}', null),
       (:m4, 'truck', 'Volvo', 'FH-16', 2017, 55000, 'EUR', 'Baku', '{a.jpg}', null);
update public.market_listings set status = 'active' where id in (:m1, :m2, :m3, :m4);
select tests.check((select count(*) = 4 from public.market_listings where id in (:m1, :m2, :m3, :m4) and status = 'active'),
  'C2 light / medium truck ads with a body type are published');
select tests.check(tests.err($$ insert into public.market_listings (category, brand) values ('plane', 'X') $$)
  like '%market_listings_category_check%', 'C3 an unknown category is refused');
select tests.check(tests.err($$ insert into public.market_listings (category, brand, body_type) values ('truck', 'X', 'rocket') $$)
  like '%market_listings_body_type_check%', 'C4 an unknown body type is refused');

select tests.login(:buyer);
select tests.check((select count(*) = 1 from public.market_search(p_category => 'light_truck')), 'C5 search by the new category');
select tests.check((select count(*) = 1 from public.market_search(p_body_type => 'tow_truck')), 'C6 search by body type');
select tests.check((select count(*) = 1 from public.market_search(p_brand => 'Mercedes-Benz',
                      p_brands => array['Mercedes-Benz', 'Mercedes', 'MB'])),
  'C7 "Mercedes" typed by the seller is found under Mercedes-Benz');
select tests.check((select count(*) = 1 from public.market_search(p_brand => 'Volvo', p_model => 'FH16',
                      p_models => array['FH16'])),
  'C8 "FH-16" = "FH16" (no case, spaces or punctuation)');
select tests.check((select count(*) = 0 from public.market_search(p_brand => 'Mercedes-Benz')),
  'C9 without the spellings the old exact rule is unchanged');
select tests.check((select count(*) >= 4 from public.market_search(null, null, null, null, null, null, null, null, null, null, false, 20, 0)),
  'C10 the old 13-parameter call (app already on phones) still works');
select tests.check((select brand = 'Mercedes' and model = 'Actros' from public.market_listings where id = :m3),
  'C11 the stored spelling is not changed');
select tests.check((select count(*) = 1 from public.market_search(
                      p_category => null, p_q => null, p_brand => 'Volvo', p_model => null, p_city => null,
                      p_min_price => null, p_max_price => null, p_year_from => null, p_year_to => null,
                      p_max_mileage => null, p_vip_only => false, p_limit => 20, p_offset => 0)),
  'C10b the old app call by name (13 parameters, as PostgREST sends it) still works');
select tests.check((select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'market_search'),
  'C13 exactly one market_search (no overload conflict)');
select tests.login(:admin);
select public.admin_market_set_vip(:m2, true, 7);
select tests.login(:buyer);
select tests.check((select array_agg(id) = array[:m2]::uuid[] from public.market_search(p_vip_only => true)),
  'C14 VIP-only search (the VIP places) works as before');
select tests.check((select id = :m2 from public.market_search() limit 1),
  'C15 VIP ad still first in the feed');
reset role;
set role anon;
select tests.check(tests.err($$ select * from public.market_search() $$) like '%permission denied%', 'C12 still not for anon');
reset role;
rollback;

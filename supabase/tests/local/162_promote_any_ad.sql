-- 0125: anybody signed in may promote any active TIR Bazarı ad; the payer
-- owns the order and only he pays it; the ad changes only after payment.
\set seller  '''a0000000-0000-4000-8000-000000000012'''
\set buyer   '''a0000000-0000-4000-8000-000000000021'''
\set other   '''a0000000-0000-4000-8000-000000000022'''
\set ad1 '''ab250000-0000-4000-8000-000000000001'''
\set ad2 '''ab250000-0000-4000-8000-000000000002'''

begin;
reset role;
-- LIVE checkout (test mode is open only to the finance owner); rolled back.
insert into public.payment_settings (id, mode, provider, commission_pct, methods) values (1, 'live', 'payriff', 0, '{card}')
  on conflict (id) do update set mode = 'live', provider = 'payriff', methods = '{card}';
set local app.market_trusted = '1';
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status, published_at)
values (:ad1, :seller, 'truck', 'DAF', 'XF', 38000, 'USD', 'active', now() - interval '1 day'),
       (:ad2, :seller, 'truck', 'MAN', 'TGX', 30000, 'USD', 'inactive', now() - interval '1 day');
set local app.market_trusted = '';
insert into public.market_promo_plans (kind, qty, price, currency, is_active) values ('bump', 1, 3, 'AZN', true)
  on conflict do nothing;

set role authenticated;
select tests.login(:buyer);
select tests.check((select user_id = :buyer and listing_id = :ad1 from public.market_promo_order_create(:ad1, 'bump', 1)),
  'A1 a friend orders İrəli çək for another person''s ad; the order is his');
select tests.check((select user_id = :buyer from public.market_vip_order_create(:ad1,
                      (select days from public.market_vip_plans where is_active order by days limit 1))),
  'A2 a friend orders VIP for another person''s ad');
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'bump', 1) $$, :ad2)) like '%listing_not_active%',
  'A3 never for an ad that is not active');
select tests.check((select bump_start is null from public.market_listings where id = :ad1),
  'A4 the ad is not changed by an order (only after payment)');
reset role;
select id as o1 from public.market_promo_orders where listing_id = :ad1 and user_id = :buyer limit 1 \gset
set role authenticated;
select tests.login(:other);
select tests.check(tests.err(format($$ select public.market_promo_payment_create(%L, 'card', 'any-key-0001') $$, :'o1')) like '%order_not_found%',
  'A5 nobody else pays the payer''s order');
select tests.login(:buyer);
select tests.check((select market_promo_order_id = :'o1' and user_id = :buyer
                      from public.market_promo_payment_create(:'o1', 'card', 'any-key-0002')),
  'A6 the payer (not the owner) pays it');
reset role;
set role anon;
select tests.login(null);
select tests.check(tests.err(format($$ select public.market_promo_order_create(%L, 'bump', 1) $$, :ad1)) like '%permission denied%',
  'A7 a visitor cannot order');
reset role;
select tests.summary('ISTƏNILƏN ELANI ÖNƏ ÇIXAR (0125)');
rollback;

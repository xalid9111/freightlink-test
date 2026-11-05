-- Servis / TIRPark Önə çıxar packs available — 0095. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''

begin;
select tests.check((select count(*) from public.place_promo_plans p
                     join (values ('service'), ('tirpark')) t(target) on t.target = p.target
                    where p.kind in ('bump', 'vip', 'premium') and p.is_active) >= 24,
  'A1 every section has İrəli çək · VIP · Premium packs');
select tests.check(exists (select 1 from public.place_promo_plans where target = 'tirpark' and kind = 'vip' and qty = 30 and price = 40 and is_active),
  'A2 TIRPark VIP 30 days = 40 AZN (the Loads price)');
select tests.check(exists (select 1 from public.place_promo_plans where target = 'service' and kind = 'premium' and qty = 1 and is_active),
  'A3 Servis Premium 1 day exists');
-- An admin's price is never changed by a re-run.
update public.place_promo_plans set price = 99, is_active = false where target = 'tirpark' and kind = 'bump' and qty = 1;
-- the same insert as 0095 (the whole file is also re-run by run_local.sh)
insert into public.place_promo_plans (target, kind, qty, price, currency, is_active)
select t.target, p.kind, p.qty, p.price, 'AZN', true
  from (values ('service'), ('tirpark')) t(target)
 cross join (values
   ('bump', 1, 3), ('bump', 3, 6), ('bump', 5, 9), ('bump', 10, 15),
   ('vip', 1, 5), ('vip', 5, 15), ('vip', 15, 25), ('vip', 30, 40),
   ('premium', 1, 7), ('premium', 5, 20), ('premium', 15, 45), ('premium', 30, 60)
 ) p(kind, qty, price)
on conflict (target, kind, qty) do nothing;
select tests.check((select price = 99 and not is_active from public.place_promo_plans where target = 'tirpark' and kind = 'bump' and qty = 1),
  'A4 re-run keeps the admin''s price and on / off');
-- A park manager can order now (the pack is there).
select tests.check(exists (select 1 from public.place_promo_plans where target = 'tirpark' and kind = 'premium' and qty = 5 and is_active),
  'A5 the Premium 5-day pack can be ordered');
select tests.summary('SERVİS / TIRPARK ÖNƏ ÇIXAR PAKETLƏRİ (0095)');
rollback;

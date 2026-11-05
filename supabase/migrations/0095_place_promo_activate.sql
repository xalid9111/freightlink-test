-- =====================================================================
-- 0095 — Servis / TIRPark "Önə çıxar": make the packs available
-- (owner, 05.11.2026: "hazırda mövcud deyil olmasın").
--
-- Run AFTER 0093.
--
-- 1) Every section (service, tirpark) gets every pack of İrəli çək ·
--    VIP · Premium with the standard Loads prices (CLAUDE.md §5:
--    İrəli çək 1/3/5/10 = 3/6/9/15, VIP 1/5/15/30 = 5/15/25/40,
--    Premium 1/5/15/30 = 7/20/45/60 AZN) — ONLY where the pack is missing.
--    A price or on / off the admin already set is never changed.
-- 2) The API (PostgREST) is told to reload, so the app sees the 0093
--    table and functions at once.
--
-- Safe: forward-only, re-runnable. Rows only added when missing; nothing
-- dropped, deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.place_promo_plans') is null
     or to_regprocedure('public.place_promo_order_create(text, uuid, text, integer)') is null then
    raise exception '0095: run 0093_place_promotions.sql first — nothing changed';
  end if;
end $$;

insert into public.place_promo_plans (target, kind, qty, price, currency, is_active)
select t.target, p.kind, p.qty, p.price, 'AZN', true
  from (values ('service'), ('tirpark')) t(target)
 cross join (values
   ('bump', 1, 3), ('bump', 3, 6), ('bump', 5, 9), ('bump', 10, 15),
   ('vip', 1, 5), ('vip', 5, 15), ('vip', 15, 25), ('vip', 30, 40),
   ('premium', 1, 7), ('premium', 5, 20), ('premium', 15, 45), ('premium', 30, 60)
 ) p(kind, qty, price)
on conflict (target, kind, qty) do nothing;

-- Final check: every section has an active pack of every kind.
do $$
begin
  if exists (
    select 1 from (values ('service'), ('tirpark')) t(target)
     cross join (values ('bump'), ('vip'), ('premium')) k(kind)
     where not exists (select 1 from public.place_promo_plans p
                        where p.target = t.target and p.kind = k.kind and p.is_active)) then
    raise warning '0095: some packs are switched off by an admin (Admin → Servislər / TIRPark → Önə çıxar qiymətləri)';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

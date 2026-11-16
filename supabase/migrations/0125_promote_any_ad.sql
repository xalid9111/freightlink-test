-- =====================================================================
-- 0125 — anybody may promote any active TIR Bazarı ad (owner, 16.11.2026:
-- "başqası istəyərsə elanı irəli çəkə, VIP edə, Premium edə bilsin … dostuma
-- deyə bilərəm ki, gir elanı aktiv elə").
--
-- Until now market_vip_order_create (0044) and market_promo_order_create
-- (0066) refused an ad that is not the caller's own ('listing_not_found').
-- Now any SIGNED-IN user may order İrəli çək / VIP / Premium for any ACTIVE
-- TIR Bazarı ad. Everything else stays exactly as it was:
--   * the server sets the price (the active plan), never the client;
--   * the order belongs to the payer (user_id) — only the payer pays it
--     (market_vip_payment_create / market_promo_payment_create, unchanged);
--   * the ad is promoted only after a verified payment (unchanged apply);
--   * the ad, its owner and its data are not changed by the order itself.
-- Loads (cargo) keep no advertising (0102); parks / services / shops keep
-- their own rules (0093) — not touched here.
--
-- Safe: forward-only, re-runnable; two functions replaced, nothing else.
-- =====================================================================

begin;

create or replace function public.market_vip_order_create(p_listing uuid, p_days integer)
returns public.market_vip_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_l public.market_listings;
  v_plan public.market_vip_plans;
  v_ord public.market_vip_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_l from market_listings where id = p_listing;
  -- 0125: any signed-in user, not only the owner.
  if v_l.id is null then raise exception 'listing_not_found' using errcode = 'P0002'; end if;
  if v_l.status <> 'active' then raise exception 'listing_not_active' using errcode = '22023'; end if;
  select * into v_plan from market_vip_plans where days = p_days and is_active;
  if v_plan.days is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from market_vip_orders
   where listing_id = p_listing and user_id = v_uid and days = p_days and status = 'pending_payment'
     and amount = v_plan.price and currency = v_plan.currency
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into market_vip_orders (listing_id, user_id, days, amount, currency)
  values (p_listing, v_uid, v_plan.days, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.market_vip_order_create(uuid, integer) from public, anon;
grant execute on function public.market_vip_order_create(uuid, integer) to authenticated;

create or replace function public.market_promo_order_create(p_listing uuid, p_kind text, p_qty integer)
returns public.market_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_l public.market_listings;
  v_plan public.market_promo_plans;
  v_ord public.market_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_l from market_listings where id = p_listing;
  -- 0125: any signed-in user, not only the owner.
  if v_l.id is null then raise exception 'listing_not_found' using errcode = 'P0002'; end if;
  if v_l.status <> 'active' then raise exception 'listing_not_active' using errcode = '22023'; end if;
  select * into v_plan from market_promo_plans where kind = p_kind and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from market_promo_orders
   where listing_id = p_listing and user_id = v_uid and kind = p_kind and qty = p_qty and status = 'pending_payment'
     and amount = v_plan.price and currency = upper(v_plan.currency)
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into market_promo_orders (listing_id, user_id, kind, qty, amount, currency)
  values (p_listing, v_uid, v_plan.kind, v_plan.qty, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.market_promo_order_create(uuid, text, integer) from public, anon;
grant execute on function public.market_promo_order_create(uuid, text, integer) to authenticated;

commit;

notify pgrst, 'reload schema';

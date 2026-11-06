-- =====================================================================
-- 0103 — Premium of a park / service / shop: shown in TIR Bazarı and / or
-- Yüklər too (owner, 07.11.2026; replaces the Parklar · Servislər ·
-- Mağazalar cards of 0102, which were a misunderstanding).
--
-- * The Premium sheet of a TIR park, a service or a shop has two cards:
--   TIR Bazarı ('market') · Yüklər bölməsi ('loads'); one or both; nothing
--   chosen = refused ('invalid_places').
-- * The place is ALWAYS Premium on its own map as before 0102 (TIRPark /
--   Servislər / Mağazalar list + map, VIP for the same days — 0093).
-- * Price (owner's "2 OK"): one place = the place's own current Premium
--   price (place_promo_plans); both = that price + the Yüklər Premium price
--   for the same days (cargo_promo_plans). No such Yüklər pack (or another
--   currency) = refused ('places_not_available'), no made-up price.
-- * After a verified payment the chosen sections show it in their
--   "Premium" strip (place_promo_cross, ends by date); a tap opens it.
-- * The 4-argument call (older app versions) = own map only, as in 0093.
-- * Orders paid under 0102's places keep working (own map + the other
--   sections they chose).
-- * TIR Bazarı ads still cannot pick Yüklər and loads take no advertising
--   (0102, owner: "3 xeyir").
--
-- Safe: forward-only, re-runnable. One check constraint widened (old values
-- kept), replaced functions (same signatures). No row is changed or deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.place_promo_cross') is null
     or to_regprocedure('public.place_promo_order_create(text, uuid, text, integer, text[])') is null then
    raise exception '0103: run 0102_place_premium_places.sql first — nothing changed';
  end if;
end $$;

-- 1) The strip may also be TIR Bazarı's or Yüklər's (0102's values stay).
alter table public.place_promo_cross drop constraint if exists place_promo_cross_place_check;
alter table public.place_promo_cross add constraint place_promo_cross_place_check
  check (place in ('parks', 'services', 'shops', 'market', 'loads'));

-- The places of a park / service / shop Premium: TIR Bazarı and / or Yüklər.
create or replace function public._place_places_ok(p_places text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_places is not null and cardinality(p_places) between 1 and 2
     and p_places <@ array['market', 'loads']
     and cardinality(p_places) = (select count(distinct x) from unnest(p_places) x);
$$;
revoke all on function public._place_places_ok(text[]) from public, anon, authenticated;

-- 2) The 4-argument call: as 0093 (own map only).
create or replace function public.place_promo_order_create(p_target text, p_id uuid, p_kind text, p_qty integer)
returns public.place_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_s public.service_providers;
  v_p public.tir_parks;
  v_plan public.place_promo_plans;
  v_ord public.place_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_target = 'service' then
    select * into v_s from service_providers where id = p_id;
    if v_s.id is null or v_s.owner_id is distinct from v_uid then raise exception 'not_found' using errcode = 'P0002'; end if;
    if v_s.status <> 'approved' or not v_s.is_active then raise exception 'not_open' using errcode = '22023'; end if;
    if v_s.lat is null or v_s.lng is null or (abs(v_s.lat) < 1e-6 and abs(v_s.lng) < 1e-6) then raise exception 'no_area' using errcode = '22023'; end if;
  elsif p_target = 'tirpark' then
    select * into v_p from tir_parks where id = p_id;
    if v_p.id is null or v_p.manager_id is distinct from v_uid or v_p.manager_status is distinct from 'approved' then
      raise exception 'not_found' using errcode = 'P0002';
    end if;
    if v_p.status <> 'approved' then raise exception 'not_open' using errcode = '22023'; end if;
  else
    raise exception 'invalid_target' using errcode = '22023';
  end if;
  select * into v_plan from place_promo_plans where target = p_target and kind = p_kind and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from place_promo_orders
   where target = p_target and coalesce(service_id, park_id) = p_id and user_id = v_uid and kind = p_kind and qty = p_qty
     and status = 'pending_payment' and amount = v_plan.price and currency = upper(v_plan.currency)
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into place_promo_orders (target, service_id, park_id, user_id, kind, qty, amount, currency)
  values (p_target, case when p_target = 'service' then p_id end, case when p_target = 'tirpark' then p_id end,
          v_uid, p_kind, p_qty, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.place_promo_order_create(text, uuid, text, integer) from public, anon;
grant execute on function public.place_promo_order_create(text, uuid, text, integer) to authenticated;

-- 3) Premium of MY park / service / shop with TIR Bazarı / Yüklər.
create or replace function public.place_promo_order_create(p_target text, p_id uuid, p_kind text, p_qty integer, p_places text[])
returns public.place_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_s public.service_providers;
  v_p public.tir_parks;
  v_places text[];
  v_plan public.place_promo_plans;
  v_loads public.cargo_promo_plans;
  v_amount numeric(12,2);
  v_ord public.place_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_kind is distinct from 'premium' then return public.place_promo_order_create(p_target, p_id, p_kind, p_qty); end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if not public._place_places_ok(p_places) then raise exception 'invalid_places' using errcode = '22023'; end if;
  -- Who may order: the same checks as 0093.
  if p_target = 'service' then
    select * into v_s from service_providers where id = p_id;
    if v_s.id is null or v_s.owner_id is distinct from v_uid then raise exception 'not_found' using errcode = 'P0002'; end if;
    if v_s.status <> 'approved' or not v_s.is_active then raise exception 'not_open' using errcode = '22023'; end if;
    if v_s.lat is null or v_s.lng is null or (abs(v_s.lat) < 1e-6 and abs(v_s.lng) < 1e-6) then raise exception 'no_area' using errcode = '22023'; end if;
  elsif p_target = 'tirpark' then
    select * into v_p from tir_parks where id = p_id;
    if v_p.id is null or v_p.manager_id is distinct from v_uid or v_p.manager_status is distinct from 'approved' then
      raise exception 'not_found' using errcode = 'P0002';
    end if;
    if v_p.status <> 'approved' then raise exception 'not_open' using errcode = '22023'; end if;
  else
    raise exception 'invalid_target' using errcode = '22023';
  end if;

  -- Price: the place's own Premium; both places = + the Yüklər Premium.
  select * into v_plan from place_promo_plans where target = p_target and kind = 'premium' and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;
  v_places := array(select x from unnest(array['market', 'loads']) x where x = any (p_places));
  v_amount := v_plan.price;
  if cardinality(v_places) = 2 then
    select * into v_loads from cargo_promo_plans where kind = 'premium' and qty = p_qty and is_active;
    if v_loads.kind is null or upper(v_loads.currency) <> upper(v_plan.currency) then
      raise exception 'places_not_available' using errcode = '22023';
    end if;
    v_amount := v_plan.price + v_loads.price;
  end if;

  select * into v_ord from place_promo_orders
   where target = p_target and coalesce(service_id, park_id) = p_id and user_id = v_uid and kind = 'premium' and qty = p_qty
     and status = 'pending_payment' and amount = v_amount and currency = upper(v_plan.currency) and places = v_places
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into place_promo_orders (target, service_id, park_id, user_id, kind, qty, amount, currency, places)
  values (p_target, case when p_target = 'service' then p_id end, case when p_target = 'tirpark' then p_id end,
          v_uid, 'premium', p_qty, v_amount, upper(v_plan.currency), v_places)
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.place_promo_order_create(text, uuid, text, integer, text[]) from public, anon;
grant execute on function public.place_promo_order_create(text, uuid, text, integer, text[]) to authenticated;

-- 4) Payment: Premium on its own map always (0093) + the chosen sections'
-- strips (TIR Bazarı / Yüklər; 0102 orders: their other maps).
create or replace function public._place_promo_apply(p_promo_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ord public.place_promo_orders;
  r record;
  v_left integer;
  v_vip_until timestamptz;
  v_vip_since timestamptz;
  v_prem_until timestamptz;
  v_prem_since timestamptz;
  v_bump_start timestamptz;
  v_bump_total integer;
  v_home text;
  v_place text;
begin
  update place_promo_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_promo_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  if v_ord.target = 'service' then
    select promo_vip_until vu, promo_vip_since vs, promo_premium_until pu, promo_premium_since ps,
           promo_bump_start bs, promo_bump_total bt into r
      from service_providers where id = v_ord.service_id for update;
  else
    select promo_vip_until vu, promo_vip_since vs, promo_premium_until pu, promo_premium_since ps,
           promo_bump_start bs, promo_bump_total bt into r
      from tir_parks where id = v_ord.park_id for update;
  end if;
  if not found then return; end if;
  v_vip_until := r.vu; v_vip_since := r.vs; v_prem_until := r.pu; v_prem_since := r.ps;
  v_bump_start := r.bs; v_bump_total := r.bt;

  if v_ord.kind = 'premium' and v_ord.places is not null then
    v_home := public._place_home(v_ord.target, coalesce(v_ord.service_id, v_ord.park_id));
    foreach v_place in array v_ord.places loop
      if v_place <> v_home then
        perform public._place_cross_extend(v_ord.target, coalesce(v_ord.service_id, v_ord.park_id), v_place, v_ord.qty);
      end if;
    end loop;
  end if;

  if v_ord.kind = 'bump' then
    v_left := case when coalesce(r.bt, 0) > 0 and r.bs is not null
                   then greatest(0, r.bt - (floor(extract(epoch from now() - r.bs) / 86400)::int + 1)) else 0 end;
    v_bump_start := now();
    v_bump_total := least(1000, v_left + v_ord.qty);
  elsif v_ord.kind = 'vip' then
    v_vip_since := case when r.vu > now() then r.vs else now() end;
    v_vip_until := greatest(coalesce(case when r.vu > now() then r.vu end, now()), now()) + make_interval(days => v_ord.qty);
  else
    v_prem_since := case when r.pu > now() then r.ps else now() end;
    v_prem_until := greatest(coalesce(case when r.pu > now() then r.pu end, now()), now()) + make_interval(days => v_ord.qty);
    v_vip_since := case when r.vu > now() then r.vs else now() end;
    v_vip_until := greatest(coalesce(case when r.vu > now() then r.vu end, now()), v_prem_until);
  end if;

  perform set_config('app.place_promo_trusted', '1', true);
  if v_ord.target = 'service' then
    update service_providers
       set promo_vip_until = v_vip_until, promo_vip_since = v_vip_since,
           promo_premium_until = v_prem_until, promo_premium_since = v_prem_since,
           promo_bump_start = v_bump_start, promo_bump_total = v_bump_total
     where id = v_ord.service_id;
  else
    update tir_parks
       set promo_vip_until = v_vip_until, promo_vip_since = v_vip_since,
           promo_premium_until = v_prem_until, promo_premium_since = v_prem_since,
           promo_bump_start = v_bump_start, promo_bump_total = v_bump_total
     where id = v_ord.park_id;
  end if;
  perform set_config('app.place_promo_trusted', '', true);
end $$;
revoke all on function public._place_promo_apply(uuid) from public, anon, authenticated;

-- Final check.
do $$
begin
  if not public._place_places_ok(array['loads', 'market']) or public._place_places_ok(array['parks']) then
    raise exception '0103: places check not replaced — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

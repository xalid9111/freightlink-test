-- =====================================================================
-- 0102 — Premium places for Parklar · Servislər · Mağazalar; no
-- advertising from / in Yüklər (owner, 07.11.2026).
--
-- 1) A TIR park's, a service's or a shop's Premium (0093) picks where it
--    is shown: Parklar ('parks', the TIRPark map), Servislər ('services')
--    and / or Mağazalar ('shops') — one, two or all three.
--    * The price = the chosen sections' current Premium prices for the same
--      days, added up: Parklar = the TIRPark prices (place_promo_plans
--      target 'tirpark'), Servislər and Mağazalar = the Servis prices
--      (target 'service', a shop is a service, 0097). A section without an
--      active Premium pack for those days (or with another currency) =
--      refused ('places_not_available') — no made-up price.
--    * The places are kept on the order (place_promo_orders.places); after
--      a verified payment the place is Premium in its own section only if
--      that section was chosen (premium / VIP as 0093), and in every other
--      chosen section through place_promo_cross (ends by date); that
--      section's list shows it in its "Premium" strip, a tap opens it.
--    * Its own section: a park = Parklar, a shop (spare_parts + shop_*
--      only, as ServiceProvider.isShop) = Mağazalar, any other service =
--      Servislər.
--    * İrəli çək and VIP unchanged; the 4-argument call stays (its
--      Premium = the own section, written on the order as its place).
-- 2) Yüklər takes no advertising any more: a load's own "Önə çıxar" is no
--    longer offered in the app, a load's Premium with places (0101) is
--    refused ('not_available'), and a TIR Bazarı ad's Premium cannot pick
--    Yüklər ('invalid_places'; TIR Bazarı alone works as before). A TIR
--    Bazarı ad's paid Premium is always TIR Bazarı's (an unpaid order made
--    with Yüklər before gets TIR Bazarı instead). Paid promotions run to
--    their end; nothing is deleted.
--
-- Safe: forward-only, re-runnable. One new table, one nullable column,
-- new functions, replaced functions of 0093 / 0101 (same signatures). No
-- row is changed or deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.place_promo_orders') is null or to_regclass('public.promo_cross') is null then
    raise exception '0102: run 0093_place_promotions.sql and 0101_premium_places.sql first — nothing changed';
  end if;
end $$;

-- 1) The places on the order -------------------------------------------------
alter table public.place_promo_orders add column if not exists places text[];

-- Premium of a park / service / shop in ANOTHER section. Written only by
-- the payment (definer functions below).
create table if not exists public.place_promo_cross (
  source_kind text not null check (source_kind in ('service', 'tirpark')),
  source_id uuid not null,
  place text not null check (place in ('parks', 'services', 'shops')),
  since timestamptz not null default now(),
  until timestamptz not null,
  primary key (source_kind, source_id, place)
);
create index if not exists place_promo_cross_place_idx on public.place_promo_cross (place, until desc);
alter table public.place_promo_cross enable row level security;
revoke all on public.place_promo_cross from anon, authenticated;
grant select on public.place_promo_cross to authenticated;
drop policy if exists "place_promo_cross_read" on public.place_promo_cross;
create policy "place_promo_cross_read" on public.place_promo_cross for select to authenticated using (true);

-- A shop = spare_parts and only shop kinds (ServiceProvider.isShop).
create or replace function public._service_is_shop(p_categories text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select coalesce('spare_parts' = any (p_categories), false)
     and not exists (select 1 from unnest(p_categories) c where c <> 'spare_parts' and c not like 'shop\_%');
$$;
revoke all on function public._service_is_shop(text[]) from public, anon;
grant execute on function public._service_is_shop(text[]) to authenticated;

-- The own section of a place.
create or replace function public._place_home(p_target text, p_id uuid)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select case when p_target = 'tirpark' then 'parks'
              when (select public._service_is_shop(s.categories) from service_providers s where s.id = p_id) then 'shops'
              else 'services' end;
$$;
revoke all on function public._place_home(text, uuid) from public, anon, authenticated;

-- Premium prices of a section ('parks' → the TIRPark prices, 'services' /
-- 'shops' → the Servis prices).
create or replace function public._place_section_target(p_place text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select case p_place when 'parks' then 'tirpark' when 'services' then 'service' when 'shops' then 'service' end;
$$;
revoke all on function public._place_section_target(text) from public, anon, authenticated;

-- The places: a non-empty subset of parks / services / shops, no repeats.
create or replace function public._place_places_ok(p_places text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_places is not null and cardinality(p_places) between 1 and 3
     and p_places <@ array['parks', 'services', 'shops']
     and cardinality(p_places) = (select count(distinct x) from unnest(p_places) x);
$$;
revoke all on function public._place_places_ok(text[]) from public, anon, authenticated;

create or replace function public._place_cross_extend(p_kind text, p_id uuid, p_place text, p_days integer)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into place_promo_cross (source_kind, source_id, place, since, until)
  values (p_kind, p_id, p_place, now(), now() + make_interval(days => p_days))
  on conflict (source_kind, source_id, place) do update
    set since = case when place_promo_cross.until > now() then place_promo_cross.since else now() end,
        until = greatest(place_promo_cross.until, now()) + make_interval(days => p_days);
end $$;
revoke all on function public._place_cross_extend(text, uuid, text, integer) from public, anon, authenticated;

-- 2) Premium of MY park / service / shop with its places ---------------------
create or replace function public.place_promo_order_create(p_target text, p_id uuid, p_kind text, p_qty integer, p_places text[])
returns public.place_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_s public.service_providers;
  v_p public.tir_parks;
  v_places text[];
  v_amount numeric(12,2) := 0;
  v_currency text;
  v_plan public.place_promo_plans;
  v_place text;
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

  -- The price: every chosen section's Premium pack for these days, added up.
  v_places := array(select x from unnest(array['parks', 'services', 'shops']) x where x = any (p_places));
  foreach v_place in array v_places loop
    select * into v_plan from place_promo_plans
     where target = public._place_section_target(v_place) and kind = 'premium' and qty = p_qty and is_active;
    if v_plan.kind is null or (v_currency is not null and upper(v_plan.currency) <> v_currency) then
      raise exception 'places_not_available' using errcode = '22023';
    end if;
    v_currency := upper(v_plan.currency);
    v_amount := v_amount + v_plan.price;
  end loop;

  select * into v_ord from place_promo_orders
   where target = p_target and coalesce(service_id, park_id) = p_id and user_id = v_uid and kind = 'premium' and qty = p_qty
     and status = 'pending_payment' and amount = v_amount and currency = v_currency and places = v_places
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into place_promo_orders (target, service_id, park_id, user_id, kind, qty, amount, currency, places)
  values (p_target, case when p_target = 'service' then p_id end, case when p_target = 'tirpark' then p_id end,
          v_uid, 'premium', p_qty, v_amount, v_currency, v_places)
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.place_promo_order_create(text, uuid, text, integer, text[]) from public, anon;
grant execute on function public.place_promo_order_create(text, uuid, text, integer, text[]) to authenticated;

-- The 4-argument call (0093, older app versions): İrəli çək / VIP as
-- before; Premium = its own section, with that place on the order.
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
  -- 0102: Premium always carries its places (here: its own section), so an
  -- unpaid order with other places is never re-used for it.
  if p_kind = 'premium' and p_target in ('service', 'tirpark') then
    return public.place_promo_order_create(p_target, p_id, p_kind, p_qty, array[public._place_home(p_target, p_id)]);
  end if;
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

-- 3) Payment → Premium only in the chosen places (0093 + the places) ---------
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
    -- 0102: the other chosen sections show it in their "Premium" strip.
    v_home := public._place_home(v_ord.target, coalesce(v_ord.service_id, v_ord.park_id));
    foreach v_place in array v_ord.places loop
      if v_place <> v_home then
        perform public._place_cross_extend(v_ord.target, coalesce(v_ord.service_id, v_ord.park_id), v_place, v_ord.qty);
      end if;
    end loop;
    -- Its own section not chosen: nothing changes there.
    if not (v_home = any (v_ord.places)) then return; end if;
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

-- 4) What a section's "Premium" strip shows: parks / services / shops from
-- the other sections that chose it, open ones only, around the map's
-- centre (100 km) when it is given; newest Premium first.
create or replace function public.place_cross_latest(p_place text, p_lat double precision default null,
                                                     p_lng double precision default null, p_limit integer default 12)
returns table (source_kind text, source_id uuid, name text, city text, lat double precision, lng double precision,
               shop boolean, since timestamptz, until timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select y.source_kind, y.source_id, y.name, y.city, y.lat, y.lng, y.shop, y.since, y.until
    from (
      select x.source_kind, x.source_id, s.name, s.city, s.lat, s.lng, public._service_is_shop(s.categories) shop, x.since, x.until
        from place_promo_cross x join service_providers s on s.id = x.source_id
       where x.place = p_place and x.until > now() and x.source_kind = 'service'
         and s.status = 'approved' and s.is_active and s.lat is not null and s.lng is not null
      union all
      select x.source_kind, x.source_id, p.name, p.city, p.lat, p.lng, false, x.since, x.until
        from place_promo_cross x join tir_parks p on p.id = x.source_id
       where x.place = p_place and x.until > now() and x.source_kind = 'tirpark' and p.status = 'approved'
    ) y
   where p_lat is null or p_lng is null
      or (abs(y.lat - p_lat) <= 1 and abs(y.lng - p_lng) <= 3
          and 6371 * 2 * asin(sqrt(power(sin(radians(y.lat - p_lat) / 2), 2)
              + cos(radians(p_lat)) * cos(radians(y.lat)) * power(sin(radians(y.lng - p_lng) / 2), 2))) <= 100)
   order by y.since desc
   limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;
revoke all on function public.place_cross_latest(text, double precision, double precision, integer) from public, anon;
grant execute on function public.place_cross_latest(text, double precision, double precision, integer) to authenticated;

-- 5) No advertising from / in Yüklər ----------------------------------------
-- A load's Premium with places (0101): refused.
create or replace function public.cargo_promo_order_create(p_cargo uuid, p_kind text, p_qty integer, p_places text[])
returns public.cargo_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  raise exception 'not_available' using errcode = '42501';
end $$;
revoke all on function public.cargo_promo_order_create(uuid, text, integer, text[]) from public, anon;
grant execute on function public.cargo_promo_order_create(uuid, text, integer, text[]) to authenticated;

-- A TIR Bazarı ad's Premium: Yüklər can no longer be picked; TIR Bazarı
-- alone = the 3-argument order (its own section, as before 0101).
create or replace function public.market_promo_order_create(p_listing uuid, p_kind text, p_qty integer, p_places text[])
returns public.market_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_kind = 'premium' and (p_places is null or p_places <> array['market']) then
    raise exception 'invalid_places' using errcode = '22023';
  end if;
  return public.market_promo_order_create(p_listing, p_kind, p_qty);
end $$;
revoke all on function public.market_promo_order_create(uuid, text, integer, text[]) from public, anon;
grant execute on function public.market_promo_order_create(uuid, text, integer, text[]) to authenticated;

-- A TIR Bazarı ad's paid Premium: always in TIR Bazarı (as before 0101).
create or replace function public._market_promo_apply(p_promo_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ord public.market_promo_orders;
  v_l public.market_listings;
  v_left integer;
  v_until timestamptz;
begin
  update market_promo_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_promo_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  select * into v_l from market_listings where id = v_ord.listing_id for update;
  if v_l.id is null then return; end if;
  perform set_config('app.market_trusted', '1', true);
  if v_ord.kind = 'bump' then
    v_left := case when coalesce(v_l.bump_total, 0) > 0 and v_l.bump_start is not null
                   then greatest(0, v_l.bump_total - (floor(extract(epoch from now() - v_l.bump_start) / 86400)::int + 1))
                   else 0 end;
    update market_listings set bump_start = now(), bump_total = least(1000, v_left + v_ord.qty) where id = v_l.id;
  else
    -- 0102: Yüklər shows no ads any more: a Premium is TIR Bazarı's, also
    -- an order made with Yüklər before 0102 (it gets TIR Bazarı instead).
    v_until := greatest(coalesce(case when market_premium_active(v_l.premium_until) then v_l.premium_until end, now()), now())
               + make_interval(days => v_ord.qty);
    update market_listings
       set premium_since = case when market_premium_active(premium_until) then premium_since else now() end,
           premium_until = v_until,
           is_vip = true,
           vip_until = case when is_vip and vip_until is null then null
                            else greatest(coalesce(case when market_vip_active(is_vip, vip_until) then vip_until end, now()), v_until) end
     where id = v_l.id;
  end if;
  perform set_config('app.market_trusted', '', true);
end $$;
revoke all on function public._market_promo_apply(uuid) from public, anon, authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.place_promo_order_create(text, uuid, text, integer, text[])') is null
     or to_regprocedure('public.place_cross_latest(text, double precision, double precision, integer)') is null then
    raise exception '0102: functions missing — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

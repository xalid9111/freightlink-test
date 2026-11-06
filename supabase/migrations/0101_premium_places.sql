-- =====================================================================
-- 0101 — Premium: where it is shown (owner, 07.11.2026).
-- Only for Premium (İrəli çək and VIP unchanged). The advertiser picks the
-- places: Yüklər bölməsi ('loads') and / or TIR Bazarı ('market').
-- * One place = the item's current Premium price (a load: Loads Premium;
--   a TIR Bazarı ad: TIR Bazarı Premium) — unchanged.
-- * Both places = the two sections' current Premium prices for the same
--   days, added up (owner's choice "a"): a load = cargo_promo_plans +
--   market_promo_plans; an ad = market_promo_plans + cargo_promo_plans.
--   If the other section has no active Premium pack for those days (or a
--   different currency), "both" is refused ('both_not_available') — no
--   made-up price.
-- * The places are kept on the order (places); after a verified payment
--   the item is Premium only where it was chosen: its own section as before
--   (premium_until …), the other section in promo_cross (ends by date).
-- * The old 3-argument order functions stay (own section only).
-- Safe: forward-only, re-runnable; one new table, two nullable columns,
-- new functions, two replaced internal functions. No row is changed.
-- =====================================================================

alter table public.cargo_promo_orders add column if not exists places text[];
alter table public.market_promo_orders add column if not exists places text[];

-- Premium of an item in the OTHER section (a load in TIR Bazarı, an ad in
-- Yüklər). Written only by the payment (definer functions below).
create table if not exists public.promo_cross (
  source_kind text not null check (source_kind in ('cargo', 'market')),
  source_id uuid not null,
  place text not null check (place in ('loads', 'market')),
  since timestamptz not null default now(),
  until timestamptz not null,
  primary key (source_kind, source_id, place)
);
alter table public.promo_cross enable row level security;
revoke all on public.promo_cross from anon, authenticated;
grant select on public.promo_cross to authenticated;
drop policy if exists "promo_cross_read" on public.promo_cross;
create policy "promo_cross_read" on public.promo_cross for select to authenticated using (true);

create or replace function public._promo_cross_extend(p_kind text, p_id uuid, p_place text, p_days integer)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into promo_cross (source_kind, source_id, place, since, until)
  values (p_kind, p_id, p_place, now(), now() + make_interval(days => p_days))
  on conflict (source_kind, source_id, place) do update
    set since = case when promo_cross.until > now() then promo_cross.since else now() end,
        until = greatest(promo_cross.until, now()) + make_interval(days => p_days);
end $$;
revoke all on function public._promo_cross_extend(text, uuid, text, integer) from public, anon, authenticated;

-- The places: a non-empty subset of loads / market, without repeats.
create or replace function public._promo_places_ok(p_places text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p_places is not null and cardinality(p_places) between 1 and 2
     and p_places <@ array['loads', 'market']
     and cardinality(p_places) = (select count(distinct x) from unnest(p_places) x);
$$;

-- A load's Premium with its places.
create or replace function public.cargo_promo_order_create(p_cargo uuid, p_kind text, p_qty integer, p_places text[])
returns public.cargo_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_c public.cargo;
  v_plan public.cargo_promo_plans;
  v_other public.market_promo_plans;
  v_amount numeric(12,2);
  v_places text[];
  v_ord public.cargo_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_kind <> 'premium' then return public.cargo_promo_order_create(p_cargo, p_kind, p_qty); end if;
  if not public._promo_places_ok(p_places) then raise exception 'invalid_places' using errcode = '22023'; end if;
  select * into v_c from cargo where id = p_cargo;
  if v_c.id is null or v_c.owner_id is distinct from v_uid then raise exception 'cargo_not_found' using errcode = 'P0002'; end if;
  if v_c.status <> 'new' or v_c.is_hidden then raise exception 'cargo_not_open' using errcode = '22023'; end if;
  select * into v_plan from cargo_promo_plans where kind = 'premium' and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;
  v_places := array(select x from unnest(array['loads', 'market']) x where x = any (p_places));
  v_amount := v_plan.price;
  if cardinality(v_places) = 2 then
    select * into v_other from market_promo_plans where kind = 'premium' and qty = p_qty and is_active;
    if v_other.kind is null or upper(v_other.currency) <> upper(v_plan.currency) then
      raise exception 'both_not_available' using errcode = '22023';
    end if;
    v_amount := v_plan.price + v_other.price;
  end if;

  select * into v_ord from cargo_promo_orders
   where cargo_id = p_cargo and user_id = v_uid and kind = 'premium' and qty = p_qty and status = 'pending_payment'
     and amount = v_amount and currency = upper(v_plan.currency) and places = v_places
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;
  insert into cargo_promo_orders (cargo_id, user_id, kind, qty, amount, currency, places)
  values (p_cargo, v_uid, 'premium', p_qty, v_amount, upper(v_plan.currency), v_places)
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.cargo_promo_order_create(uuid, text, integer, text[]) from public, anon;
grant execute on function public.cargo_promo_order_create(uuid, text, integer, text[]) to authenticated;

-- A TIR Bazarı ad's Premium with its places.
create or replace function public.market_promo_order_create(p_listing uuid, p_kind text, p_qty integer, p_places text[])
returns public.market_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_l public.market_listings;
  v_plan public.market_promo_plans;
  v_other public.cargo_promo_plans;
  v_amount numeric(12,2);
  v_places text[];
  v_ord public.market_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_kind <> 'premium' then return public.market_promo_order_create(p_listing, p_kind, p_qty); end if;
  if not public._promo_places_ok(p_places) then raise exception 'invalid_places' using errcode = '22023'; end if;
  select * into v_l from market_listings where id = p_listing;
  if v_l.id is null or v_l.owner_id is distinct from v_uid then raise exception 'listing_not_found' using errcode = 'P0002'; end if;
  if v_l.status <> 'active' then raise exception 'listing_not_active' using errcode = '22023'; end if;
  select * into v_plan from market_promo_plans where kind = 'premium' and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;
  v_places := array(select x from unnest(array['loads', 'market']) x where x = any (p_places));
  v_amount := v_plan.price;
  if cardinality(v_places) = 2 then
    select * into v_other from cargo_promo_plans where kind = 'premium' and qty = p_qty and is_active;
    if v_other.kind is null or upper(v_other.currency) <> upper(v_plan.currency) then
      raise exception 'both_not_available' using errcode = '22023';
    end if;
    v_amount := v_plan.price + v_other.price;
  end if;

  select * into v_ord from market_promo_orders
   where listing_id = p_listing and user_id = v_uid and kind = 'premium' and qty = p_qty and status = 'pending_payment'
     and amount = v_amount and currency = upper(v_plan.currency) and places = v_places
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;
  insert into market_promo_orders (listing_id, user_id, kind, qty, amount, currency, places)
  values (p_listing, v_uid, 'premium', p_qty, v_amount, upper(v_plan.currency), v_places)
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.market_promo_order_create(uuid, text, integer, text[]) from public, anon;
grant execute on function public.market_promo_order_create(uuid, text, integer, text[]) to authenticated;

-- Payment → Premium only in the chosen places.
create or replace function public._cargo_promo_apply(p_promo_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ord public.cargo_promo_orders;
  v_c public.cargo;
  v_left integer;
  v_until timestamptz;
begin
  update cargo_promo_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_promo_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  select * into v_c from cargo where id = v_ord.cargo_id for update;
  if v_c.id is null then return; end if;
  perform set_config('app.cargo_trusted', '1', true);
  if v_ord.kind = 'bump' then
    v_left := case when coalesce(v_c.bump_total, 0) > 0 and v_c.bump_start is not null
                   then greatest(0, v_c.bump_total - (floor(extract(epoch from now() - v_c.bump_start) / 86400)::int + 1))
                   else 0 end;
    update cargo set bump_start = now(), bump_total = least(1000, v_left + v_ord.qty) where id = v_c.id;
  else
    -- 0101: Premium in TIR Bazarı too / only (the places of the order).
    if 'market' = any (coalesce(v_ord.places, array['loads'])) then
      perform public._promo_cross_extend('cargo', v_c.id, 'market', v_ord.qty);
    end if;
    if not ('loads' = any (coalesce(v_ord.places, array['loads']))) then
      perform set_config('app.cargo_trusted', '', true);
      return;
    end if;
    v_until := greatest(coalesce(case when cargo_premium_active(v_c.premium_until) then v_c.premium_until end, now()), now())
               + make_interval(days => v_ord.qty);
    update cargo
       set premium_since = case when cargo_premium_active(premium_until) then premium_since else now() end,
           premium_until = v_until,
           is_featured = true,
           featured_until = case when is_featured and featured_until is null then null
                                 else greatest(coalesce(case when cargo_vip_active(is_featured, featured_until) then featured_until end, now()), v_until) end
     where id = v_c.id;
  end if;
  perform set_config('app.cargo_trusted', '', true);
end $$;
revoke all on function public._cargo_promo_apply(uuid) from public, anon, authenticated;

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
    -- 0101: Premium in Yüklər too / only (the places of the order).
    if 'loads' = any (coalesce(v_ord.places, array['market'])) then
      perform public._promo_cross_extend('market', v_l.id, 'loads', v_ord.qty);
    end if;
    if not ('market' = any (coalesce(v_ord.places, array['market']))) then
      perform set_config('app.market_trusted', '', true);
      return;
    end if;
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

-- What the other section shows: open loads in TIR Bazarı ('market'),
-- active ads in Yüklər ('loads'); newest Premium first.
create or replace function public.promo_cross_latest(p_place text, p_limit integer default 12)
returns table (source_kind text, source_id uuid, since timestamptz, until timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select x.source_kind, x.source_id, x.since, x.until
    from promo_cross x
   where x.place = p_place and x.until > now()
     and ((x.source_kind = 'cargo' and exists (select 1 from cargo c where c.id = x.source_id and c.status = 'new' and not c.is_hidden))
       or (x.source_kind = 'market' and exists (select 1 from market_listings l where l.id = x.source_id and l.status = 'active')))
   order by x.since desc
   limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;
revoke all on function public.promo_cross_latest(text, integer) from public, anon;
grant execute on function public.promo_cross_latest(text, integer) to authenticated;

notify pgrst, 'reload schema';

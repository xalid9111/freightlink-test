-- =====================================================================
-- 0065 — TIR Bazarı: "Satışdadır" / "Sifarişlə", wheel formula,
-- equipment, damage (owner, 25.10.2026)
--
-- New optional columns of market_listings (empty = not given, so every
-- older ad stays as it is; no row is changed):
-- * availability: 'in_stock' or 'on_order' (brought on order); empty =
--   in stock, so every older ad stays "Satışdadır".
-- * axle_formula: 4x2, 4x4, 6x2, 6x4, 6x6, 8x4.
-- * equipment: any of retarder, adr, air_conditioning, sleeper.
-- * damaged: true = "Vuruğu var", false = "Vuruğu yoxdur".
-- market_search: + p_availability, p_axle_formula, p_equipment (the ad
-- has all of them), p_damaged. Every earlier parameter is kept with the
-- same meaning, so the app already installed on phones keeps working.
--
-- Safe: forward-only, re-runnable. No row is changed or deleted; no
-- table, column, constraint, policy or grant is removed. market_search
-- is re-created with four more parameters (a function, no data); its
-- grants are set again below.
--
-- One transaction: everything below is applied together or not at all
-- (a check at the end stops it if anything is not as expected).
-- =====================================================================

begin;

-- 1. New optional columns and their rules ---------------------------------
alter table public.market_listings add column if not exists availability text;
alter table public.market_listings add column if not exists axle_formula text;
alter table public.market_listings add column if not exists equipment text[];
alter table public.market_listings add column if not exists damaged boolean;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.market_listings'::regclass
                    and conname = 'market_listings_availability_check') then
    alter table public.market_listings add constraint market_listings_availability_check
      check (availability is null or availability in ('in_stock', 'on_order'));
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.market_listings'::regclass
                    and conname = 'market_listings_axle_formula_check') then
    alter table public.market_listings add constraint market_listings_axle_formula_check
      check (axle_formula is null or axle_formula in ('4x2', '4x4', '6x2', '6x4', '6x6', '8x4'));
  end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.market_listings'::regclass
                    and conname = 'market_listings_equipment_check') then
    alter table public.market_listings add constraint market_listings_equipment_check
      check (equipment is null
             or equipment <@ array['retarder', 'adr', 'air_conditioning', 'sleeper']::text[]);
  end if;
end $$;

create index if not exists idx_market_on_order on public.market_listings (category)
  where status = 'active' and availability = 'on_order';

-- 2. Search: + the four new choices --------------------------------------
-- The 0064 version (16 parameters) is replaced by the same search with
-- four more parameters at the end.
drop function if exists public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer, text, text[], text[]);

create or replace function public.market_search(
  p_category text default null,
  p_q text default null,
  p_brand text default null,
  p_model text default null,
  p_city text default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_year_from integer default null,
  p_year_to integer default null,
  p_max_mileage integer default null,
  p_vip_only boolean default false,
  p_limit integer default 20,
  p_offset integer default 0,
  p_body_type text default null,
  p_brands text[] default null,
  p_models text[] default null,
  p_availability text default null,
  p_axle_formula text default null,
  p_equipment text[] default null,
  p_damaged boolean default null
) returns setof public.market_listings
language sql stable security invoker set search_path = public, pg_temp as $$
  select l.* from public.market_listings l
  where l.status = 'active'
    and (p_category is null or l.category = p_category)
    and (p_body_type is null or l.body_type = p_body_type)
    and (p_availability is null or coalesce(l.availability, 'in_stock') = p_availability)
    and (p_axle_formula is null or l.axle_formula = p_axle_formula)
    and (p_equipment is null or l.equipment @> p_equipment)
    and (p_damaged is null or l.damaged = p_damaged)
    and ((p_brand is null and p_brands is null)
         or lower(l.brand) = lower(p_brand)
         or public.market_name_key(l.brand) in (select public.market_name_key(x) from unnest(p_brands) x))
    and ((p_model is null and p_models is null)
         or lower(l.model) = lower(p_model)
         or public.market_name_key(l.model) in (select public.market_name_key(x) from unnest(p_models) x))
    and (p_city is null or l.city ilike '%' || p_city || '%')
    and (p_min_price is null or l.price >= p_min_price)
    and (p_max_price is null or l.price <= p_max_price)
    and (p_year_from is null or l.year >= p_year_from)
    and (p_year_to is null or l.year <= p_year_to)
    and (p_max_mileage is null or l.mileage_km <= p_max_mileage)
    and (not coalesce(p_vip_only, false) or public.market_vip_active(l.is_vip, l.vip_until))
    and (nullif(btrim(coalesce(p_q, '')), '') is null
         or l.brand ilike '%' || btrim(p_q) || '%'
         or l.model ilike '%' || btrim(p_q) || '%'
         or l.city ilike '%' || btrim(p_q) || '%'
         or (l.brand || ' ' || coalesce(l.model, '')) ilike '%' || btrim(p_q) || '%')
  order by public.market_vip_active(l.is_vip, l.vip_until) desc, l.published_at desc nulls last, l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 20), 60))
  offset greatest(0, coalesce(p_offset, 0));
$$;

revoke all on function public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer, text, text[], text[], text, text, text[], boolean) from public, anon;
grant execute on function public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer, text, text[], text[], text, text, text[], boolean) to authenticated;

-- 3. Final check: one market_search (the new one), the rules in place.
do $$
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'market_search') <> 1
     or to_regprocedure('public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer, text, text[], text[], text, text, text[], boolean)') is null
     or (select count(*) from pg_constraint where conrelid = 'public.market_listings'::regclass
          and conname in ('market_listings_availability_check', 'market_listings_axle_formula_check',
                          'market_listings_equipment_check')) <> 3 then
    raise exception '0065: final check failed — nothing changed';
  end if;
end $$;

-- PostgREST reads the new parameter list at once (sent at commit).
notify pgrst, 'reload schema';

commit;

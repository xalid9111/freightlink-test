-- =====================================================================
-- 0064 — TIR Bazarı: medium / light trucks, body type, other spellings
-- (owner, 25.10.2026, Mərhələ 2)
--
-- * market_listings.category: two more classes — 'medium_truck'
--   (3.5–16 t) and 'light_truck' (Qazel, vans, up to 3.5 t). The five
--   existing ones stay.
-- * market_listings.body_type: new, optional (tow truck, crane, reefer,
--   dump …) — apart from brand, model and category.
-- * market_search: also by body type, and by every spelling of a brand /
--   model the app sends (p_brands / p_models: "Mercedes", "КАМАЗ",
--   "FH-16" …), compared without case, spaces or punctuation. Every
--   earlier parameter is kept with the same meaning, so the app already
--   installed on phones keeps working.
--
-- Safe: forward-only, re-runnable. No row is changed or deleted; no
-- table, column, policy or grant is removed. Only the 0040 category
-- check (market_listings_category_check) is replaced, and only while it
-- is exactly the 0040 rule; every other constraint stays untouched.
-- market_search is re-created with the longer parameter list (a
-- function, no data); its grants are set again below.
-- =====================================================================

-- 1. Body type (optional) ----------------------------------------------
alter table public.market_listings add column if not exists body_type text;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.market_listings'::regclass
                    and conname = 'market_listings_body_type_check') then
    alter table public.market_listings add constraint market_listings_body_type_check
      check (body_type is null or body_type in (
        'tractor_unit', 'tent', 'ref', 'van', 'dump', 'tow_truck', 'manipulator', 'car_carrier',
        'tanker', 'open', 'lowbed', 'container', 'chassis', 'concrete_mixer', 'special'));
  end if;
end $$;

-- 2. Two more categories -------------------------------------------------
--   * already the 7-class rule  -> nothing to do (re-run is safe);
--   * exactly the 0040 rule     -> dropped and re-added with 7 classes,
--                                  in one transaction;
--   * anything else / missing   -> stop with an error, nothing changed.
do $$
declare
  v_old constant text := 'CHECK ((category = ANY (ARRAY[''truck''::text, ''trailer''::text, ''semitrailer''::text, ''construction''::text, ''other''::text])))';
  v_new constant text := 'CHECK ((category = ANY (ARRAY[''truck''::text, ''medium_truck''::text, ''light_truck''::text, ''trailer''::text, ''semitrailer''::text, ''construction''::text, ''other''::text])))';
  v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = 'public.market_listings'::regclass
     and c.conname = 'market_listings_category_check'
     and c.contype = 'c';
  if v_def = v_new then
    return;
  end if;
  if v_def is distinct from v_old then
    raise exception '0064: market_listings_category_check is not the 0040 rule (found: %) — nothing changed', coalesce(v_def, 'none');
  end if;
  alter table public.market_listings drop constraint market_listings_category_check;
  alter table public.market_listings add constraint market_listings_category_check
    check (category in ('truck', 'medium_truck', 'light_truck', 'trailer', 'semitrailer', 'construction', 'other'));
end $$;

create index if not exists idx_market_body on public.market_listings (category, body_type)
  where status = 'active' and body_type is not null;

-- 3. Spellings compared without case, spaces or punctuation -------------
-- "FH-16" = "FH16", "TGX18.480" = "TGX 18.480", "Mercedes Benz" = "mercedes-benz".
create or replace function public.market_name_key(p text)
returns text language sql immutable parallel safe set search_path = public, pg_temp as $$
  select lower(regexp_replace(coalesce(p, ''), '[[:space:]./_-]+', '', 'g'));
$$;

-- 4. Search: + body type, + every spelling of the brand / model ----------
drop function if exists public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer);

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
  p_models text[] default null
) returns setof public.market_listings
language sql stable security invoker set search_path = public, pg_temp as $$
  select l.* from public.market_listings l
  where l.status = 'active'
    and (p_category is null or l.category = p_category)
    and (p_body_type is null or l.body_type = p_body_type)
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

revoke all on function public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer, text, text[], text[]) from public, anon;
grant execute on function public.market_search(text, text, text, text, text, numeric, numeric, integer, integer, integer, boolean, integer, integer, text, text[], text[]) to authenticated;
revoke all on function public.market_name_key(text) from public, anon;
grant execute on function public.market_name_key(text) to authenticated;

-- PostgREST reads the new parameter list at once.
notify pgrst, 'reload schema';

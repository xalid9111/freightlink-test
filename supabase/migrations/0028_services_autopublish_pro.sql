-- =====================================================================
-- 0028 — Services: published at once, PRO services
--
-- 1) A new service profile is published immediately (status 'approved')
--    — no waiting for the admin. The admin can still reject / suspend it
--    afterwards (Admin → Servislər). Owners still cannot change status,
--    verification, PRO or rating themselves.
-- 2) PRO service (is_pro): set only by the admin; shown with a gold "PRO"
--    badge and listed first. It is a label, not a rating — stars still
--    come only from real reviews.
--
-- Safe: forward-only, re-runnable; one new column with a default. No row
-- is changed or deleted (existing 'pending' profiles stay as they are —
-- approve them in Admin → Servislər or with the one-line SQL in the notes).
-- =====================================================================

alter table public.service_providers add column if not exists is_pro boolean not null default false;
-- 0018 grants SELECT column by column: the new column must be added.
grant select (is_pro) on table public.service_providers to authenticated;

create or replace function public.guard_service_provider()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  if current_user not in ('anon', 'authenticated') then
    return new;                       -- trusted server-side caller
  end if;
  if public.is_admin() then
    return new;                       -- admin using the API directly
  end if;
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if public.is_blocked(auth.uid()) then
    raise exception 'account_blocked' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'approved';         -- 0028: published at once, no waiting
    new.is_verified := false;
    new.is_pro := false;
    new.added_by_admin := false;
    new.admin_note := null;
    new.rating_avg := 0;
    new.rating_count := 0;
    new.created_at := now();
    new.updated_at := now();
  else
    new.id := old.id;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.is_verified := old.is_verified;
    new.is_pro := old.is_pro;
    new.added_by_admin := old.added_by_admin;
    new.admin_note := old.admin_note;
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
    new.created_at := old.created_at;
  end if;

  -- Only known categories are kept (unchanged from 0017).
  new.categories := coalesce(array(
    select distinct c from unnest(new.categories) c
    where exists (select 1 from public.service_categories sc where sc.id = c)
  ), '{}');
  return new;
end;
$$;

create or replace function public.nearby_services(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 100,
  p_category text default null,
  p_min_rating numeric default 0,
  p_only_active boolean default false,
  p_kind text default null,
  p_query text default null,
  p_limit integer default 200
) returns jsonb
language sql stable security invoker set search_path = public, pg_temp as $$
  with params as (
    select greatest(1, least(coalesce(p_radius_km, 100), 3000))::double precision as r,
           greatest(1, least(coalesce(p_limit, 200), 500)) as lim,
           nullif(btrim(coalesce(p_query, '')), '') as q
  ), box as (
    select r, lim, q,
           r / 111.0 as dlat,
           r / (111.0 * greatest(cos(radians(p_lat)), 0.02)) as dlng
    from params
  ), hits as (
    select s.id, s.owner_id, s.kind, s.name, s.specialty, s.description, s.categories,
           s.country, s.city, s.address, s.lat, s.lng, s.is_mobile, s.service_radius_km,
           s.phone, s.whatsapp, s.working_hours, s.is_24h, s.is_active, s.status,
           s.is_verified, s.is_pro, s.added_by_admin, s.photos, s.rating_avg, s.rating_count,
           s.created_at, s.updated_at,
           2 * 6371 * asin(sqrt(
             power(sin(radians(s.lat - p_lat) / 2), 2) +
             cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2)
           )) as distance_km
    from public.service_providers s, box b
    where s.status = 'approved'
      and s.lat between p_lat - b.dlat and p_lat + b.dlat
      and (b.dlng >= 180 or s.lng between p_lng - b.dlng and p_lng + b.dlng)
      and (p_category is null or p_category = any(s.categories))
      and (p_kind is null or s.kind = p_kind)
      and s.rating_avg >= coalesce(p_min_rating, 0)
      and (not coalesce(p_only_active, false) or s.is_active)
      and (s.owner_id is null or not public.is_blocked(s.owner_id))
      and (b.q is null or s.name ilike '%' || b.q || '%' or s.city ilike '%' || b.q || '%'
           or s.specialty ilike '%' || b.q || '%')
  )
  select coalesce(jsonb_agg(to_jsonb(h) order by h.distance_km), '[]'::jsonb)
  from (
    select h.* from hits h, box b
    where h.distance_km <= b.r
    order by h.distance_km
    limit (select lim from box)
  ) h;
$$;

create or replace function public.admin_set_service_pro(p_id uuid, p_pro boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  update public.service_providers set is_pro = coalesce(p_pro, false) where id = p_id;
  if not found then raise exception 'service_not_found'; end if;
  perform public._admin_log(case when p_pro then 'service.pro_on' else 'service.pro_off' end,
    'service', p_id::text, null, jsonb_build_object('is_pro', p_pro));
end;
$$;
revoke all on function public.admin_set_service_pro(uuid, boolean) from public, anon;
grant execute on function public.admin_set_service_pro(uuid, boolean) to authenticated;

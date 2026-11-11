-- =====================================================================
-- 0117 — TIRPark: truck parking from OpenStreetMap ("Xəritə məlumatı")
-- (owner, 11.11.2026)
--
-- * Azerbaijan: ONLY the platform's own parks (tir_parks) — no OSM object
--   with country AZ is ever stored (check constraint + the import refuses
--   it; the import script also drops points inside Azerbaijan's border).
-- * Europe and Asia: OpenStreetMap objects tagged for lorries (amenity =
--   parking / highway = rest_area | services with hgv = yes | designated)
--   are brought in bulk from Geofabrik's regional extracts by the GitHub
--   workflow "OSM truck parks" (monthly, scripts/osm_truck_parks). Users
--   never ask an outside API: the map reads this table.
-- * Kept apart from tir_parks on purpose: no booking, no management, no
--   reviews, no promotion, no favourites can ever reach these rows — they
--   are map data, not parks checked by the platform.
-- * One row per OSM object (source_id = 'node/123' | 'way/123' |
--   'relation/123', the primary key): a new import updates the row, never
--   makes a second one. An object the source no longer has is not deleted:
--   rows not seen for 120 days simply stop showing; an admin can hide one.
-- * Only what the source says is kept (name + a short list of OSM tags);
--   nothing is made up. Data © OpenStreetMap contributors, ODbL 1.0.
-- * The map reads one screen at a time (osm_truck_parks_in_bounds, at most
--   400 rows, only for a small enough area), so many markers never slow the
--   app; an OSM object within 150 m of an approved platform park is not
--   shown (the platform park stands there).
--
-- Safe: forward-only, re-runnable. Two new tables, new functions. No
-- existing table, row or function is changed.
-- =====================================================================

begin;

create table if not exists public.osm_truck_parks (
  source_id text primary key check (source_id ~ '^(node|way|relation)/[0-9]{1,15}$'),
  country_code text not null check (country_code ~ '^[A-Z]{2}$' and country_code <> 'AZ'),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  name text check (name is null or char_length(name) between 1 and 120),
  tags jsonb not null default '{}'::jsonb check (jsonb_typeof(tags) = 'object'),
  hidden boolean not null default false,
  hidden_by uuid references public.users(id) on delete set null,
  hidden_at timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists osm_truck_parks_geo_idx on public.osm_truck_parks (lat, lng);
create index if not exists osm_truck_parks_country_idx on public.osm_truck_parks (country_code);

-- One row per import of one country (what the admin page shows).
create table if not exists public.osm_truck_park_imports (
  id bigint generated always as identity primary key,
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  source text not null check (char_length(source) between 1 and 40),
  data_date text check (data_date is null or char_length(data_date) <= 40),
  rows_in integer not null default 0,
  rows_new integer not null default 0,
  run_at timestamptz not null default now()
);
create index if not exists osm_truck_park_imports_run_idx on public.osm_truck_park_imports (run_at desc);

-- No direct access for the app: it reads through the functions below.
alter table public.osm_truck_parks enable row level security;
alter table public.osm_truck_park_imports enable row level security;
revoke all on public.osm_truck_parks from anon, authenticated;
revoke all on public.osm_truck_park_imports from anon, authenticated;

-- Only these OSM tags are kept (short values), everything else is dropped.
create or replace function public._osm_park_tags(p jsonb)
returns jsonb language sql immutable set search_path = public, pg_temp as $$
  select coalesce(jsonb_object_agg(k, left(v, 120)), '{}'::jsonb)
    from jsonb_each_text(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) as e(k, v)
   where k in ('operator', 'fee', 'opening_hours', 'capacity:hgv', 'toilets', 'shower',
               'supervised', 'lit', 'maxstay', 'hgv', 'kind')
     and btrim(v) <> '';
$$;

-- The import (GitHub workflow, Supabase SQL API / service role only): one
-- country, up to 5000 rows a call, upserted by source_id. Never AZ.
create or replace function public.osm_truck_parks_upsert(
  p_country text, p_rows jsonb, p_source text default 'geofabrik', p_data_date text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_cc text := upper(btrim(coalesce(p_country, '')));
  v_in integer := 0;
  v_new integer := 0;
  r jsonb;
  v_lat double precision;
  v_lng double precision;
  v_id text;
  v_name text;
  v_inserted boolean;
begin
  if auth.uid() is not null then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_cc !~ '^[A-Z]{2}$' then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if v_cc = 'AZ' then raise exception 'not_allowed_az' using errcode = '42501'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) > 5000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    v_id := r ->> 'id';
    v_lat := (r ->> 'lat')::double precision;
    v_lng := (r ->> 'lng')::double precision;
    if v_id is null or v_id !~ '^(node|way|relation)/[0-9]{1,15}$'
       or v_lat is null or v_lng is null or abs(v_lat) > 90 or abs(v_lng) > 180 then
      continue;
    end if;
    v_name := nullif(left(btrim(coalesce(r ->> 'name', '')), 120), '');
    insert into osm_truck_parks as o (source_id, country_code, lat, lng, name, tags)
    values (v_id, v_cc, v_lat, v_lng, v_name, public._osm_park_tags(r -> 'tags'))
    on conflict (source_id) do update
      set country_code = excluded.country_code, lat = excluded.lat, lng = excluded.lng,
          name = excluded.name, tags = excluded.tags, last_seen_at = now()
    returning (xmax = 0) into v_inserted;
    v_in := v_in + 1;
    if v_inserted then v_new := v_new + 1; end if;
  end loop;
  insert into osm_truck_park_imports (country_code, source, data_date, rows_in, rows_new)
  values (v_cc, left(coalesce(nullif(btrim(p_source), ''), 'geofabrik'), 40), left(p_data_date, 40), v_in, v_new);
  return jsonb_build_object('rows', v_in, 'new', v_new);
end $$;
revoke all on function public.osm_truck_parks_upsert(text, jsonb, text, text) from public, anon, authenticated;
grant execute on function public.osm_truck_parks_upsert(text, jsonb, text, text) to service_role;

-- The map: OSM objects inside one screen (south, west, north, east). Too
-- big an area → nothing (the app asks only from zoom 7 on). At most 400,
-- spread evenly (stable order); 'more' = there were more than that.
create or replace function public.osm_truck_parks_in_bounds(
  p_south double precision, p_west double precision, p_north double precision, p_east double precision,
  p_limit integer default 400)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 400), 1), 400);
  v_items jsonb;
  v_count integer;
begin
  if p_south is null or p_west is null or p_north is null or p_east is null
     or p_south > p_north or p_west > p_east
     or abs(p_south) > 90 or abs(p_north) > 90 or abs(p_west) > 180 or abs(p_east) > 180 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if p_north - p_south > 12 or p_east - p_west > 24 then
    return jsonb_build_object('items', '[]'::jsonb, 'more', true);
  end if;
  with hits as (
    select o.source_id, o.lat, o.lng, o.name, o.tags
      from osm_truck_parks o
     where not o.hidden
       and o.last_seen_at > now() - interval '120 days'
       and o.lat between p_south and p_north
       and o.lng between p_west and p_east
       and not exists (
         select 1 from tir_parks t
          where t.status = 'approved'
            and t.lat between o.lat - 0.002 and o.lat + 0.002
            and t.lng between o.lng - 0.004 and o.lng + 0.004
            and public.tir_park_distance_m(o.lat, o.lng, t.lat, t.lng) < 150)
     order by md5(o.source_id)
     limit v_limit + 1),
  numbered as (select h.*, row_number() over (order by md5(h.source_id)) rn from hits h)
  select coalesce(jsonb_agg(jsonb_build_object('id', n.source_id, 'lat', n.lat, 'lng', n.lng,
                                               'name', n.name, 'tags', n.tags) order by n.rn)
                  filter (where n.rn <= v_limit), '[]'::jsonb),
         count(*)
    into v_items, v_count
    from numbered n;
  return jsonb_build_object('items', v_items, 'more', v_count > v_limit);
end $$;
revoke all on function public.osm_truck_parks_in_bounds(double precision, double precision, double precision, double precision, integer) from public;
grant execute on function public.osm_truck_parks_in_bounds(double precision, double precision, double precision, double precision, integer) to anon, authenticated;

-- Admins: hide / show one object (a wrong place), logged.
create or replace function public.admin_osm_park_set_hidden(p_source_id text, p_hidden boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old osm_truck_parks;
begin
  perform public._require_admin();
  select * into v_old from osm_truck_parks where source_id = p_source_id;
  if v_old.source_id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  update osm_truck_parks
     set hidden = coalesce(p_hidden, false),
         hidden_by = case when coalesce(p_hidden, false) then auth.uid() end,
         hidden_at = case when coalesce(p_hidden, false) then now() end
   where source_id = p_source_id;
  perform public._admin_log(case when coalesce(p_hidden, false) then 'osm_park.hide' else 'osm_park.show' end,
    'osm_truck_parks', p_source_id, jsonb_build_object('hidden', v_old.hidden),
    jsonb_build_object('hidden', coalesce(p_hidden, false), 'name', v_old.name, 'country', v_old.country_code));
end $$;
revoke all on function public.admin_osm_park_set_hidden(text, boolean) from public, anon;
grant execute on function public.admin_osm_park_set_hidden(text, boolean) to authenticated;

-- Admins: how much map data there is and when each country was last brought in.
create or replace function public.admin_osm_parks_status()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  return jsonb_build_object(
    'total', (select count(*) from osm_truck_parks),
    'shown', (select count(*) from osm_truck_parks where not hidden and last_seen_at > now() - interval '120 days'),
    'hidden', (select count(*) from osm_truck_parks where hidden),
    'last_run', (select max(run_at) from osm_truck_park_imports),
    'countries', coalesce((
      select jsonb_agg(jsonb_build_object('country', c.country_code, 'count', c.n, 'last_run', c.last_run)
                       order by c.country_code)
        from (select p.country_code, count(*) n,
                     (select max(i.run_at) from osm_truck_park_imports i where i.country_code = p.country_code) last_run
                from osm_truck_parks p group by p.country_code) c), '[]'::jsonb));
end $$;
revoke all on function public.admin_osm_parks_status() from public, anon;
grant execute on function public.admin_osm_parks_status() to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.osm_truck_parks') is null
     or to_regclass('public.osm_truck_park_imports') is null
     or to_regprocedure('public.osm_truck_parks_upsert(text, jsonb, text, text)') is null
     or to_regprocedure('public.osm_truck_parks_in_bounds(double precision, double precision, double precision, double precision, integer)') is null
     or to_regprocedure('public.admin_osm_park_set_hidden(text, boolean)') is null
     or to_regprocedure('public.admin_osm_parks_status()') is null then
    raise exception '0117: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

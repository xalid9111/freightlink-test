-- =====================================================================
-- 0077 — TIRPark: TIR parks on the map (owner, 31.10.2026, PR 1)
--
-- The bottom-bar tab "Servislər" becomes "TIRPark" (Servislər stays, opened
-- from TIRPark). Drivers add the parks they find on the road; an admin
-- approves them.
--
-- * tir_parks: name, place on the map (lat / lng), city, amenities, status.
--   A park added by a user starts as 'pending' and is seen only by him and
--   the admins; after approval ('approved') everybody signed in sees it.
--   'rejected' / 'hidden' are kept (nothing is deleted), seen by admins.
-- * Before adding, the app asks tir_parks_near(): parks within the radius
--   (approved ones, and anybody's pending ones by name only) so the same
--   park is not added twice. tir_park_add() refuses a park closer than
--   60 m to an existing one (duplicate) and more than 10 parks a day.
-- * The author edits his park while it is pending; status, author and
--   rating are set only by the server. An admin approves / rejects /
--   hides (admin_tir_park_set_status, checked on the server, logged).
-- * rating_avg / rating_count / photo_urls are filled by PR 2 (reviews,
--   pictures); they start empty.
--
-- Safe: forward-only, re-runnable. One new table, new functions. No
-- existing table or row is changed or deleted.
-- =====================================================================

begin;

create or replace function public.tir_park_amenities_valid(p text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p is not null
     and cardinality(p) <= 12
     and p <@ array['secure', '24_7', 'food', 'shower', 'wc', 'fuel', 'wifi', 'repair', 'lighting', 'camera', 'free', 'paid']::text[];
$$;

create table if not exists public.tir_parks (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 80),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  city text check (city is null or char_length(city) <= 80),
  amenities text[] not null default '{}' check (public.tir_park_amenities_valid(amenities)),
  note text check (note is null or char_length(note) <= 500),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'hidden')),
  photo_urls text[] not null default '{}' check (cardinality(photo_urls) <= 10),
  rating_avg numeric(3,2) not null default 0,
  rating_count integer not null default 0,
  created_by uuid default auth.uid() references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz
);
create index if not exists tir_parks_status_idx on public.tir_parks (status);
create index if not exists tir_parks_geo_idx on public.tir_parks (lat, lng);

alter table public.tir_parks enable row level security;
revoke all on public.tir_parks from anon, authenticated;
grant select, update on public.tir_parks to authenticated;

-- Approved parks for everybody signed in; one's own (any state); admins all.
drop policy if exists "tir_parks_select" on public.tir_parks;
create policy "tir_parks_select" on public.tir_parks
  for select to authenticated
  using (status = 'approved' or created_by = auth.uid() or public.is_admin());

-- The author edits his park while it waits for approval; admins always.
drop policy if exists "tir_parks_update" on public.tir_parks;
create policy "tir_parks_update" on public.tir_parks
  for update to authenticated
  using ((created_by = auth.uid() and status = 'pending') or public.is_admin())
  with check ((created_by = auth.uid() and status = 'pending') or public.is_admin());

-- Status, author, rating and review fields are the server's: a user's
-- update keeps them as they were (an admin changes status only through
-- admin_tir_park_set_status, which sets app.tir_park_admin).
create or replace function public.tir_parks_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' then
    if coalesce(current_setting('app.tir_park_admin', true), 'off') <> 'on' then
      new.status := old.status;
      new.reviewed_by := old.reviewed_by;
      new.reviewed_at := old.reviewed_at;
    end if;
    if coalesce(current_setting('app.tir_park_rating', true), 'off') <> 'on' then
      new.rating_avg := old.rating_avg;
      new.rating_count := old.rating_count;
    end if;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;
  return new;
end $$;
drop trigger if exists tir_parks_guard on public.tir_parks;
create trigger tir_parks_guard before update on public.tir_parks
  for each row execute function public.tir_parks_guard();

-- Distance in metres (haversine; no extension needed).
create or replace function public.tir_park_distance_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable set search_path = public, pg_temp as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- Before adding: parks near the chosen place (not rejected / hidden), so
-- the same park is not added twice. Other people's pending parks show
-- only their name, place and state.
create or replace function public.tir_parks_near(p_lat double precision, p_lng double precision, p_radius_m integer default 500)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'lat', t.lat, 'lng', t.lng,
                                        'status', t.status, 'distance_m', round(t.d)::int) order by t.d)
      from (select p.*, public.tir_park_distance_m(p_lat, p_lng, p.lat, p.lng) d
              from tir_parks p
             where p.status in ('approved', 'pending')
               and p.lat between p_lat - 0.1 and p_lat + 0.1) t
     where t.d <= least(greatest(coalesce(p_radius_m, 500), 10), 5000)), '[]'::jsonb);
end $$;
revoke all on function public.tir_parks_near(double precision, double precision, integer) from public, anon;
grant execute on function public.tir_parks_near(double precision, double precision, integer) to authenticated;

-- Add a park (starts pending). Refused: closer than 60 m to an existing
-- park ('duplicate_nearby'), more than 10 a day ('too_many'), blocked users.
create or replace function public.tir_park_add(
  p_name text, p_lat double precision, p_lng double precision,
  p_city text default null, p_amenities text[] default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if exists (select 1 from tir_parks p
              where p.status in ('approved', 'pending')
                and p.lat between p_lat - 0.01 and p_lat + 0.01
                and public.tir_park_distance_m(p_lat, p_lng, p.lat, p.lng) < 60) then
    raise exception 'duplicate_nearby' using errcode = '23505';
  end if;
  if (select count(*) from tir_parks where created_by = v_uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  insert into tir_parks (name, lat, lng, city, amenities, note, created_by)
  values (btrim(p_name), p_lat, p_lng, nullif(btrim(coalesce(p_city, '')), ''), coalesce(p_amenities, '{}'),
          nullif(btrim(coalesce(p_note, '')), ''), v_uid)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.tir_park_add(text, double precision, double precision, text, text[], text) from public, anon;
grant execute on function public.tir_park_add(text, double precision, double precision, text, text[], text) to authenticated;

-- Admins: approve / reject / hide (logged).
create or replace function public.admin_tir_park_set_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old tir_parks;
begin
  perform public._require_admin();
  if p_status not in ('pending', 'approved', 'rejected', 'hidden') then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  select * into v_old from tir_parks where id = p_id;
  if v_old.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform set_config('app.tir_park_admin', 'on', true);
  update tir_parks set status = p_status, reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
  perform set_config('app.tir_park_admin', 'off', true);
  perform public._admin_log('tir_park.' || p_status, 'tir_parks', p_id::text,
    jsonb_build_object('status', v_old.status), jsonb_build_object('status', p_status, 'name', v_old.name));
end $$;
revoke all on function public.admin_tir_park_set_status(uuid, text) from public, anon;
grant execute on function public.admin_tir_park_set_status(uuid, text) to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.tir_parks') is null
     or to_regprocedure('public.tir_park_add(text, double precision, double precision, text, text[], text)') is null
     or to_regprocedure('public.tir_parks_near(double precision, double precision, integer)') is null
     or to_regprocedure('public.admin_tir_park_set_status(uuid, text)') is null then
    raise exception '0077: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

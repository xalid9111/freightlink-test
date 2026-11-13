-- =====================================================================
-- 0118 — "Daşıyıcılar": empty truck ads on Yüklər (owner, 13.11.2026)
--
-- A carrier says where his truck stands now and where it is going (or "any
-- direction"), the truck, how many tonnes are free, from when, and how to
-- reach him. Yüklər gets a "Yüklər | Daşıyıcılar" switch; loads stay exactly
-- as they are (cargo is not touched).
--
-- * Its own table empty_truck_ads (a separate kind, never mixed with cargo;
--   the old fleet table "trucks" is a different thing and is not used).
-- * Anyone may read the active ads (visitors too, but without the phone /
--   WhatsApp columns — the app shows "sign in to contact"). An owner reads
--   all of his own ads; admins all.
-- * The owner creates, edits, pauses ("paused"), re-activates and closes
--   ("filled" = Maşın doldu) his own ads; nothing is deleted. Admins may
--   change any ad's status (logged).
-- * The server checks every field (places, tonnes, types, phone, time).
--
-- Safe: forward-only, re-runnable. One new table, new functions. No
-- existing table, row or function is changed.
-- =====================================================================

begin;

create table if not exists public.empty_truck_ads (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.users(id) on delete cascade,
  -- Where the truck is now: city + country (English names as on loads,
  -- ISO code for the flag), the map point only when the owner chose one.
  from_city text not null check (char_length(btrim(from_city)) between 1 and 80),
  from_country text not null check (char_length(btrim(from_country)) between 2 and 60),
  from_code text check (from_code is null or from_code ~ '^[A-Z]{2}$'),
  from_lat double precision check (from_lat is null or from_lat between -90 and 90),
  from_lng double precision check (from_lng is null or from_lng between -180 and 180),
  -- Where it is going, or any direction.
  any_direction boolean not null default false,
  to_city text check (to_city is null or char_length(btrim(to_city)) between 1 and 80),
  to_country text check (to_country is null or char_length(btrim(to_country)) between 2 and 60),
  to_code text check (to_code is null or to_code ~ '^[A-Z]{2}$'),
  -- The truck: type code (as on loads), free tonnes, suitable load / body kinds.
  truck_type text not null check (char_length(btrim(truck_type)) between 1 and 30),
  free_tons numeric(6,2) not null check (free_tons > 0 and free_tons <= 100),
  body_types text[] not null default '{}' check (cardinality(body_types) <= 12),
  -- Free from (null = now).
  available_from timestamptz,
  phone text check (phone is null or phone ~ '^\+?[0-9 ()-]{6,24}$'),
  whatsapp text check (whatsapp is null or whatsapp ~ '^\+?[0-9 ()-]{6,24}$'),
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'active' check (status in ('active', 'paused', 'filled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint empty_truck_direction check (any_direction or (to_city is not null and to_country is not null))
);
create index if not exists empty_truck_ads_feed_idx on public.empty_truck_ads (status, created_at desc);
create index if not exists empty_truck_ads_owner_idx on public.empty_truck_ads (owner_id, created_at desc);

alter table public.empty_truck_ads enable row level security;
revoke all on public.empty_truck_ads from anon, authenticated;
grant select on public.empty_truck_ads to authenticated;
-- Visitors: every column but the contact numbers.
grant select (id, owner_id, from_city, from_country, from_code, from_lat, from_lng, any_direction, to_city, to_country,
              to_code, truck_type, free_tons, body_types, available_from, note, status, created_at, updated_at)
  on public.empty_truck_ads to anon;

drop policy if exists "empty_truck_ads_select" on public.empty_truck_ads;
create policy "empty_truck_ads_select" on public.empty_truck_ads
  for select to authenticated
  using (status = 'active' or owner_id = auth.uid() or public.is_admin());
drop policy if exists "empty_truck_ads_select_guest" on public.empty_truck_ads;
create policy "empty_truck_ads_select_guest" on public.empty_truck_ads
  for select to anon
  using (status = 'active');

-- Create or edit one's own ad (p_id null = new). Returns the id.
create or replace function public.empty_truck_save(
  p_id uuid,
  p_from_city text, p_from_country text, p_from_code text, p_from_lat double precision, p_from_lng double precision,
  p_any_direction boolean, p_to_city text, p_to_country text, p_to_code text,
  p_truck_type text, p_free_tons numeric, p_body_types text[], p_available_from timestamptz,
  p_phone text, p_whatsapp text, p_note text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_any boolean := coalesce(p_any_direction, false);
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_from_city, '')), '') is null or nullif(btrim(coalesce(p_from_country, '')), '') is null then
    raise exception 'from_required' using errcode = '22023';
  end if;
  if not v_any and (nullif(btrim(coalesce(p_to_city, '')), '') is null or nullif(btrim(coalesce(p_to_country, '')), '') is null) then
    raise exception 'to_required' using errcode = '22023';
  end if;
  if p_free_tons is null or p_free_tons <= 0 or p_free_tons > 100 then
    raise exception 'invalid_tons' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_truck_type, '')), '') is null then
    raise exception 'truck_required' using errcode = '22023';
  end if;
  if p_available_from is not null and p_available_from < now() - interval '1 day' then
    raise exception 'invalid_time' using errcode = '22023';
  end if;
  if p_id is null then
    if (select count(*) from empty_truck_ads where owner_id = v_uid and created_at > now() - interval '1 day') >= 20 then
      raise exception 'too_many' using errcode = '54000';
    end if;
    insert into empty_truck_ads (owner_id, from_city, from_country, from_code, from_lat, from_lng, any_direction,
                                 to_city, to_country, to_code, truck_type, free_tons, body_types, available_from,
                                 phone, whatsapp, note)
    values (v_uid, btrim(p_from_city), btrim(p_from_country), upper(nullif(btrim(p_from_code), '')), p_from_lat, p_from_lng, v_any,
            case when v_any then null else btrim(p_to_city) end,
            case when v_any then null else btrim(p_to_country) end,
            case when v_any then null else upper(nullif(btrim(p_to_code), '')) end,
            btrim(p_truck_type), p_free_tons, coalesce(p_body_types, '{}'), p_available_from,
            nullif(btrim(p_phone), ''), nullif(btrim(p_whatsapp), ''), nullif(btrim(p_note), ''))
    returning id into v_id;
    return v_id;
  end if;
  update empty_truck_ads
     set from_city = btrim(p_from_city), from_country = btrim(p_from_country), from_code = upper(nullif(btrim(p_from_code), '')),
         from_lat = p_from_lat, from_lng = p_from_lng, any_direction = v_any,
         to_city = case when v_any then null else btrim(p_to_city) end,
         to_country = case when v_any then null else btrim(p_to_country) end,
         to_code = case when v_any then null else upper(nullif(btrim(p_to_code), '')) end,
         truck_type = btrim(p_truck_type), free_tons = p_free_tons, body_types = coalesce(p_body_types, '{}'),
         available_from = p_available_from, phone = nullif(btrim(p_phone), ''), whatsapp = nullif(btrim(p_whatsapp), ''),
         note = nullif(btrim(p_note), ''), updated_at = now()
   where id = p_id and owner_id = v_uid
  returning id into v_id;
  if v_id is null then raise exception 'not_allowed' using errcode = '42501'; end if;
  return v_id;
end $$;
revoke all on function public.empty_truck_save(uuid, text, text, text, double precision, double precision, boolean, text, text, text,
  text, numeric, text[], timestamptz, text, text, text) from public, anon;
grant execute on function public.empty_truck_save(uuid, text, text, text, double precision, double precision, boolean, text, text, text,
  text, numeric, text[], timestamptz, text, text, text) to authenticated;

-- Pause / re-activate / "Maşın doldu": the owner on his ad; admins on any (logged).
create or replace function public.empty_truck_set_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old empty_truck_ads;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_status not in ('active', 'paused', 'filled') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select * into v_old from empty_truck_ads where id = p_id;
  if v_old.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_old.owner_id is distinct from auth.uid() and not public.is_admin() then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update empty_truck_ads set status = p_status, updated_at = now() where id = p_id;
  if v_old.owner_id is distinct from auth.uid() then
    perform public._admin_log('empty_truck.' || p_status, 'empty_truck_ads', p_id::text,
      jsonb_build_object('status', v_old.status), jsonb_build_object('status', p_status));
  end if;
end $$;
revoke all on function public.empty_truck_set_status(uuid, text) from public, anon;
grant execute on function public.empty_truck_set_status(uuid, text) to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.empty_truck_ads') is null
     or to_regprocedure('public.empty_truck_save(uuid, text, text, text, double precision, double precision, boolean, text, text, text, text, numeric, text[], timestamptz, text, text, text)') is null
     or to_regprocedure('public.empty_truck_set_status(uuid, text)') is null then
    raise exception '0118: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

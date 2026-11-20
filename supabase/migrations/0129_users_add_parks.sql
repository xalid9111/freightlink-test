-- =====================================================================
-- 0129 — Users add TIR parks again (owner, 20.11.2026: "TIR parkı əlavə et
-- bölməsində istifadəçilər park əlavə edə bilsin").
-- "TIR parkı əlavə et +" on the Xəritə tab: the user moves the map so the
-- place is under the pin, writes the name (city, amenities, a note) and
-- the park is shown on the map at once — the rules of 0099 come back:
--   * signed in, not blocked; a real place (lat / lng in range);
--   * a park closer than 60 m to an existing one is refused;
--   * at most 10 parks a day per user;
--   * published at once (status 'approved'), the admin can still hide it.
-- 0100 had switched this off (every call refused). The park management system
-- (owner panel, workers, bookings) is switched off in the app; nothing of
-- it is touched here.
-- Safe: forward-only, re-runnable; one replaced function, no table or row
-- changed or deleted.
-- =====================================================================

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
  if length(btrim(coalesce(p_name, ''))) < 2 or length(btrim(p_name)) > 80 then
    raise exception 'name_required' using errcode = '22023';
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
  insert into tir_parks (name, lat, lng, city, amenities, note, created_by, status, reviewed_at)
  values (btrim(p_name), p_lat, p_lng, nullif(btrim(coalesce(p_city, '')), ''), coalesce(p_amenities, '{}'),
          nullif(btrim(coalesce(p_note, '')), ''), v_uid, 'approved', now())
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.tir_park_add(text, double precision, double precision, text, text[], text) from public, anon;
grant execute on function public.tir_park_add(text, double precision, double precision, text, text[], text) to authenticated;

notify pgrst, 'reload schema';

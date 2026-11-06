-- =====================================================================
-- 0099 — No admin approval for services, shops and parking spots (owner,
-- 06.11.2026). The admin approves only "Park işlədirəm" (the park owner's
-- request, tir_park_owner_requests / manager applications — unchanged).
--
-- 1) Services / shops: a last trigger (zz_service_publish) publishes every
--    profile its owner makes or saves, whatever older guard functions do
--    (a re-run of an old migration such as 0018 cannot bring the waiting
--    back). Rejected / suspended stay as the admin set them; the admin and
--    trusted server code keep full control.
-- 2) Services / shops waiting now ('pending') are published once.
-- 3) "Dayanacaq əlavə et" (tir_park_add): the spot is shown at once.
-- 4) Spots waiting now (pending, NO manager application) are published
--    once; a park with a manager application keeps waiting for the admin.
-- Safe: forward-only, re-runnable; nothing is deleted. Only 'pending' rows
-- change to 'approved' as described above.
-- =====================================================================

-- 1) Services / shops: published without the admin.
create or replace function public.service_publish_guard()
returns trigger language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user not in ('anon', 'authenticated') or auth.uid() is null or public.is_admin() then
    return new;                                  -- trusted server code / admin
  end if;
  if tg_op = 'INSERT' then
    new.status := 'approved';
  elsif old.status = 'pending' or new.status = 'pending' then
    new.status := case when old.status in ('rejected', 'suspended') then old.status else 'approved' end;
  end if;
  return new;
end $$;
revoke all on function public.service_publish_guard() from public, anon, authenticated;
drop trigger if exists zz_service_publish on public.service_providers;
create trigger zz_service_publish before insert or update on public.service_providers
  for each row execute function public.service_publish_guard();

-- 2) Waiting services / shops: published once.
update public.service_providers set status = 'approved' where status = 'pending';

-- 3) "Dayanacaq əlavə et": shown at once.
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
  -- 0099 (owner, 06.11.2026): a parking spot is shown at once — no admin
  -- approval (only "Park işlədirəm" waits for the admin).
  insert into tir_parks (name, lat, lng, city, amenities, note, created_by, status, reviewed_at)
  values (btrim(p_name), p_lat, p_lng, nullif(btrim(coalesce(p_city, '')), ''), coalesce(p_amenities, '{}'),
          nullif(btrim(coalesce(p_note, '')), ''), v_uid, 'approved', now())
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public.tir_park_add(text, double precision, double precision, text, text[], text) from public, anon;
grant execute on function public.tir_park_add(text, double precision, double precision, text, text[], text) to authenticated;

-- 4) Waiting parking spots without a manager application: published once.
do $$
begin
  perform set_config('app.tir_park_admin', 'on', true);   -- the park guard lets the status change
  update public.tir_parks set status = 'approved', reviewed_at = coalesce(reviewed_at, now())
   where status = 'pending' and manager_id is null;
  perform set_config('app.tir_park_admin', 'off', true);
end $$;

notify pgrst, 'reload schema';

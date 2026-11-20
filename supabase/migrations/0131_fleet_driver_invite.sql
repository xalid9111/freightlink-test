-- =====================================================================
-- 0131 — Maşınlarım: the driver is chosen from the registered users
-- (owner, 20.11.2026: "sürücü əlavə edərkən ad yazılanda qeydiyyatda olan
-- istifadəçilər tapılsın … qeydiyyatdadırsa əlavə edilə bilsin").
--   * fleet_driver_search(q): while the owner types the driver's name the
--     registered accounts whose name holds it (≥ 2 letters, at most 10,
--     never oneself, never a deleted / blocked account): id, name, picture,
--     blue badge only — no phone, no e-mail.
--   * fleet_driver_invite_user(truck, user): the owner picks one → the
--     truck shows "Sürücü təsdiqi gözləyir" (pending_driver_id) and the
--     driver gets a bell notice "… sizi sürücü kimi əlavə edir" with Qəbul
--     et / Rədd et. Never linked without his own yes.
--   * fleet_driver_answer(invite, accept): only the invited account; yes =
--     linked exactly like the code (fleet_driver_join), no = the waiting
--     mark goes; the owner gets a notice either way.
--   * fleet_driver_invite_cancel(truck): the owner takes it back (✕).
--   * fleet_my_driver_invites(): the open invitations of the signed-in
--     user (the bell hides an answered one).
--   * The one-time code stays; a new code no longer cancels a waiting
--     invitation; unlinking cancels both.
-- Safe: forward-only, re-runnable; two columns added (nullable), functions
-- added / replaced with the same signatures; no row is deleted.
-- =====================================================================

do $$
begin
  if to_regclass('public.fleet_trucks') is null then
    raise exception '0131: run 0130_fleet.sql first — nothing changed';
  end if;
end $$;

alter table public.fleet_trucks add column if not exists pending_driver_id uuid references public.users(id) on delete set null;
alter table public.fleet_driver_invites add column if not exists invited_user uuid references public.users(id) on delete cascade;
create index if not exists fleet_driver_invites_user_idx on public.fleet_driver_invites (invited_user)
  where invited_user is not null and used_at is null and cancelled_at is null;

-- The registered accounts whose name holds the typed text.
create or replace function public.fleet_driver_search(p_q text)
returns table (id uuid, full_name text, avatar_url text, is_verified boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_q text := btrim(coalesce(p_q, ''));
begin
  if char_length(v_q) < 2 or char_length(v_q) > 60 then return; end if;
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');
  return query
    select p.id, p.full_name, p.avatar_url, coalesce(p.is_verified, false)
      from user_profiles p
     where p.id <> v_me
       and p.is_active is not false
       and not public.is_blocked(p.id)
       and p.full_name is not null
       and p.full_name <> 'Silinmiş istifadəçi'
       and p.full_name ilike '%' || v_q || '%'
     order by (p.full_name ilike v_q || '%') desc, p.full_name
     limit 10;
end $$;

-- The owner asks a registered account to drive his truck.
create or replace function public.fleet_driver_invite_user(p_truck uuid, p_user uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_t fleet_trucks := public._fleet_owned_truck(p_truck);
  v_name text;
  v_owner text;
  v_code text;
  v_i fleet_driver_invites;
begin
  if p_user is null or p_user = v_t.owner_id then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select full_name into v_name from users where id = p_user and is_active is not false;
  if v_name is null or public.is_blocked(p_user) then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_t.driver_id = p_user then
    return jsonb_build_object('status', 'linked');
  end if;
  -- The same invitation still open: nothing new (a double tap).
  select * into v_i from fleet_driver_invites
   where truck_id = v_t.id and invited_user = p_user and used_at is null and cancelled_at is null and expires_at > now();
  if v_i.id is not null then
    return jsonb_build_object('status', 'pending', 'invite_id', v_i.id);
  end if;
  if (select count(*) from fleet_driver_invites where created_by = v_t.owner_id and created_at > now() - interval '1 day') >= 30 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  -- Another account's open invitation for this truck is replaced.
  update fleet_driver_invites set cancelled_at = now()
   where truck_id = v_t.id and invited_user is not null and used_at is null and cancelled_at is null;
  loop
    v_code := public._tir_park_new_code();
    exit when not exists (select 1 from fleet_driver_invites where code = v_code);
  end loop;
  insert into fleet_driver_invites (truck_id, code, created_by, invited_user)
  values (v_t.id, v_code, v_t.owner_id, p_user) returning * into v_i;
  update fleet_trucks set pending_driver_id = p_user, driver_name = left(btrim(v_name), 60), updated_at = now()
   where id = v_t.id;
  select full_name into v_owner from users where id = v_t.owner_id;
  begin
    insert into notifications (user_id, type, title, body, data)
    values (p_user, 'fleet_driver_invite',
            coalesce(nullif(btrim(v_owner), ''), 'TırLink') || ' sizi sürücü kimi əlavə edir',
            v_t.name || coalesce(' · ' || v_t.plate, ''),
            jsonb_build_object('invite_id', v_i.id, 'truck', v_t.name, 'plate', v_t.plate,
                               'owner', v_owner, 'dedupe', 'fli:' || v_i.id))
    on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  exception when others then
    raise notice 'notice (fleet invite) skipped: %', sqlerrm;
  end;
  return jsonb_build_object('status', 'pending', 'invite_id', v_i.id);
end $$;

-- The invited account answers: yes = linked, no = the waiting mark goes.
create or replace function public.fleet_driver_answer(p_invite uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_i fleet_driver_invites;
  v_t fleet_trucks;
  v_name text;
begin
  if p_accept is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select * into v_i from fleet_driver_invites where id = p_invite for update;
  if v_i.id is null or v_i.invited_user is distinct from v_me then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if v_i.used_at is not null or v_i.cancelled_at is not null or v_i.expires_at <= now() then
    raise exception 'invite_closed' using errcode = '22023';
  end if;
  select * into v_t from fleet_trucks where id = v_i.truck_id and deleted_at is null for update;
  if v_t.id is null then raise exception 'invite_closed' using errcode = '22023'; end if;
  select full_name into v_name from users where id = v_me;
  if p_accept then
    update fleet_driver_invites set used_at = now(), used_by = v_me where id = v_i.id;
    update fleet_trucks set driver_id = v_me, pending_driver_id = null, updated_at = now() where id = v_t.id;
  else
    update fleet_driver_invites set cancelled_at = now() where id = v_i.id;
    update fleet_trucks set pending_driver_id = null, updated_at = now()
     where id = v_t.id and pending_driver_id = v_me;
  end if;
  begin
    insert into notifications (user_id, type, title, body, data)
    values (v_t.owner_id, 'fleet_driver_answer',
            coalesce(nullif(btrim(v_name), ''), 'Sürücü') || case when p_accept then ' qəbul etdi' else ' rədd etdi' end,
            v_t.name || coalesce(' · ' || v_t.plate, ''),
            jsonb_build_object('truck_id', v_t.id, 'truck', v_t.name, 'driver', v_name, 'accepted', p_accept,
                               'dedupe', 'fla:' || v_i.id))
    on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  exception when others then
    raise notice 'notice (fleet answer) skipped: %', sqlerrm;
  end;
  return jsonb_build_object('truck_id', v_t.id, 'name', v_t.name, 'plate', v_t.plate, 'accepted', p_accept);
end $$;

-- The owner takes a waiting invitation back (the ✕ on the chosen driver).
create or replace function public.fleet_driver_invite_cancel(p_truck uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._fleet_owned_truck(p_truck);
  update fleet_driver_invites set cancelled_at = now()
   where truck_id = p_truck and invited_user is not null and used_at is null and cancelled_at is null;
  update fleet_trucks set pending_driver_id = null, updated_at = now() where id = p_truck;
end $$;

-- My open invitations (the bell hides the answered / closed ones).
create or replace function public.fleet_my_driver_invites()
returns setof uuid language sql stable security definer set search_path = public, pg_temp as $$
  select i.id from fleet_driver_invites i
    join fleet_trucks t on t.id = i.truck_id and t.deleted_at is null
   where i.invited_user = auth.uid() and i.used_at is null and i.cancelled_at is null and i.expires_at > now();
$$;

-- A code no longer cancels a waiting invitation (only other codes).
create or replace function public.fleet_invite_create(p_truck uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_t fleet_trucks := public._fleet_owned_truck(p_truck);
  v_code text;
  v_i fleet_driver_invites;
begin
  if (select count(*) from fleet_driver_invites where created_by = v_t.owner_id and created_at > now() - interval '1 day') >= 30 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  update fleet_driver_invites set cancelled_at = now()
   where truck_id = v_t.id and invited_user is null and used_at is null and cancelled_at is null;
  loop
    v_code := public._tir_park_new_code();
    exit when not exists (select 1 from fleet_driver_invites where code = v_code);
  end loop;
  insert into fleet_driver_invites (truck_id, code, created_by) values (v_t.id, v_code, v_t.owner_id) returning * into v_i;
  return jsonb_build_object('code', v_i.code, 'expires_at', v_i.expires_at);
end $$;

-- The code: only an open code (never someone's personal invitation).
create or replace function public.fleet_driver_join(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_i fleet_driver_invites;
  v_t fleet_trucks;
begin
  select * into v_i from fleet_driver_invites
   where code = upper(btrim(coalesce(p_code, ''))) and invited_user is null
     and used_at is null and cancelled_at is null and expires_at > now()
   for update;
  if v_i.id is null then raise exception 'invalid_code' using errcode = '22023'; end if;
  select * into v_t from fleet_trucks where id = v_i.truck_id and deleted_at is null;
  if v_t.id is null then raise exception 'invalid_code' using errcode = '22023'; end if;
  if v_t.owner_id = v_me then raise exception 'own_truck' using errcode = '22023'; end if;
  update fleet_driver_invites set used_at = now(), used_by = v_me where id = v_i.id;
  update fleet_driver_invites set cancelled_at = now()
   where truck_id = v_t.id and invited_user is not null and used_at is null and cancelled_at is null;
  update fleet_trucks set driver_id = v_me, pending_driver_id = null, updated_at = now() where id = v_t.id;
  return jsonb_build_object('truck_id', v_t.id, 'name', v_t.name, 'plate', v_t.plate);
end $$;

-- Unlinking: the driver, the waiting invitation and open codes all go.
create or replace function public.fleet_driver_unlink(p_truck uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._fleet_owned_truck(p_truck);
  update fleet_trucks set driver_id = null, pending_driver_id = null, updated_at = now() where id = p_truck;
  update fleet_driver_invites set cancelled_at = now() where truck_id = p_truck and used_at is null and cancelled_at is null;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'fleet_driver_search(text)', 'fleet_driver_invite_user(uuid, uuid)', 'fleet_driver_answer(uuid, boolean)', 'fleet_driver_invite_cancel(uuid)',
    'fleet_my_driver_invites()', 'fleet_invite_create(uuid)', 'fleet_driver_join(text)', 'fleet_driver_unlink(uuid)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

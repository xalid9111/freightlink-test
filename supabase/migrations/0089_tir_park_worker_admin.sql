-- =====================================================================
-- 0089 — TIR park: one worker as the park's admin (owner, 03.11.2026).
--
-- Run AFTER 0088.
--
-- The park's owner names ONE of his active workers "Admin"
-- (tir_park_worker_set_admin; naming another one takes it from the
-- first). The park admin, besides adding trucks and recording exits:
--   * makes / cancels invitation codes,
--   * approves or rejects the workers who sent their name (0088),
--   * takes ordinary workers off.
-- He cannot take the admin role from anyone, cannot take himself or the
-- owner off, and still does not see the takings, the report or the
-- payments — those stay the owner's. The owner keeps full control and
-- can take the role back (or the worker off) at any time. A new request
-- is told to the park admin too (notification).
--
-- Safe: forward-only, re-runnable. One column (default false) and one
-- index added, functions created / re-created. No table, column or row
-- is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.tir_park_worker_approve(uuid, uuid)') is null then
    raise exception '0089: run 0088 first — nothing changed';
  end if;
end $$;

alter table public.tir_park_workers add column if not exists is_admin boolean not null default false;
-- One admin per park.
create unique index if not exists tir_park_workers_one_admin_idx on public.tir_park_workers (park_id) where is_admin;

-- Am I this park's admin (an active worker the owner named)?
create or replace function public.is_tir_park_staff_admin(p_park uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from tir_park_workers w
                  where w.park_id = p_park and w.user_id = auth.uid() and w.active and w.is_admin);
$$;
revoke all on function public.is_tir_park_staff_admin(uuid) from public, anon;
grant execute on function public.is_tir_park_staff_admin(uuid) to authenticated;

-- The owner, an app admin or the park's admin.
create or replace function public._tir_park_staff_only(p_park uuid)
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null
     or not (public.is_tir_park_manager(p_park) or public.is_admin() or public.is_tir_park_staff_admin(p_park)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
end $$;
revoke all on function public._tir_park_staff_only(uuid) from public, anon, authenticated;

-- The owner names / un-names the park admin.
create or replace function public.tir_park_worker_set_admin(p_park uuid, p_user uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_owner_only(p_park);
  if coalesce(p_on, false) then
    if not exists (select 1 from tir_park_workers where park_id = p_park and user_id = p_user and active) then
      raise exception 'not_found' using errcode = 'P0002';
    end if;
    update tir_park_workers set is_admin = false where park_id = p_park and is_admin and user_id <> p_user;
    update tir_park_workers set is_admin = true where park_id = p_park and user_id = p_user;
  else
    update tir_park_workers set is_admin = false where park_id = p_park and user_id = p_user;
  end if;
end $$;
revoke all on function public.tir_park_worker_set_admin(uuid, uuid, boolean) from public, anon;
grant execute on function public.tir_park_worker_set_admin(uuid, uuid, boolean) to authenticated;

-- Invitations: also the park admin.
create or replace function public.tir_park_invite_create(p_park uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_code text;
  v_i tir_park_invites;
begin
  perform public._tir_park_staff_only(p_park);
  if (select count(*) from tir_park_invites where park_id = p_park and used_at is null and cancelled_at is null and expires_at > now()) >= 20 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  loop
    v_code := public._tir_park_new_code();
    exit when not exists (select 1 from tir_park_invites where code = v_code);
  end loop;
  insert into tir_park_invites (park_id, code, created_by) values (p_park, v_code, auth.uid()) returning * into v_i;
  return jsonb_build_object('id', v_i.id, 'code', v_i.code, 'expires_at', v_i.expires_at);
end $$;
revoke all on function public.tir_park_invite_create(uuid) from public, anon;
grant execute on function public.tir_park_invite_create(uuid) to authenticated;

create or replace function public.tir_park_invite_cancel(p_invite uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_i tir_park_invites;
begin
  select * into v_i from tir_park_invites where id = p_invite for update;
  if v_i.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public._tir_park_staff_only(v_i.park_id);
  update tir_park_invites set cancelled_at = coalesce(cancelled_at, now()) where id = p_invite and used_at is null;
end $$;
revoke all on function public.tir_park_invite_cancel(uuid) from public, anon;
grant execute on function public.tir_park_invite_cancel(uuid) to authenticated;

-- Requests: the park admin approves / rejects too.
create or replace function public.tir_park_worker_approve(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_staff_only(p_park);
  update tir_park_workers set active = true, status = 'active', joined_at = now(), removed_at = null
   where park_id = p_park and user_id = p_user and status = 'pending';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_approve(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_approve(uuid, uuid) to authenticated;

create or replace function public.tir_park_worker_reject(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_staff_only(p_park);
  update tir_park_workers set active = false, status = 'rejected', is_admin = false, removed_at = now()
   where park_id = p_park and user_id = p_user and status = 'pending';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_reject(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_reject(uuid, uuid) to authenticated;

-- Taking off: the owner anybody; the park admin only ordinary workers.
create or replace function public.tir_park_worker_remove(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_staff_only(p_park);
  if not (public.is_tir_park_manager(p_park) or public.is_admin())
     and (p_user = auth.uid()
          or exists (select 1 from tir_park_workers where park_id = p_park and user_id = p_user and is_admin)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update tir_park_workers set active = false, status = 'removed', is_admin = false, removed_at = now()
   where park_id = p_park and user_id = p_user and active;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_remove(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_remove(uuid, uuid) to authenticated;

-- İşçilər list: + who is the admin; the park admin sees it too.
create or replace function public.tir_park_workers_list(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_today timestamptz := public._tir_park_today_start();
begin
  perform public._tir_park_staff_only(p_park);
  return jsonb_build_object(
    'workers', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', w.user_id, 'name', coalesce(w.full_name, u.full_name), 'account_name', u.full_name,
                                          'phone', u.phone, 'active', w.active, 'is_admin', w.is_admin,
                                          'status', coalesce(w.status, case when w.active then 'active' else 'removed' end),
                                          'joined_at', w.joined_at,
                                          'today_in', (select count(*) from tir_park_stays s where s.park_id = p_park and s.entered_by = w.user_id and s.entered_at >= v_today),
                                          'today_out', (select count(*) from tir_park_stays s where s.park_id = p_park and s.exited_by = w.user_id and s.exited_at >= v_today))
                       order by (w.status = 'pending') desc, w.is_admin desc, w.active desc, w.joined_at desc)
        from tir_park_workers w left join users u on u.id = w.user_id where w.park_id = p_park), '[]'::jsonb),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'code', i.code, 'created_at', i.created_at, 'expires_at', i.expires_at)
                       order by i.created_at desc)
        from tir_park_invites i
       where i.park_id = p_park and i.used_at is null and i.cancelled_at is null and i.expires_at > now()), '[]'::jsonb));
end $$;
revoke all on function public.tir_park_workers_list(uuid) from public, anon;
grant execute on function public.tir_park_workers_list(uuid) to authenticated;

-- My parks as a worker: + am I the admin, and how many requests wait.
create or replace function public.tir_park_my_work()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'city', p.city,
                                               'status', coalesce(w.status, 'active'),
                                               'is_admin', w.active and w.is_admin,
                                               'pending', case when w.active and w.is_admin
                                                               then (select count(*) from tir_park_workers x where x.park_id = p.id and x.status = 'pending')
                                                               else 0 end)
                            order by p.name), '[]'::jsonb)
    from tir_park_workers w join tir_parks p on p.id = w.park_id
   where w.user_id = auth.uid() and p.status = 'approved'
     and (w.active or w.status in ('pending', 'rejected'));
$$;
revoke all on function public.tir_park_my_work() from public, anon;
grant execute on function public.tir_park_my_work() to authenticated;

-- A new request: the owner (0088) and also the park admin are told.
create or replace function public.tir_park_invite_accept(p_code text, p_name text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_i tir_park_invites;
  p tir_parks;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_conv conversations;
  v_admin uuid;
begin
  if public.is_blocked(auth.uid()) then raise exception 'blocked' using errcode = '42501'; end if;
  if char_length(v_name) not between 3 and 80 or v_name !~ '^\S+ \S+' then
    return jsonb_build_object('error', 'name_required');
  end if;
  v_i := public._tir_park_invite_find(p_code);
  if v_i.id is null then return jsonb_build_object('error', 'invalid_code'); end if;
  select * into p from tir_parks where id = v_i.park_id;
  if p.manager_id = auth.uid() then return jsonb_build_object('error', 'own_park'); end if;
  if exists (select 1 from tir_park_workers where park_id = p.id and user_id = auth.uid() and active) then
    return jsonb_build_object('error', 'already_worker');
  end if;
  update tir_park_invites set used_by = auth.uid(), used_at = now() where id = v_i.id and used_at is null;
  insert into tir_park_workers (park_id, user_id, active, status, full_name, invited_by, joined_at, removed_at)
  values (v_i.park_id, auth.uid(), false, 'pending', v_name, v_i.created_by, now(), null)
  on conflict (park_id, user_id) do update
     set active = false, status = 'pending', is_admin = false, full_name = excluded.full_name, invited_by = excluded.invited_by,
         joined_at = now(), removed_at = null;

  begin
    insert into notifications (user_id, type, title, body, data)
    values (p.manager_id, 'tirpark_worker_request', 'İşçi təsdiq gözləyir: ' || v_name, p.name,
            jsonb_build_object('park_id', p.id, 'worker_id', auth.uid(), 'dedupe', 'tpw:' || v_i.id))
    on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  exception when others then
    null;
  end;
  begin
    select user_id into v_admin from tir_park_workers where park_id = p.id and active and is_admin limit 1;
    if v_admin is not null and v_admin <> p.manager_id then
      insert into notifications (user_id, type, title, body, data)
      values (v_admin, 'tirpark_worker_request', 'İşçi təsdiq gözləyir: ' || v_name, p.name,
              jsonb_build_object('park_id', p.id, 'worker_id', auth.uid(), 'dedupe', 'tpwa:' || v_i.id))
      on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
    end if;
  exception when others then
    null;
  end;
  begin
    v_conv := public.get_or_create_direct_conversation(p.manager_id);
    insert into messages (conversation_id, sender_id, receiver_id, message)
    values (v_conv.id, auth.uid(), p.manager_id,
            'Park işçisi kimi qoşulmaq istəyirəm.' || E'\nPark: ' || p.name || E'\nAd, soyad: ' || v_name
            || E'\nTəsdiq: Profil → Park işlədirəm → İşçilər → Təsdiqlə');
  exception when others then
    null;
  end;
  return jsonb_build_object('park_id', p.id, 'park_name', p.name, 'status', 'pending');
end $$;
revoke all on function public.tir_park_invite_accept(text, text) from public, anon;
grant execute on function public.tir_park_invite_accept(text, text) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_park_worker_set_admin(uuid, uuid, boolean)') is null
     or to_regprocedure('public.is_tir_park_staff_admin(uuid)') is null then
    raise exception '0089: final check failed — nothing changed';
  end if;
end $$;

commit;

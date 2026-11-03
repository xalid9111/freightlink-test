-- =====================================================================
-- 0088 — TIR park workers: the owner approves (owner, 03.11.2026).
--
-- Run AFTER 0087.
--
-- Before (0087) a worker who accepted the invitation code was bound to
-- the park at once and the owner was not told. Now:
--   1. The worker pastes the code, sees the park's name, writes his name
--      and surname and sends — tir_park_invite_accept(code, name). He is
--      NOT working yet: "Sahibkarın təsdiqini gözləyir".
--   2. The park's owner is told: a notice (notifications, type
--      'tirpark_worker_request'), a message from the worker in Mesajlar,
--      and the count on Profil → "Park işlədirəm"
--      (tir_park_owner_pending_workers).
--   3. The owner approves (tir_park_worker_approve) → the worker works;
--      or rejects (tir_park_worker_reject).
-- The one-argument tir_park_invite_accept(code) of 0087 now refuses
-- ('name_required'), so an old copy of the app cannot skip the approval.
-- A worker already approved by 0087 keeps working.
--
-- Safe: forward-only, re-runnable. Two nullable columns, functions
-- created / re-created. No table, column or row is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.tir_park_workers') is null then
    raise exception '0088: run 0087 first — nothing changed';
  end if;
end $$;

-- The name the worker wrote, and where his request stands.
alter table public.tir_park_workers add column if not exists full_name text;
alter table public.tir_park_workers add column if not exists status text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tir_park_workers_status_check') then
    alter table public.tir_park_workers add constraint tir_park_workers_status_check check (
          (status is null or status in ('pending', 'active', 'rejected', 'removed'))
      and (full_name is null or char_length(full_name) between 3 and 80));
  end if;
end $$;

-- 0087's one-argument accept: no longer binds anybody.
create or replace function public.tir_park_invite_accept(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  return jsonb_build_object('error', 'name_required');
end $$;
revoke all on function public.tir_park_invite_accept(text) from public, anon;
grant execute on function public.tir_park_invite_accept(text) to authenticated;

-- The worker sends his request with his name and surname → waits.
create or replace function public.tir_park_invite_accept(p_code text, p_name text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_i tir_park_invites;
  p tir_parks;
  v_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  v_conv conversations;
begin
  if public.is_blocked(auth.uid()) then raise exception 'blocked' using errcode = '42501'; end if;
  -- Name and surname: two words at least, 3–80 characters.
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
     set active = false, status = 'pending', full_name = excluded.full_name, invited_by = excluded.invited_by,
         joined_at = now(), removed_at = null;

  -- Tell the owner (never blocks the request).
  begin
    insert into notifications (user_id, type, title, body, data)
    values (p.manager_id, 'tirpark_worker_request', 'İşçi təsdiq gözləyir: ' || v_name, p.name,
            jsonb_build_object('park_id', p.id, 'worker_id', auth.uid(),
                               'dedupe', 'tpw:' || v_i.id))
    on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
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

-- The owner lets the worker in / says no.
create or replace function public.tir_park_worker_approve(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_owner_only(p_park);
  update tir_park_workers set active = true, status = 'active', joined_at = now(), removed_at = null
   where park_id = p_park and user_id = p_user and status = 'pending';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_approve(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_approve(uuid, uuid) to authenticated;

create or replace function public.tir_park_worker_reject(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_owner_only(p_park);
  update tir_park_workers set active = false, status = 'rejected', removed_at = now()
   where park_id = p_park and user_id = p_user and status = 'pending';
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_reject(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_reject(uuid, uuid) to authenticated;

-- Taken off: also marked 'removed'.
create or replace function public.tir_park_worker_remove(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_owner_only(p_park);
  update tir_park_workers set active = false, status = 'removed', removed_at = now() where park_id = p_park and user_id = p_user and active;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_remove(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_remove(uuid, uuid) to authenticated;

-- How many workers wait for the signed-in owner (Profil count).
create or replace function public.tir_park_owner_pending_workers()
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from tir_park_workers w join tir_parks p on p.id = w.park_id
   where p.manager_id = auth.uid() and p.manager_status = 'approved' and w.status = 'pending';
$$;
revoke all on function public.tir_park_owner_pending_workers() from public, anon;
grant execute on function public.tir_park_owner_pending_workers() to authenticated;

-- The owner's İşçilər: + the name each worker wrote and his status.
create or replace function public.tir_park_workers_list(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_today timestamptz := public._tir_park_today_start();
begin
  perform public._tir_park_owner_only(p_park);
  return jsonb_build_object(
    'workers', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', w.user_id, 'name', coalesce(w.full_name, u.full_name), 'account_name', u.full_name,
                                          'phone', u.phone, 'active', w.active,
                                          'status', coalesce(w.status, case when w.active then 'active' else 'removed' end),
                                          'joined_at', w.joined_at,
                                          'today_in', (select count(*) from tir_park_stays s where s.park_id = p_park and s.entered_by = w.user_id and s.entered_at >= v_today),
                                          'today_out', (select count(*) from tir_park_stays s where s.park_id = p_park and s.exited_by = w.user_id and s.exited_at >= v_today))
                       order by (w.status = 'pending') desc, w.active desc, w.joined_at desc)
        from tir_park_workers w left join users u on u.id = w.user_id where w.park_id = p_park), '[]'::jsonb),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'code', i.code, 'created_at', i.created_at, 'expires_at', i.expires_at)
                       order by i.created_at desc)
        from tir_park_invites i
       where i.park_id = p_park and i.used_at is null and i.cancelled_at is null and i.expires_at > now()), '[]'::jsonb));
end $$;
revoke all on function public.tir_park_workers_list(uuid) from public, anon;
grant execute on function public.tir_park_workers_list(uuid) to authenticated;

-- My parks as a worker: + waiting / not let in.
create or replace function public.tir_park_my_work()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'city', p.city,
                                               'status', coalesce(w.status, 'active'))
                            order by p.name), '[]'::jsonb)
    from tir_park_workers w join tir_parks p on p.id = w.park_id
   where w.user_id = auth.uid() and p.status = 'approved'
     and (w.active or w.status in ('pending', 'rejected'));
$$;
revoke all on function public.tir_park_my_work() from public, anon;
grant execute on function public.tir_park_my_work() to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_park_invite_accept(text, text)') is null
     or to_regprocedure('public.tir_park_worker_approve(uuid, uuid)') is null then
    raise exception '0088: final check failed — nothing changed';
  end if;
end $$;

commit;

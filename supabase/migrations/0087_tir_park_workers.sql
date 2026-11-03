-- =====================================================================
-- 0087 — TIR park owner panel, stage 2: workers (owner, 03.11.2026).
--
-- Run AFTER 0086.
--
-- 1. Workers join by an INVITATION, never automatically (the owner's
--    rule): the owner makes an invitation code in his panel
--    (tir_park_invite_create) and gives it to the worker; the worker,
--    signed in with his OWN FreightLink account, types it in Profil →
--    "Park işçisiyəm", sees the park's name (tir_park_invite_preview) and
--    accepts (tir_park_invite_accept) — only then he is bound to that
--    park. A phone number or e-mail never binds anyone. No passwords are
--    made by the owner. An invitation works once, for 7 days; the owner
--    can cancel it or take a worker off (tir_park_worker_remove).
-- 2. A worker adds trucks by their plate and records their exit
--    (can_work_tir_park now includes the park's active workers); he sees
--    the places, not the takings (tir_park_owner_summary hides the money
--    for him). Bookings, payments, settings, invitations and the report
--    stay the owner's.
-- 3. The owner sees all records and the workers' activity
--    (tir_park_worker_activity) and a report by day
--    (tir_park_owner_report: entries, exits, money taken).
--
-- Safe: forward-only, re-runnable. Two new tables, functions created /
-- re-created. No table, column or row is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.tir_park_stays') is null or to_regprocedure('public.can_work_tir_park(uuid)') is null then
    raise exception '0087: run 0086 first — nothing changed';
  end if;
end $$;

-- 1) Workers and invitations ------------------------------------------------------
create table if not exists public.tir_park_workers (
  park_id uuid not null references public.tir_parks(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  active boolean not null default true,
  invited_by uuid references public.users(id) on delete set null,
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  primary key (park_id, user_id)
);
create index if not exists tir_park_workers_user_idx on public.tir_park_workers (user_id) where active;
alter table public.tir_park_workers enable row level security;
revoke all on public.tir_park_workers from anon, authenticated;

create table if not exists public.tir_park_invites (
  id uuid primary key default gen_random_uuid(),
  park_id uuid not null references public.tir_parks(id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z2-9]{8}$'),
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_by uuid references public.users(id) on delete set null,
  used_at timestamptz,
  cancelled_at timestamptz
);
create index if not exists tir_park_invites_park_idx on public.tir_park_invites (park_id, created_at desc);
alter table public.tir_park_invites enable row level security;
revoke all on public.tir_park_invites from anon, authenticated;

-- Wrong codes typed by one person (a code cannot be guessed by trying).
create table if not exists public.tir_park_invite_attempts (
  user_id uuid not null references public.users(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists tir_park_invite_attempts_idx on public.tir_park_invite_attempts (user_id, at desc);
alter table public.tir_park_invite_attempts enable row level security;
revoke all on public.tir_park_invite_attempts from anon, authenticated;

-- Who may work a park: its owner, its active workers, admins.
create or replace function public.can_work_tir_park(p_park uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_tir_park_manager(p_park) or public.is_admin()
      or exists (select 1 from tir_park_workers w where w.park_id = p_park and w.user_id = auth.uid() and w.active);
$$;
revoke all on function public.can_work_tir_park(uuid) from public, anon;
grant execute on function public.can_work_tir_park(uuid) to authenticated;

create or replace function public._tir_park_owner_only(p_park uuid)
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not (public.is_tir_park_manager(p_park) or public.is_admin()) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
end $$;
revoke all on function public._tir_park_owner_only(uuid) from public, anon, authenticated;

-- The owner makes an invitation (a one-time code, 7 days).
create or replace function public.tir_park_invite_create(p_park uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_code text;
  v_i tir_park_invites;
begin
  perform public._tir_park_owner_only(p_park);
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
  perform public._tir_park_owner_only(v_i.park_id);
  update tir_park_invites set cancelled_at = coalesce(cancelled_at, now()) where id = p_invite and used_at is null;
end $$;
revoke all on function public.tir_park_invite_cancel(uuid) from public, anon;
grant execute on function public.tir_park_invite_cancel(uuid) to authenticated;

-- A valid code → the park's name (shown before accepting); a wrong code is
-- counted (30 a day per person).
create or replace function public._tir_park_invite_find(p_code text)
returns tir_park_invites language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_i tir_park_invites;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if (select count(*) from tir_park_invite_attempts where user_id = auth.uid() and at > now() - interval '1 day') >= 30 then
    raise exception 'too_many_attempts' using errcode = '54000';
  end if;
  select * into v_i from tir_park_invites
   where code = v_code and used_at is null and cancelled_at is null and expires_at > now();
  if v_i.id is null then
    insert into tir_park_invite_attempts (user_id) values (auth.uid());
  end if;
  return v_i;
end $$;
revoke all on function public._tir_park_invite_find(text) from public, anon, authenticated;

create or replace function public.tir_park_invite_preview(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_i tir_park_invites;
  p tir_parks;
begin
  v_i := public._tir_park_invite_find(p_code);
  if v_i.id is null then return jsonb_build_object('error', 'invalid_code'); end if;
  select * into p from tir_parks where id = v_i.park_id;
  return jsonb_build_object('park_id', p.id, 'park_name', p.name, 'city', p.city);
end $$;
revoke all on function public.tir_park_invite_preview(text) from public, anon;
grant execute on function public.tir_park_invite_preview(text) to authenticated;

-- The worker accepts with his own account → bound to that park.
create or replace function public.tir_park_invite_accept(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_i tir_park_invites;
  p tir_parks;
begin
  if public.is_blocked(auth.uid()) then raise exception 'blocked' using errcode = '42501'; end if;
  v_i := public._tir_park_invite_find(p_code);
  if v_i.id is null then return jsonb_build_object('error', 'invalid_code'); end if;
  select * into p from tir_parks where id = v_i.park_id;
  if p.manager_id = auth.uid() then return jsonb_build_object('error', 'own_park'); end if;
  update tir_park_invites set used_by = auth.uid(), used_at = now() where id = v_i.id and used_at is null;
  insert into tir_park_workers (park_id, user_id, active, invited_by, joined_at, removed_at)
  values (v_i.park_id, auth.uid(), true, v_i.created_by, now(), null)
  on conflict (park_id, user_id) do update set active = true, invited_by = excluded.invited_by, joined_at = now(), removed_at = null;
  return jsonb_build_object('park_id', p.id, 'park_name', p.name);
end $$;
revoke all on function public.tir_park_invite_accept(text) from public, anon;
grant execute on function public.tir_park_invite_accept(text) to authenticated;

-- The owner takes a worker off (his records stay).
create or replace function public.tir_park_worker_remove(p_park uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_owner_only(p_park);
  update tir_park_workers set active = false, removed_at = now() where park_id = p_park and user_id = p_user and active;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
end $$;
revoke all on function public.tir_park_worker_remove(uuid, uuid) from public, anon;
grant execute on function public.tir_park_worker_remove(uuid, uuid) to authenticated;

-- The owner's İşçilər: workers (with what they did today) + open invitations.
create or replace function public.tir_park_workers_list(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_today timestamptz := public._tir_park_today_start();
begin
  perform public._tir_park_owner_only(p_park);
  return jsonb_build_object(
    'workers', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', w.user_id, 'name', u.full_name, 'phone', u.phone, 'active', w.active,
                                          'joined_at', w.joined_at,
                                          'today_in', (select count(*) from tir_park_stays s where s.park_id = p_park and s.entered_by = w.user_id and s.entered_at >= v_today),
                                          'today_out', (select count(*) from tir_park_stays s where s.park_id = p_park and s.exited_by = w.user_id and s.exited_at >= v_today))
                       order by w.active desc, w.joined_at desc)
        from tir_park_workers w left join users u on u.id = w.user_id where w.park_id = p_park), '[]'::jsonb),
    'invites', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'code', i.code, 'created_at', i.created_at, 'expires_at', i.expires_at)
                       order by i.created_at desc)
        from tir_park_invites i
       where i.park_id = p_park and i.used_at is null and i.cancelled_at is null and i.expires_at > now()), '[]'::jsonb));
end $$;
revoke all on function public.tir_park_workers_list(uuid) from public, anon;
grant execute on function public.tir_park_workers_list(uuid) to authenticated;

-- Parks I work at (Profil → "Park işçisiyəm").
create or replace function public.tir_park_my_work()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'city', p.city) order by p.name), '[]'::jsonb)
    from tir_park_workers w join tir_parks p on p.id = w.park_id
   where w.user_id = auth.uid() and w.active and p.status = 'approved';
$$;
revoke all on function public.tir_park_my_work() from public, anon;
grant execute on function public.tir_park_my_work() to authenticated;

-- 2) The owner sees what the workers did ("İşçi fəaliyyəti") -------------------------
create or replace function public.tir_park_worker_activity(p_park uuid, p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_owner uuid;
begin
  perform public._tir_park_owner_only(p_park);
  select manager_id into v_owner from tir_parks where id = p_park;
  return coalesce((
    select jsonb_agg(x.e order by x.ts desc) from (
      select y.e, y.ts from (
        select jsonb_build_object('kind', 'in', 'plate', s.plate, 'at', s.entered_at, 'by', u.full_name, 'user_id', s.entered_by) as e,
               s.entered_at as ts
          from tir_park_stays s join users u on u.id = s.entered_by
         where s.park_id = p_park and s.entered_by is distinct from v_owner
        union all
        select jsonb_build_object('kind', 'out', 'plate', s.plate, 'at', s.exited_at, 'amount', s.amount, 'by', u.full_name, 'user_id', s.exited_by),
               s.exited_at
          from tir_park_stays s join users u on u.id = s.exited_by
         where s.park_id = p_park and s.exited_at is not null and s.exited_by is distinct from v_owner
      ) y
      order by y.ts desc
      limit least(greatest(coalesce(p_limit, 30), 1), 100)
    ) x), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_worker_activity(uuid, integer) from public, anon;
grant execute on function public.tir_park_worker_activity(uuid, integer) to authenticated;

-- 3) The report by day (Baku days): entries, exits, money taken --------------------------
create or replace function public.tir_park_owner_report(p_park uuid, p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 92);
  v_from date := (now() at time zone 'Asia/Baku')::date - (v_days - 1);
begin
  perform public._tir_park_owner_only(p_park);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'day', d.day,
             'entries', (select count(*) from tir_park_stays s where s.park_id = p_park
                          and (s.entered_at at time zone 'Asia/Baku')::date = d.day),
             'exits', (select count(*) from tir_park_stays s where s.park_id = p_park and s.exited_at is not null
                          and (s.exited_at at time zone 'Asia/Baku')::date = d.day),
             'cars_paid', coalesce((select sum(s.amount) from tir_park_stays s where s.park_id = p_park and s.exited_at is not null
                          and (s.exited_at at time zone 'Asia/Baku')::date = d.day), 0),
             'bookings_paid', coalesce((select sum(b.amount) from tir_park_bookings b where b.park_id = p_park and b.confirmed_at is not null
                          and b.status in ('confirmed', 'checked_in', 'completed')
                          and (b.confirmed_at at time zone 'Asia/Baku')::date = d.day), 0))
           order by d.day desc)
      from (select generate_series(v_from, (now() at time zone 'Asia/Baku')::date, interval '1 day')::date as day) d), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_owner_report(uuid, integer) from public, anon;
grant execute on function public.tir_park_owner_report(uuid, integer) to authenticated;

-- The park's numbers (0086) — money only for the owner.
create or replace function public.tir_park_owner_summary(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  p tir_parks;
  v_in integer;
  v_reserved integer;
  v_today timestamptz := public._tir_park_today_start();
  v_owner boolean := public.is_tir_park_manager(p_park) or public.is_admin();
begin
  if auth.uid() is null or not public.can_work_tir_park(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select * into p from tir_parks where id = p_park;
  select count(*)::int into v_in from tir_park_stays where park_id = p_park and exited_at is null;
  -- Booked for now, not come yet.
  select coalesce(sum(trucks), 0)::int into v_reserved from tir_park_bookings
   where park_id = p_park and start_at <= now() and end_at > now()
     and (status in ('confirmed', 'payment_review') or (status = 'pending_payment' and hold_until > now()));
  return jsonb_build_object(
    'capacity', coalesce(p.capacity, 0),
    'in_park', v_in,
    'reserved', v_reserved,
    'free', greatest(0, coalesce(p.capacity, 0) - v_in - v_reserved),
    'currency', p.currency,
    'open', p.booking_open,
    -- Money only for the owner (a worker sees places, not the takings).
    -- Taken today: exits today + bookings confirmed today.
    'today_paid', case when not v_owner then null else coalesce((select sum(amount) from tir_park_stays where park_id = p_park and exited_at >= v_today), 0)
                + coalesce((select sum(amount) from tir_park_bookings where park_id = p_park and confirmed_at >= v_today
                            and status in ('confirmed', 'checked_in', 'completed')), 0) end,
    -- Run up by the cars still in the park (not taken yet).
    'accruing', case when not v_owner then null else coalesce((select sum(public._tir_park_stay_amount(rate, entered_at, paid_until, now()))
                            from tir_park_stays where park_id = p_park and exited_at is null), 0) end,
    'today_in', (select count(*) from tir_park_stays where park_id = p_park and entered_at >= v_today),
    'today_out', (select count(*) from tir_park_stays where park_id = p_park and exited_at >= v_today));
end $$;
revoke all on function public.tir_park_owner_summary(uuid) from public, anon;
grant execute on function public.tir_park_owner_summary(uuid) to authenticated;

-- The park's latest events ("Parkın gedişatı") — the owner's only (0087).
create or replace function public.tir_park_owner_feed(p_park uuid, p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._tir_park_owner_only(p_park);   -- the owner's (0087: not the workers')
  return coalesce((
    select jsonb_agg(e order by (e ->> 'at')::timestamptz desc)
      from (
        select x.e from (
          select jsonb_build_object('kind', 'in', 'plate', s.plate, 'at', s.entered_at, 'by', u.full_name) as e, s.entered_at as ts
            from tir_park_stays s left join users u on u.id = s.entered_by where s.park_id = p_park
          union all
          select jsonb_build_object('kind', 'out', 'plate', s.plate, 'at', s.exited_at, 'amount', s.amount, 'by', u.full_name), s.exited_at
            from tir_park_stays s left join users u on u.id = s.exited_by where s.park_id = p_park and s.exited_at is not null
          union all
          select jsonb_build_object('kind', 'booking', 'plate', b.plate, 'at', b.created_at, 'booking_no', b.booking_no,
                                    'start_at', b.start_at, 'end_at', b.end_at), b.created_at
            from tir_park_bookings b where b.park_id = p_park and b.status not in ('expired')
          union all
          select jsonb_build_object('kind', 'paid', 'plate', b.plate, 'at', b.confirmed_at, 'amount', b.amount), b.confirmed_at
            from tir_park_bookings b where b.park_id = p_park and b.confirmed_at is not null
        ) x
        order by x.ts desc
        limit least(greatest(coalesce(p_limit, 30), 1), 100)
      ) y(e)), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_owner_feed(uuid, integer) from public, anon;
grant execute on function public.tir_park_owner_feed(uuid, integer) to authenticated;

-- Final check.
do $$
begin
  if to_regclass('public.tir_park_workers') is null or to_regprocedure('public.tir_park_invite_accept(text)') is null
     or to_regprocedure('public.tir_park_owner_report(uuid, integer)') is null then
    raise exception '0087: final check failed — nothing changed';
  end if;
end $$;

commit;

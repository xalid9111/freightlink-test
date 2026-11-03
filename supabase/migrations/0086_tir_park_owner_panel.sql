-- =====================================================================
-- 0086 — TIR park owner panel, stage 1 (owner, 03.11.2026).
--
-- Run AFTER 0079 … 0085. Builds on tir_parks / tir_park_bookings; no
-- second booking system.
--
-- 1. "Park işlədirəm": a person writes only the park's NAME
--    (tir_park_owner_apply) → an admin approves it in Admin → TIRPark
--    (admin_tir_park_owner_request_set) → his owner panel opens; there he
--    puts the park on the map once, with capacity and the price per day
--    (tir_park_owner_setup). One owner per park.
-- 2. Cars in the park by their plate (no place numbers, no entry code):
--    tir_park_stays. tir_park_stay_enter(park, plate) / tir_park_stay_exit.
--    The amount grows with the time: price per 24 h × hours / 24
--    (3 AZN: 5 h = 0.63, 1 day 4 h = 3.50, 2 days = 6.00), taken at the
--    exit. A car with a paid booking starts paying only after its paid
--    days end (an overstay is counted the same way).
-- 3. Bookings by day: a day starts at 00:00 (Baku); a booking for today
--    may start at today's 00:00 (before: not before "now"). The free
--    places of every booked day are checked before it is held (as 0079).
--    Cars that came without a booking also take places now.
-- 4. The owner's numbers (tir_park_owner_summary): capacity, in the park,
--    free, "Bu gün" = money actually taken today (exits today + bookings
--    confirmed today), and — separately — what the cars still in the park
--    have run up so far (not taken yet, so nothing is counted twice).
--    tir_park_owner_feed: the park's latest events.
--
-- can_work_tir_park(park): the park's owner (and admins) for now; stage 2
-- adds the park's workers.
--
-- Safe: forward-only, re-runnable. Two new tables, functions created /
-- re-created. No table, column or row is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text)') is null
     or to_regprocedure('public.tir_park_manager_pending()') is null then
    raise exception '0086: run 0079 … 0085 first — nothing changed';
  end if;
end $$;

-- Today's 00:00 in Baku.
create or replace function public._tir_park_today_start()
returns timestamptz language sql stable set search_path = public, pg_temp as $$
  select date_trunc('day', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku';
$$;

-- Who may work a park (stage 2 adds workers).
create or replace function public.can_work_tir_park(p_park uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_tir_park_manager(p_park) or public.is_admin();
$$;
revoke all on function public.can_work_tir_park(uuid) from public, anon;
grant execute on function public.can_work_tir_park(uuid) to authenticated;

-- 1) "Park işlədirəm" ----------------------------------------------------------
create table if not exists public.tir_park_owner_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.users(id) on delete cascade,
  park_name text not null check (char_length(btrim(park_name)) between 2 and 80),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  park_id uuid references public.tir_parks(id) on delete set null,
  note text check (note is null or char_length(note) <= 200),
  created_at timestamptz not null default now(),
  reviewed_by uuid references public.users(id) on delete set null,
  reviewed_at timestamptz
);
-- One open request (waiting, or approved and not set up yet) per person.
create unique index if not exists tir_park_owner_requests_open on public.tir_park_owner_requests (user_id)
  where status = 'pending' or (status = 'approved' and park_id is null);
alter table public.tir_park_owner_requests enable row level security;
revoke all on public.tir_park_owner_requests from anon, authenticated;
grant select on public.tir_park_owner_requests to authenticated;
drop policy if exists "tir_park_owner_requests_read" on public.tir_park_owner_requests;
create policy "tir_park_owner_requests_read" on public.tir_park_owner_requests
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

create or replace function public.tir_park_owner_apply(p_name text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 80 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if exists (select 1 from tir_park_owner_requests where user_id = auth.uid()
              and (status = 'pending' or (status = 'approved' and park_id is null))) then
    raise exception 'already_applied' using errcode = '23505';
  end if;
  insert into tir_park_owner_requests (user_id, park_name) values (auth.uid(), btrim(p_name)) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.tir_park_owner_apply(text) from public, anon;
grant execute on function public.tir_park_owner_apply(text) to authenticated;

-- Admin: the requests (waiting first), with who asked.
create or replace function public.admin_tir_park_owner_requests()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'park_name', r.park_name, 'status', r.status, 'park_id', r.park_id,
                                        'created_at', r.created_at, 'user_id', r.user_id, 'user_name', u.full_name,
                                        'user_phone', u.phone, 'user_email', u.email)
                     order by (r.status = 'pending') desc, r.created_at desc)
      from (select * from tir_park_owner_requests order by created_at desc limit 300) r
      left join users u on u.id = r.user_id), '[]'::jsonb);
end $$;
revoke all on function public.admin_tir_park_owner_requests() from public, anon;
grant execute on function public.admin_tir_park_owner_requests() to authenticated;

create or replace function public.admin_tir_park_owner_request_set(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old tir_park_owner_requests;
begin
  perform public._require_admin();
  if p_status not in ('approved', 'rejected') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select * into v_old from tir_park_owner_requests where id = p_id for update;
  if v_old.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_old.status <> 'pending' then raise exception 'already_reviewed' using errcode = '22023'; end if;
  update tir_park_owner_requests
     set status = p_status, note = left(nullif(btrim(coalesce(p_note, '')), ''), 200), reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_id;
  perform public._admin_log('tir_park.owner_request_' || p_status, 'tir_park_owner_requests', p_id::text,
    jsonb_build_object('status', v_old.status), jsonb_build_object('status', p_status, 'park_name', v_old.park_name, 'user_id', v_old.user_id));
end $$;
revoke all on function public.admin_tir_park_owner_request_set(uuid, text, text) from public, anon;
grant execute on function public.admin_tir_park_owner_request_set(uuid, text, text) to authenticated;

-- The approved owner puts his park on the map (once): capacity, price per
-- day. p_park = an approved park nobody runs yet (the same place), or null
-- = a new park at p_lat / p_lng.
create or replace function public.tir_park_owner_setup(
  p_request uuid, p_park uuid, p_lat double precision, p_lng double precision, p_city text,
  p_capacity integer, p_price numeric, p_phone text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_r tir_park_owner_requests;
  v_park tir_parks;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_r from tir_park_owner_requests where id = p_request for update;
  if v_r.id is null or v_r.user_id <> auth.uid() then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_r.status <> 'approved' or v_r.park_id is not null then raise exception 'not_allowed' using errcode = '42501'; end if;
  if p_capacity is null or p_capacity not between 1 and 2000 or p_price is null or p_price <= 0 or p_price > 10000
     or p_phone is null or char_length(btrim(p_phone)) not between 5 and 40
     or (p_city is not null and char_length(p_city) > 80) then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  perform set_config('app.tir_park_manage', 'on', true);
  if p_park is null then
    if p_lat is null or p_lng is null or abs(p_lat) > 90 or abs(p_lng) > 180 then
      raise exception 'invalid_argument' using errcode = '22023';
    end if;
    if exists (select 1 from tir_parks where status in ('approved', 'pending')
                and lat between p_lat - 0.001 and p_lat + 0.001
                and public.tir_park_distance_m(p_lat, p_lng, lat, lng) < 60) then
      raise exception 'duplicate_nearby' using errcode = '23505';
    end if;
    insert into tir_parks (name, lat, lng, city, status, created_by, reviewed_by, reviewed_at,
                           manager_id, manager_status, manager_applied_at, phone,
                           capacity, bookable, price, price_unit, booking_open)
    values (v_r.park_name, p_lat, p_lng, nullif(btrim(coalesce(p_city, '')), ''), 'approved', auth.uid(), v_r.reviewed_by, now(),
            auth.uid(), 'approved', now(), btrim(p_phone),
            p_capacity, p_capacity, round(p_price, 2), 'day', false)
    returning id into v_id;
  else
    select * into v_park from tir_parks where id = p_park for update;
    if v_park.id is null or v_park.status <> 'approved' then raise exception 'not_found' using errcode = 'P0002'; end if;
    if v_park.manager_id is not null and v_park.manager_status in ('pending', 'approved') and v_park.manager_id <> auth.uid() then
      raise exception 'already_managed' using errcode = '23505';
    end if;
    update tir_parks
       set manager_id = auth.uid(), manager_status = 'approved', manager_applied_at = now(), phone = btrim(p_phone),
           capacity = p_capacity, bookable = p_capacity, price = round(p_price, 2), price_unit = 'day'
     where id = p_park;
    v_id := p_park;
  end if;
  perform set_config('app.tir_park_manage', 'off', true);
  update tir_park_owner_requests set park_id = v_id where id = p_request;
  return v_id;
end $$;
revoke all on function public.tir_park_owner_setup(uuid, uuid, double precision, double precision, text, integer, numeric, text) from public, anon;
grant execute on function public.tir_park_owner_setup(uuid, uuid, double precision, double precision, text, integer, numeric, text) to authenticated;

-- 2) Cars in the park ------------------------------------------------------------
create table if not exists public.tir_park_stays (
  id uuid primary key default gen_random_uuid(),
  park_id uuid not null references public.tir_parks(id) on delete restrict,
  plate text not null check (char_length(plate) between 3 and 15 and plate ~ '^[[:alnum:]][[:alnum:]-]*[[:alnum:]]$'),
  entered_at timestamptz not null default now(),
  entered_by uuid references public.users(id) on delete set null,
  exited_at timestamptz,
  exited_by uuid references public.users(id) on delete set null,
  booking_id uuid references public.tir_park_bookings(id) on delete set null,
  rate numeric(10,2) not null check (rate >= 0),            -- price per 24 h at the entry
  paid_until timestamptz,                                    -- a paid booking's end
  amount numeric(12,2) check (amount is null or amount >= 0), -- taken at the exit
  currency text not null default 'AZN',
  created_at timestamptz not null default now(),
  check (exited_at is null or exited_at >= entered_at)
);
create unique index if not exists tir_park_stays_open on public.tir_park_stays (park_id, plate) where exited_at is null;
create index if not exists tir_park_stays_park_idx on public.tir_park_stays (park_id, entered_at desc);
create index if not exists tir_park_stays_exit_idx on public.tir_park_stays (park_id, exited_at desc) where exited_at is not null;
alter table public.tir_park_stays enable row level security;
revoke all on public.tir_park_stays from anon, authenticated;
grant select on public.tir_park_stays to authenticated;
drop policy if exists "tir_park_stays_read" on public.tir_park_stays;
create policy "tir_park_stays_read" on public.tir_park_stays
  for select to authenticated using (public.can_work_tir_park(park_id));

-- Price per 24 h × hours / 24 (from the end of a paid booking, if any).
create or replace function public._tir_park_stay_amount(p_rate numeric, p_from timestamptz, p_paid_until timestamptz, p_to timestamptz)
returns numeric language sql immutable set search_path = public, pg_temp as $$
  select round(coalesce(p_rate, 0) * greatest(0, extract(epoch from (p_to - greatest(p_from, coalesce(p_paid_until, p_from))))) / 86400.0, 2);
$$;

-- Cars without a booking that are in the park now.
create or replace function public._tir_park_walkins(p_park uuid)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from tir_park_stays where park_id = p_park and exited_at is null and booking_id is null;
$$;
revoke all on function public._tir_park_walkins(uuid) from public, anon, authenticated;

-- Booked places (0080) + cars without a booking that are in the park now.
create or replace function public._tir_park_used(p_park uuid, p_from timestamptz, p_to timestamptz, p_except uuid default null)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(trucks), 0)::int + public._tir_park_walkins(p_park) from tir_park_bookings
   where park_id = p_park and start_at < p_to and end_at > p_from
     and (p_except is null or id <> p_except)
     and (status in ('confirmed', 'checked_in', 'payment_review') or (status = 'pending_payment' and hold_until > now()));
$$;
revoke all on function public._tir_park_used(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- A car comes in (by its plate).
create or replace function public.tir_park_stay_enter(p_park uuid, p_plate text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  p tir_parks;
  v_plate text := public._tir_park_plate(p_plate);
  v_b tir_park_bookings;
  v_s tir_park_stays;
  v_rate numeric;
begin
  if auth.uid() is null or not public.can_work_tir_park(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_plate is null then raise exception 'invalid_plate' using errcode = '22023'; end if;
  select * into p from tir_parks where id = p_park for update;   -- one car at a time per park
  if p.id is null or p.status <> 'approved' then raise exception 'not_found' using errcode = 'P0002'; end if;
  if exists (select 1 from tir_park_stays where park_id = p_park and plate = v_plate and exited_at is null) then
    raise exception 'already_in' using errcode = '23505';
  end if;
  perform public._tir_park_expire_holds(p_park);
  -- Its booking for now (paid), if any.
  select * into v_b from tir_park_bookings
   where park_id = p_park and plate = v_plate and status = 'confirmed' and start_at <= now() + interval '12 hours' and end_at > now()
   order by start_at limit 1 for update;
  if v_b.id is null and exists (select 1 from tir_park_bookings where park_id = p_park and plate = v_plate and status = 'payment_review'
                                 and end_at > now()) then
    raise exception 'payment_in_review' using errcode = '22023';
  end if;
  if v_b.id is null and coalesce(p.capacity, 0) - public._tir_park_used(p_park, now(), now() + interval '1 minute') < 1 then
    raise exception 'no_space' using errcode = '23P01';
  end if;
  v_rate := case when p.price_unit = 'hour' then coalesce(p.price, 0) * 24 else coalesce(p.price, 0) end;
  insert into tir_park_stays (park_id, plate, entered_by, booking_id, rate, paid_until, currency)
  values (p_park, v_plate, auth.uid(), v_b.id, round(v_rate, 2), v_b.end_at, p.currency)
  returning * into v_s;
  if v_b.id is not null then
    update tir_park_bookings set status = 'checked_in', checked_in_at = now(), checked_in_by = auth.uid(), updated_at = now()
     where id = v_b.id;
  end if;
  return to_jsonb(v_s) || jsonb_build_object('booking_no', v_b.booking_no);
end $$;
revoke all on function public.tir_park_stay_enter(uuid, text) from public, anon;
grant execute on function public.tir_park_stay_enter(uuid, text) to authenticated;

-- A car leaves: the amount is taken now.
create or replace function public.tir_park_stay_exit(p_stay uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_s tir_park_stays;
begin
  select * into v_s from tir_park_stays where id = p_stay for update;
  if v_s.id is null or auth.uid() is null or not public.can_work_tir_park(v_s.park_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_s.exited_at is not null then raise exception 'already_out' using errcode = '22023'; end if;
  update tir_park_stays
     set exited_at = now(), exited_by = auth.uid(),
         amount = public._tir_park_stay_amount(rate, entered_at, paid_until, now())
   where id = p_stay returning * into v_s;
  if v_s.booking_id is not null then
    update tir_park_bookings set status = 'completed', checked_out_at = now(), updated_at = now()
     where id = v_s.booking_id and status = 'checked_in';
  end if;
  return to_jsonb(v_s);
end $$;
revoke all on function public.tir_park_stay_exit(uuid) from public, anon;
grant execute on function public.tir_park_stay_exit(uuid) to authenticated;

-- The cars in the park now (+ what each has run up so far) and the paid
-- bookings expected today that have not come yet.
create or replace function public.tir_park_parked(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.can_work_tir_park(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'now', now(),
    'in', coalesce((
      select jsonb_agg(jsonb_build_object('id', s.id, 'plate', s.plate, 'entered_at', s.entered_at, 'rate', s.rate,
                                          'paid_until', s.paid_until, 'booking_id', s.booking_id, 'booking_no', b.booking_no,
                                          'amount_now', public._tir_park_stay_amount(s.rate, s.entered_at, s.paid_until, now()),
                                          'currency', s.currency, 'by', u.full_name)
                       order by s.entered_at desc)
        from tir_park_stays s
        left join tir_park_bookings b on b.id = s.booking_id
        left join users u on u.id = s.entered_by
       where s.park_id = p_park and s.exited_at is null), '[]'::jsonb),
    'expected', coalesce((
      select jsonb_agg(jsonb_build_object('id', b.id, 'booking_no', b.booking_no, 'plate', b.plate, 'trucks', b.trucks,
                                          'start_at', b.start_at, 'end_at', b.end_at, 'status', b.status)
                       order by b.start_at)
        from tir_park_bookings b
       where b.park_id = p_park and b.status in ('confirmed', 'payment_review')
         and b.start_at < public._tir_park_today_start() + interval '1 day' and b.end_at > now()), '[]'::jsonb));
end $$;
revoke all on function public.tir_park_parked(uuid) from public, anon;
grant execute on function public.tir_park_parked(uuid) to authenticated;

-- The owner's numbers.
create or replace function public.tir_park_owner_summary(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  p tir_parks;
  v_in integer;
  v_reserved integer;
  v_today timestamptz := public._tir_park_today_start();
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
    -- Taken today: exits today + bookings confirmed today.
    'today_paid', coalesce((select sum(amount) from tir_park_stays where park_id = p_park and exited_at >= v_today), 0)
                + coalesce((select sum(amount) from tir_park_bookings where park_id = p_park and confirmed_at >= v_today
                            and status in ('confirmed', 'checked_in', 'completed')), 0),
    -- Run up by the cars still in the park (not taken yet).
    'accruing', coalesce((select sum(public._tir_park_stay_amount(rate, entered_at, paid_until, now()))
                            from tir_park_stays where park_id = p_park and exited_at is null), 0),
    'today_in', (select count(*) from tir_park_stays where park_id = p_park and entered_at >= v_today),
    'today_out', (select count(*) from tir_park_stays where park_id = p_park and exited_at >= v_today));
end $$;
revoke all on function public.tir_park_owner_summary(uuid) from public, anon;
grant execute on function public.tir_park_owner_summary(uuid) to authenticated;

-- The park's latest events ("Parkın gedişatı").
create or replace function public.tir_park_owner_feed(p_park uuid, p_limit integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.can_work_tir_park(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
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

-- 3) Bookings by day: from today's 00:00 (Baku) -----------------------------------
create or replace function public.tir_park_booking_create(p_park uuid, p_from timestamptz, p_to timestamptz, p_trucks integer, p_plate text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  p tir_parks;
  v_units integer;
  v_secs double precision;
  v_b tir_park_bookings;
  v_plate text := public._tir_park_plate(p_plate);
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_trucks is null or p_trucks not between 1 and 50 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if v_plate is null then raise exception 'invalid_plate' using errcode = '22023'; end if;
  -- A day starts at 00:00 (Baku); today's booking may start at today's 00:00.
  if p_from is null or p_to is null or p_to <= p_from or p_from < public._tir_park_today_start() - interval '1 minute'
     or p_to - p_from > interval '30 days' then
    raise exception 'invalid_time' using errcode = '22023';
  end if;
  select * into p from tir_parks where id = p_park for update;
  if p.id is null or not public.tir_park_bookable(p) then raise exception 'not_bookable' using errcode = '22023'; end if;
  if p.manager_id = v_uid then raise exception 'own_park' using errcode = '22023'; end if;
  if (select count(*) from tir_park_bookings where user_id = v_uid and status = 'pending_payment' and hold_until > now()) >= 3 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  perform public._tir_park_expire_holds(p_park);
  if p.bookable - public._tir_park_used(p_park, p_from, p_to) < p_trucks then
    raise exception 'no_space' using errcode = '23P01';
  end if;
  v_secs := extract(epoch from (p_to - p_from));
  v_units := greatest(1, ceil(v_secs / case when p.price_unit = 'hour' then 3600 else 86400 end)::int);
  insert into tir_park_bookings (booking_no, park_id, user_id, trucks, start_at, end_at, units, unit, price, amount, currency,
                                 status, hold_until, plate)
  values ('TP' || to_char(now(), 'YYMMDD') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6)),
          p_park, v_uid, p_trucks, p_from, p_to, v_units, p.price_unit, p.price,
          round(p.price * v_units * p_trucks, 2), p.currency, 'pending_payment', now() + interval '60 minutes', v_plate)
  returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text) from public, anon;
grant execute on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text) to authenticated;

-- Final check.
do $$
begin
  if to_regclass('public.tir_park_stays') is null or to_regclass('public.tir_park_owner_requests') is null
     or to_regprocedure('public.tir_park_stay_enter(uuid, text)') is null
     or to_regprocedure('public.tir_park_owner_summary(uuid)') is null then
    raise exception '0086: final check failed — nothing changed';
  end if;
end $$;

commit;

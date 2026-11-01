-- =====================================================================
-- 0079 — TIR park management and paid space booking (owner, 01.11.2026)
--
-- * A user applies in Profil → "TIR parkı idarə edirəm": a new park, or an
--   approved park on the map nobody manages yet. The application keeps the
--   park's contact, address, place, total TIR capacity, the number of
--   TIRs it takes through the app now ("bookable"), price per hour / day,
--   opening hours and amenities. Managing is a separate permission: it
--   exists only after an admin approves the application
--   (admin_tir_park_manager_set); a normal profile has no such right.
-- * Bookings: a driver picks arrival / departure and the number of TIRs.
--   tir_park_booking_create LOCKS THE PARK ROW, then counts the TIRs of
--   confirmed / arrived bookings and of unexpired payment holds that
--   overlap the time — so the last free space can never go to two people.
--   A new booking holds its space 15 minutes ('pending_payment').
-- * Payment: the existing card checkout (ad_payments, Edge Function
--   payments-checkout, payments-webhook). Only a verified provider event
--   (finance_apply_provider_event, service role) confirms a booking; a
--   failed payment or an expired hold frees the space. TEST mode stays
--   test (the checkout is open only to the finance owner, as before) and a
--   test-paid booking is marked paid_mode = 'test'. No commission is set
--   on these payments (commission 0); no money split is assumed.
-- * Entry code: on confirmation the server makes a random 8-character code
--   (from gen_random_uuid). The driver sees it; the park's approved
--   manager (or an admin) checks it on the server: right park only, once
--   only (a used code is refused), at most 30 wrong codes an hour. The
--   manager sees the driver's name, not his phone (the phone rules of
--   0019 stay).
-- * Statuses: pending_payment, confirmed, checked_in, completed, cancelled,
--   expired (refund_pending / refunded are reserved for a provider that
--   supports refunds; nothing sets them today).
-- * Payouts to parks: NOT implemented — the payment provider is not
--   connected and has no payout account mechanism here. No card / bank
--   data is stored anywhere in FreightLink.
--
-- Safe: forward-only, re-runnable. New columns (nullable / defaulted) on
-- tir_parks and ad_payments, two new tables, new functions, and
-- finance_apply_provider_event re-created from 0067 with ONE more step.
-- Nothing is deleted. Needs 0077 (tir_parks) and 0067.
-- =====================================================================

begin;

-- 1) Park management fields ------------------------------------------------
alter table public.tir_parks add column if not exists manager_id uuid references public.users(id) on delete set null;
alter table public.tir_parks add column if not exists manager_status text;
alter table public.tir_parks add column if not exists phone text;
alter table public.tir_parks add column if not exists address text;
alter table public.tir_parks add column if not exists capacity integer;
alter table public.tir_parks add column if not exists bookable integer;
alter table public.tir_parks add column if not exists price numeric(10,2);
alter table public.tir_parks add column if not exists price_unit text;
alter table public.tir_parks add column if not exists currency text not null default 'AZN';
alter table public.tir_parks add column if not exists hours text;
alter table public.tir_parks add column if not exists booking_open boolean not null default false;
alter table public.tir_parks add column if not exists manager_applied_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tir_parks_manage_check') then
    alter table public.tir_parks add constraint tir_parks_manage_check check (
          (manager_status is null or manager_status in ('pending', 'approved', 'rejected'))
      and (phone is null or char_length(phone) <= 40)
      and (address is null or char_length(address) <= 160)
      and (capacity is null or capacity between 1 and 2000)
      and (bookable is null or (bookable >= 0 and bookable <= coalesce(capacity, 0)))
      and (price is null or (price > 0 and price <= 10000))
      and (price_unit is null or price_unit in ('hour', 'day'))
      and currency in ('AZN')
      and (hours is null or char_length(hours) <= 40));
  end if;
end $$;
create index if not exists tir_parks_manager_idx on public.tir_parks (manager_id) where manager_id is not null;

-- Manager fields are the server's: a direct update keeps them (the
-- functions below set app.tir_park_manage).
create or replace function public.tir_parks_manage_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if coalesce(current_setting('app.tir_park_manage', true), 'off') <> 'on' then
    new.manager_id := old.manager_id;
    new.manager_status := old.manager_status;
    new.manager_applied_at := old.manager_applied_at;
    new.capacity := old.capacity;
    new.bookable := old.bookable;
    new.price := old.price;
    new.price_unit := old.price_unit;
    new.currency := old.currency;
    new.booking_open := old.booking_open;
  end if;
  return new;
end $$;
drop trigger if exists tir_parks_manage_guard on public.tir_parks;
create trigger tir_parks_manage_guard before update on public.tir_parks
  for each row execute function public.tir_parks_manage_guard();

-- Approved manager of the park (or an admin).
create or replace function public.is_tir_park_manager(p_park uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.is_admin() or exists (
    select 1 from tir_parks where id = p_park and manager_id = auth.uid() and manager_status = 'approved');
$$;
revoke all on function public.is_tir_park_manager(uuid) from public, anon;
grant execute on function public.is_tir_park_manager(uuid) to authenticated;

-- Open for booking: approved park, approved manager, price, capacity, open.
create or replace function public.tir_park_bookable(p tir_parks)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select p.status = 'approved' and p.manager_status = 'approved' and p.booking_open
     and coalesce(p.price, 0) > 0 and p.price_unit is not null and coalesce(p.bookable, 0) > 0;
$$;

-- 2) Applying to manage a park ----------------------------------------------
-- p_park null = a new park; else an approved park nobody manages yet.
create or replace function public.tir_park_manage_apply(
  p_park uuid, p_name text, p_lat double precision, p_lng double precision,
  p_city text, p_address text, p_phone text, p_amenities text[],
  p_capacity integer, p_bookable integer, p_price numeric, p_unit text, p_hours text, p_note text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_park tir_parks;
  v_id uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 80
     or p_phone is null or char_length(btrim(p_phone)) not between 5 and 40
     or p_capacity is null or p_capacity not between 1 and 2000
     or p_bookable is null or p_bookable < 0 or p_bookable > p_capacity
     or p_price is null or p_price <= 0 or p_price > 10000
     or p_unit is null or p_unit not in ('hour', 'day')
     or (p_hours is not null and char_length(p_hours) > 40)
     or (p_address is not null and char_length(p_address) > 160)
     or not public.tir_park_amenities_valid(coalesce(p_amenities, '{}')) then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if (select count(*) from tir_parks where manager_id = v_uid and manager_applied_at > now() - interval '1 day') >= 5 then
    raise exception 'too_many' using errcode = '54000';
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
    insert into tir_parks (name, lat, lng, city, amenities, note, status, created_by,
                           manager_id, manager_status, manager_applied_at, phone, address,
                           capacity, bookable, price, price_unit, hours, booking_open)
    values (btrim(p_name), p_lat, p_lng, nullif(btrim(coalesce(p_city, '')), ''), coalesce(p_amenities, '{}'),
            nullif(btrim(coalesce(p_note, '')), ''), 'pending', v_uid,
            v_uid, 'pending', now(), btrim(p_phone), nullif(btrim(coalesce(p_address, '')), ''),
            p_capacity, p_bookable, round(p_price, 2), p_unit, nullif(btrim(coalesce(p_hours, '')), ''), true)
    returning id into v_id;
  else
    select * into v_park from tir_parks where id = p_park for update;
    if v_park.id is null or v_park.status <> 'approved' then raise exception 'not_found' using errcode = 'P0002'; end if;
    if v_park.manager_id is not null and v_park.manager_status in ('pending', 'approved') and v_park.manager_id <> v_uid then
      raise exception 'already_managed' using errcode = '23505';
    end if;
    update tir_parks
       set manager_id = v_uid, manager_status = 'pending', manager_applied_at = now(),
           phone = btrim(p_phone), address = nullif(btrim(coalesce(p_address, '')), ''),
           capacity = p_capacity, bookable = p_bookable, price = round(p_price, 2), price_unit = p_unit,
           hours = nullif(btrim(coalesce(p_hours, '')), ''), booking_open = true
     where id = p_park;
    v_id := p_park;
  end if;
  perform set_config('app.tir_park_manage', 'off', true);
  return v_id;
end $$;
revoke all on function public.tir_park_manage_apply(uuid, text, double precision, double precision, text, text, text, text[], integer, integer, numeric, text, text, text) from public, anon;
grant execute on function public.tir_park_manage_apply(uuid, text, double precision, double precision, text, text, text, text[], integer, integer, numeric, text, text, text) to authenticated;

-- An admin approves / rejects an application (a new park is approved with it).
create or replace function public.admin_tir_park_manager_set(p_park uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old tir_parks;
begin
  perform public._require_admin();
  if p_status not in ('approved', 'rejected') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select * into v_old from tir_parks where id = p_park for update;
  if v_old.id is null or v_old.manager_id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform set_config('app.tir_park_manage', 'on', true);
  perform set_config('app.tir_park_admin', 'on', true);
  update tir_parks
     set manager_status = p_status,
         status = case when p_status = 'approved' and status = 'pending' then 'approved' else status end,
         reviewed_by = case when p_status = 'approved' and status = 'pending' then auth.uid() else reviewed_by end,
         reviewed_at = case when p_status = 'approved' and status = 'pending' then now() else reviewed_at end
   where id = p_park;
  perform set_config('app.tir_park_admin', 'off', true);
  perform set_config('app.tir_park_manage', 'off', true);
  perform public._admin_log('tir_park.manager_' || p_status, 'tir_parks', p_park::text,
    jsonb_build_object('manager_status', v_old.manager_status, 'status', v_old.status),
    jsonb_build_object('manager_status', p_status, 'manager_id', v_old.manager_id, 'name', v_old.name));
end $$;
revoke all on function public.admin_tir_park_manager_set(uuid, text) from public, anon;
grant execute on function public.admin_tir_park_manager_set(uuid, text) to authenticated;

-- The approved manager changes what drivers book (capacity, free places
-- now, price, hours, contact, open / paused).
create or replace function public.tir_park_manager_update(
  p_park uuid, p_capacity integer, p_bookable integer, p_price numeric, p_unit text,
  p_hours text, p_phone text, p_booking_open boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from tir_parks where id = p_park and manager_id = auth.uid() and manager_status = 'approved') then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_capacity is null or p_capacity not between 1 and 2000 or p_bookable is null or p_bookable < 0 or p_bookable > p_capacity
     or p_price is null or p_price <= 0 or p_price > 10000 or p_unit not in ('hour', 'day')
     or (p_hours is not null and char_length(p_hours) > 40)
     or p_phone is null or char_length(btrim(p_phone)) not between 5 and 40 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  perform set_config('app.tir_park_manage', 'on', true);
  update tir_parks set capacity = p_capacity, bookable = p_bookable, price = round(p_price, 2), price_unit = p_unit,
                       hours = nullif(btrim(coalesce(p_hours, '')), ''), phone = btrim(p_phone),
                       booking_open = coalesce(p_booking_open, false)
   where id = p_park;
  perform set_config('app.tir_park_manage', 'off', true);
end $$;
revoke all on function public.tir_park_manager_update(uuid, integer, integer, numeric, text, text, text, boolean) from public, anon;
grant execute on function public.tir_park_manager_update(uuid, integer, integer, numeric, text, text, text, boolean) to authenticated;

-- 3) Bookings --------------------------------------------------------------
create table if not exists public.tir_park_bookings (
  id uuid primary key default gen_random_uuid(),
  booking_no text not null unique,
  park_id uuid not null references public.tir_parks(id) on delete restrict,
  user_id uuid not null default auth.uid() references public.users(id) on delete restrict,
  trucks integer not null check (trucks between 1 and 50),
  start_at timestamptz not null,
  end_at timestamptz not null,
  units integer not null check (units between 1 and 1000),
  unit text not null check (unit in ('hour', 'day')),
  price numeric(10,2) not null check (price > 0),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'AZN',
  status text not null default 'pending_payment' check (status in
    ('pending_payment', 'confirmed', 'checked_in', 'completed', 'cancelled', 'expired', 'refund_pending', 'refunded')),
  hold_until timestamptz,
  paid_mode text check (paid_mode is null or paid_mode in ('test', 'live')),
  code text unique check (code is null or code ~ '^[A-Z2-9]{8}$'),
  confirmed_at timestamptz,
  checked_in_at timestamptz,
  checked_in_by uuid references public.users(id) on delete set null,
  checked_out_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_at > start_at)
);
create index if not exists tir_park_bookings_park_time_idx on public.tir_park_bookings (park_id, start_at, end_at);
create index if not exists tir_park_bookings_user_idx on public.tir_park_bookings (user_id, created_at desc);

alter table public.tir_park_bookings enable row level security;
revoke all on public.tir_park_bookings from anon, authenticated;
grant select on public.tir_park_bookings to authenticated;
-- The driver sees his own bookings (with his code); admins all. Managers
-- read their park's bookings through tir_park_manager_bookings (no code).
drop policy if exists "tir_park_bookings_select" on public.tir_park_bookings;
create policy "tir_park_bookings_select" on public.tir_park_bookings
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- Wrong-code attempts (a manager may try at most 30 an hour).
create table if not exists public.tir_park_code_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.users(id) on delete cascade,
  park_id uuid not null references public.tir_parks(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists tir_park_code_attempts_idx on public.tir_park_code_attempts (user_id, at);
alter table public.tir_park_code_attempts enable row level security;
revoke all on public.tir_park_code_attempts from anon, authenticated;

-- Holds whose time is over free their space.
create or replace function public._tir_park_expire_holds(p_park uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  update tir_park_bookings set status = 'expired', updated_at = now()
   where park_id = p_park and status = 'pending_payment' and hold_until <= now();
$$;
revoke all on function public._tir_park_expire_holds(uuid) from public, anon, authenticated;

-- TIRs taken in [from, to): confirmed, arrived, and unexpired holds.
create or replace function public._tir_park_used(p_park uuid, p_from timestamptz, p_to timestamptz, p_except uuid default null)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(trucks), 0)::int from tir_park_bookings
   where park_id = p_park and start_at < p_to and end_at > p_from
     and (p_except is null or id <> p_except)
     and (status in ('confirmed', 'checked_in') or (status = 'pending_payment' and hold_until > now()));
$$;
revoke all on function public._tir_park_used(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- Free places for a time (anybody signed in, bookable parks).
create or replace function public.tir_park_availability(p_park uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare p tir_parks;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into p from tir_parks where id = p_park;
  if p.id is null or not public.tir_park_bookable(p) then raise exception 'not_bookable' using errcode = '22023'; end if;
  if p_from is null or p_to is null or p_to <= p_from then raise exception 'invalid_time' using errcode = '22023'; end if;
  return jsonb_build_object('capacity', p.capacity, 'bookable', p.bookable,
                            'free', greatest(0, p.bookable - public._tir_park_used(p_park, p_from, p_to)));
end $$;
revoke all on function public.tir_park_availability(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.tir_park_availability(uuid, timestamptz, timestamptz) to authenticated;

-- Book: the park row is locked, so two bookings for the last space wait
-- for each other and only one gets it. Returns the booking (no code yet).
create or replace function public.tir_park_booking_create(p_park uuid, p_from timestamptz, p_to timestamptz, p_trucks integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  p tir_parks;
  v_units integer;
  v_secs double precision;
  v_b tir_park_bookings;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_trucks is null or p_trucks not between 1 and 50 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if p_from is null or p_to is null or p_to <= p_from or p_from < now() - interval '15 minutes'
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
                                 status, hold_until)
  values ('TP' || to_char(now(), 'YYMMDD') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6)),
          p_park, v_uid, p_trucks, p_from, p_to, v_units, p.price_unit, p.price,
          round(p.price * v_units * p_trucks, 2), p.currency, 'pending_payment', now() + interval '15 minutes')
  returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer) from public, anon;
grant execute on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer) to authenticated;

-- The driver cancels his booking (before arrival). No automatic refund:
-- the test provider has none (shown before payment).
create or replace function public.tir_park_booking_cancel(p_booking uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or v_b.user_id is distinct from auth.uid() then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_b.status not in ('pending_payment', 'confirmed') then raise exception 'not_cancellable' using errcode = '22023'; end if;
  update tir_park_bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'driver', updated_at = now()
   where id = p_booking;
end $$;
revoke all on function public.tir_park_booking_cancel(uuid) from public, anon;
grant execute on function public.tir_park_booking_cancel(uuid) to authenticated;

-- 4) Card payment for a booking (same checkout as 0062 / 0066 / 0067) ------
alter table public.ad_payments add column if not exists tir_park_booking_id uuid
  references public.tir_park_bookings(id) on delete restrict;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target6') then
    alter table public.ad_payments add constraint ad_payments_one_target6
      check (num_nonnulls(order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                          tir_park_booking_id) = 1);
  end if;
  if exists (select 1 from pg_constraint where conname = 'ad_payments_one_target5') then
    alter table public.ad_payments drop constraint ad_payments_one_target5;
  end if;
end $$;
create unique index if not exists ad_payments_one_open_per_tp_booking on public.ad_payments (tir_park_booking_id)
  where tir_park_booking_id is not null and status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_tp_booking on public.ad_payments (tir_park_booking_id, mode)
  where tir_park_booking_id is not null and status = 'succeeded';

create or replace function public.tir_park_booking_payment_create(p_booking uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_b tir_park_bookings;
  v_pay public.ad_payments;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not ((payment_checkout_available() ->> 'available')::boolean) then
    raise exception 'payments_disabled' using errcode = '42501';
  end if;
  if p_method is null or not (p_method = any (s.methods)) then raise exception 'invalid_method' using errcode = '22023'; end if;
  if p_key is null or length(p_key) not between 8 and 80 or p_key !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where user_id = v_uid and idempotency_key = p_key;
  if v_pay.id is not null then return v_pay; end if;

  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or v_b.user_id is distinct from v_uid then raise exception 'order_not_found' using errcode = 'P0002'; end if;
  if v_b.status <> 'pending_payment' or v_b.hold_until <= now() then raise exception 'order_not_payable' using errcode = '22023'; end if;
  if exists (select 1 from ad_payments where tir_park_booking_id = p_booking and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;
  select * into v_pay from ad_payments where tir_park_booking_id = p_booking and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  -- The space stays held while the payment runs (its own space only).
  update tir_park_bookings set hold_until = greatest(hold_until, now() + interval '15 minutes'), updated_at = now()
   where id = p_booking;
  insert into ad_payments (order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                           tir_park_booking_id, user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (null, null, null, null, null, p_booking, v_uid, v_b.amount, upper(v_b.currency), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode, 0, p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('tir_park_booking_id', p_booking, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.tir_park_booking_payment_create(uuid, text, text) from public, anon;
grant execute on function public.tir_park_booking_payment_create(uuid, text, text) to authenticated;

-- An 8-character code (no 0/O/1/I), from two random UUIDs.
create or replace function public._tir_park_new_code()
returns text language plpgsql volatile set search_path = public, pg_temp as $$
declare
  a constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  h text := md5(gen_random_uuid()::text || gen_random_uuid()::text);
  c text := '';
  i integer;
begin
  for i in 0..7 loop
    c := c || substr(a, (('x' || substr(h, i * 2 + 1, 2))::bit(8)::int % 32) + 1, 1);
  end loop;
  return c;
end $$;
revoke all on function public._tir_park_new_code() from public, anon, authenticated;

-- A verified successful payment confirms the booking and gives the code.
-- A booking whose hold ran out is confirmed only if its space is still
-- free; otherwise it is logged for the admin (manual refund decision).
create or replace function public._tir_park_booking_paid(p_booking uuid, p_mode text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_b tir_park_bookings;
  p tir_parks;
  v_code text;
begin
  select * into v_b from tir_park_bookings where id = p_booking;
  if v_b.id is null then return; end if;
  select * into p from tir_parks where id = v_b.park_id for update;   -- same lock as booking
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.status = 'pending_payment'
     or (v_b.status = 'expired' and p.bookable - public._tir_park_used(v_b.park_id, v_b.start_at, v_b.end_at, v_b.id) >= v_b.trucks) then
    loop
      v_code := public._tir_park_new_code();
      exit when not exists (select 1 from tir_park_bookings where code = v_code);
    end loop;
    update tir_park_bookings
       set status = 'confirmed', paid_mode = p_mode, code = v_code, confirmed_at = now(), hold_until = null, updated_at = now()
     where id = p_booking;
  else
    perform public._finance_log('tir_park.paid_not_confirmed', 'tir_park_booking', p_booking::text,
      jsonb_build_object('status', v_b.status, 'mode', p_mode));
  end if;
end $$;
revoke all on function public._tir_park_booking_paid(uuid, text) from public, anon, authenticated;

create or replace function public._tir_park_booking_failed(p_booking uuid)
returns void language sql security definer set search_path = public, pg_temp as $$
  update tir_park_bookings set status = 'cancelled', cancelled_at = now(), cancel_reason = 'payment_failed', hold_until = null,
         updated_at = now()
   where id = p_booking and status = 'pending_payment';
$$;
revoke all on function public._tir_park_booking_failed(uuid) from public, anon, authenticated;

-- 5) 0067's function with ONE extra step: a TIR park booking payment
-- confirms (success, LIVE or TEST) or frees (failure) the booking.
create or replace function public.finance_apply_provider_event(
  p_provider text, p_event_id text, p_payment uuid, p_type text,
  p_amount numeric, p_currency text, p_provider_ref text, p_payload jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_pay public.ad_payments;
  v_new text;
  v_result text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not_authorized' using errcode = '42501'; end if;
  if p_event_id is null or length(p_event_id) not between 3 and 200 then raise exception 'invalid_event' using errcode = '22023'; end if;

  insert into ad_payment_events (provider, event_id, payment_id, type, payload)
  values (p_provider, p_event_id, p_payment, coalesce(p_type, ''), coalesce(p_payload, '{}'::jsonb))
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  select * into v_pay from ad_payments where id = p_payment for update;
  v_new := case p_type when 'payment.succeeded' then 'succeeded' when 'payment.failed' then 'failed' else null end;
  v_result := case
    when v_pay.id is null then 'unknown_payment'
    when v_new is null then 'ignored_type'
    when v_pay.provider <> p_provider then 'provider_mismatch'
    when p_provider = 'test' and v_pay.mode <> 'test' then 'provider_mismatch'
    when p_amount is distinct from v_pay.amount or upper(coalesce(p_currency, '')) <> v_pay.currency then 'amount_mismatch'
    when v_pay.provider_ref is not null and p_provider_ref is distinct from v_pay.provider_ref then 'ref_mismatch'
    when v_pay.status not in ('created', 'pending') then 'already_final'
    else 'applied' end;
  update ad_payment_events set result = v_result where provider = p_provider and event_id = p_event_id;
  if v_result <> 'applied' then
    perform public._finance_log('provider_event.rejected', 'payment', coalesce(p_payment::text, ''),
      jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'type', p_type, 'result', v_result));
    return v_result;
  end if;

  update ad_payments set status = v_new, provider_ref = coalesce(provider_ref, p_provider_ref),
         confirmed_at = case when v_new = 'succeeded' then now() else confirmed_at end,
         failure_reason = case when v_new = 'failed' then left(coalesce(p_payload ->> 'reason', 'declined'), 200) else null end,
         updated_at = now()
   where id = v_pay.id;

  if v_new = 'succeeded' and v_pay.mode = 'live' then
    update ad_orders
       set payment_status = 'paid', paid_at = coalesce(paid_at, now()),
           payment_reference = coalesce(payment_reference, left(v_pay.provider || ':' || coalesce(p_provider_ref, v_pay.id::text), 120)),
           status = case when status = 'pending_payment' then 'awaiting_approval' else status end,
           updated_at = now()
     where id = v_pay.order_id;
  end if;
  -- 0054: a VIP order is applied on a LIVE or a TEST success.
  if v_new = 'succeeded' and v_pay.market_vip_order_id is not null then
    perform public._market_vip_apply(v_pay.market_vip_order_id);
  end if;
  -- 0062: the same for a load VIP order.
  if v_new = 'succeeded' and v_pay.cargo_vip_order_id is not null then
    perform public._cargo_vip_apply(v_pay.cargo_vip_order_id);
  end if;
  -- 0066: İrəli çək / Premium orders, the same way.
  if v_new = 'succeeded' and v_pay.market_promo_order_id is not null then
    perform public._market_promo_apply(v_pay.market_promo_order_id);
  end if;
  -- 0067: the same for a load.
  if v_new = 'succeeded' and v_pay.cargo_promo_order_id is not null then
    perform public._cargo_promo_apply(v_pay.cargo_promo_order_id);
  end if;
  -- 0079: a TIR park booking — confirmed with its code, or freed.
  if v_pay.tir_park_booking_id is not null then
    if v_new = 'succeeded' then
      perform public._tir_park_booking_paid(v_pay.tir_park_booking_id, v_pay.mode);
    else
      perform public._tir_park_booking_failed(v_pay.tir_park_booking_id);
    end if;
  end if;
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id, 'vip_order_id', v_pay.market_vip_order_id,
                       'cargo_vip_order_id', v_pay.cargo_vip_order_id, 'market_promo_order_id', v_pay.market_promo_order_id,
                       'cargo_promo_order_id', v_pay.cargo_promo_order_id, 'tir_park_booking_id', v_pay.tir_park_booking_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 6) The manager's side ---------------------------------------------------
-- My parks (applications and managed ones).
create or replace function public.tir_park_my_managed()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'lat', lat, 'lng', lng, 'city', city, 'address', address, 'phone', phone,
    'amenities', amenities, 'status', status, 'manager_status', manager_status, 'capacity', capacity,
    'bookable', bookable, 'price', price, 'price_unit', price_unit, 'currency', currency, 'hours', hours,
    'booking_open', booking_open) order by manager_applied_at desc), '[]'::jsonb)
    from tir_parks where manager_id = auth.uid();
$$;
revoke all on function public.tir_park_my_managed() from public, anon;
grant execute on function public.tir_park_my_managed() to authenticated;

-- The park's bookings for its manager (no codes).
create or replace function public.tir_park_manager_bookings(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', b.id, 'booking_no', b.booking_no, 'trucks', b.trucks, 'start_at', b.start_at, 'end_at', b.end_at,
      'status', case when b.status = 'pending_payment' and b.hold_until <= now() then 'expired' else b.status end,
      'amount', b.amount, 'currency', b.currency, 'paid_mode', b.paid_mode,
      'checked_in_at', b.checked_in_at, 'checked_out_at', b.checked_out_at,
      'driver', u.full_name)
      order by b.start_at desc)
      from (select * from tir_park_bookings where park_id = p_park order by start_at desc limit 300) b
      left join users u on u.id = b.user_id), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_manager_bookings(uuid) from public, anon;
grant execute on function public.tir_park_manager_bookings(uuid) to authenticated;

-- Entry: the code is checked on the server — right park, once only.
create or replace function public.tir_park_booking_check_in(p_park uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_b tir_park_bookings;
begin
  if v_uid is null or not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if (select count(*) from tir_park_code_attempts where user_id = v_uid and at > now() - interval '1 hour') >= 30 then
    raise exception 'too_many_attempts' using errcode = '54000';
  end if;
  select * into v_b from tir_park_bookings where park_id = p_park and code = v_code for update;
  if v_b.id is null then
    -- Counted (not raised, so the attempt is kept for the hourly limit).
    insert into tir_park_code_attempts (user_id, park_id) values (v_uid, p_park);
    return jsonb_build_object('error', 'invalid_code');
  end if;
  if v_b.status in ('checked_in', 'completed') then raise exception 'already_used' using errcode = '22023'; end if;
  if v_b.status <> 'confirmed' then raise exception 'not_valid' using errcode = '22023'; end if;
  if now() < v_b.start_at - interval '6 hours' or now() > v_b.end_at then raise exception 'not_in_time' using errcode = '22023'; end if;
  update tir_park_bookings set status = 'checked_in', checked_in_at = now(), checked_in_by = v_uid, updated_at = now()
   where id = v_b.id returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_check_in(uuid, text) from public, anon;
grant execute on function public.tir_park_booking_check_in(uuid, text) to authenticated;

-- Exit: the booking is completed; its space is free again.
create or replace function public.tir_park_booking_check_out(p_booking uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or not public.is_tir_park_manager(v_b.park_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_b.status <> 'checked_in' then raise exception 'not_checked_in' using errcode = '22023'; end if;
  update tir_park_bookings set status = 'completed', checked_out_at = now(), updated_at = now() where id = p_booking;
end $$;
revoke all on function public.tir_park_booking_check_out(uuid) from public, anon;
grant execute on function public.tir_park_booking_check_out(uuid) to authenticated;

-- 7) Admin: a booking's status (logged). Refund states are not set here —
-- the provider has no refunds yet.
create or replace function public.admin_tir_park_booking_set_status(p_booking uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  perform public._require_admin();
  if p_status not in ('confirmed', 'checked_in', 'completed', 'cancelled', 'expired') then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if p_status in ('confirmed', 'checked_in') and v_b.code is null then raise exception 'not_paid' using errcode = '22023'; end if;
  update tir_park_bookings
     set status = p_status, updated_at = now(),
         checked_in_at = case when p_status = 'checked_in' then coalesce(checked_in_at, now()) else checked_in_at end,
         checked_out_at = case when p_status = 'completed' then coalesce(checked_out_at, now()) else checked_out_at end,
         cancelled_at = case when p_status = 'cancelled' then coalesce(cancelled_at, now()) else cancelled_at end,
         cancel_reason = case when p_status = 'cancelled' then coalesce(cancel_reason, 'admin') else cancel_reason end
   where id = p_booking;
  perform public._admin_log('tir_park.booking_' || p_status, 'tir_park_bookings', p_booking::text,
    jsonb_build_object('status', v_b.status), jsonb_build_object('status', p_status, 'booking_no', v_b.booking_no));
end $$;
revoke all on function public.admin_tir_park_booking_set_status(uuid, text) from public, anon;
grant execute on function public.admin_tir_park_booking_set_status(uuid, text) to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.tir_park_bookings') is null
     or to_regclass('public.tir_park_code_attempts') is null
     or not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target6')
     or to_regprocedure('public.tir_park_manage_apply(uuid, text, double precision, double precision, text, text, text, text[], integer, integer, numeric, text, text, text)') is null
     or to_regprocedure('public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer)') is null
     or to_regprocedure('public.tir_park_booking_payment_create(uuid, text, text)') is null
     or to_regprocedure('public.tir_park_booking_check_in(uuid, text)') is null
     or to_regprocedure('public.admin_tir_park_manager_set(uuid, text)') is null then
    raise exception '0079: final check failed — nothing changed';
  end if;
end $$;

commit;

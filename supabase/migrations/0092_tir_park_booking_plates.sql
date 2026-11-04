-- =====================================================================
-- 0092 — TIR park: one plate per truck in a booking (audit P2-2,
-- 04.11.2026).
--
-- Run AFTER 0091.
--
-- Before: a booking for several TIRs kept only one plate. The other
-- trucks came in as cars without a booking, were charged again at the
-- exit and took an extra place.
--
-- Now:
--   * tir_park_bookings.plates (text[]): every truck's plate, tidied like
--     _tir_park_plate; plate = the first one (as before). Old bookings
--     keep plates = null and are read as [plate].
--   * tir_park_booking_create(park, from, to, trucks, plate, plates) — the
--     new app sends one plate per truck (different plates, as many as
--     TIRs). The 5-argument function of 0086 stays as it is, so an old
--     copy of the app keeps working.
--   * tir_park_stay_enter: any plate of a paid booking comes in on that
--     booking (never more trucks in at once than booked); a truck of a
--     running multi-truck booking that went out may come back on it; the
--     booking is "checked in" from the first truck.
--   * tir_park_stay_exit: the booking is finished only when its last
--     truck has left and every booked truck came (or its time is over);
--     a single-truck booking is finished at its exit, as before.
--   * tir_park_parked / tir_park_manager_bookings: + plates (and the
--     plates still expected); tir_park_owner_summary: trucks of a booking
--     that have not come yet stay "reserved".
--
-- Single-truck bookings work exactly as before. Money is unchanged: each
-- booked truck pays only its overstay after the booking's end.
--
-- Safe: forward-only, re-runnable. One nullable column, functions
-- created / re-created. No row is changed or deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public._tir_park_plate(text)') is null
     or to_regclass('public.tir_park_stays') is null then
    raise exception '0092: run 0082 and 0086 first — nothing changed';
  end if;
end $$;

alter table public.tir_park_bookings add column if not exists plates text[];

-- A booking's plates (old bookings: its one plate).
create or replace function public._tir_park_booking_plates(p_plates text[], p_plate text)
returns text[] language sql immutable set search_path = public, pg_temp as $$
  select case when p_plates is not null and cardinality(p_plates) > 0 then p_plates
              when p_plate is not null then array[p_plate]
              else '{}'::text[] end;
$$;
revoke all on function public._tir_park_booking_plates(text[], text) from public, anon, authenticated;

-- Book with one plate per truck (same rules as 0086 + the plates).
create or replace function public.tir_park_booking_create(p_park uuid, p_from timestamptz, p_to timestamptz, p_trucks integer,
                                                          p_plate text, p_plates text[])
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  p tir_parks;
  v_units integer;
  v_secs double precision;
  v_b tir_park_bookings;
  v_plates text[] := '{}';
  v_one text;
  v_raw text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_trucks is null or p_trucks not between 1 and 50 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  -- One tidy plate per truck, all different.
  foreach v_raw in array coalesce(nullif(p_plates, '{}'::text[]), array[p_plate]) loop
    v_one := public._tir_park_plate(v_raw);
    if v_one is null then raise exception 'invalid_plate' using errcode = '22023'; end if;
    if v_one = any(v_plates) then raise exception 'duplicate_plate' using errcode = '22023'; end if;
    v_plates := v_plates || v_one;
  end loop;
  if cardinality(v_plates) <> p_trucks then raise exception 'plates_count' using errcode = '22023'; end if;
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
                                 status, hold_until, plate, plates)
  values ('TP' || to_char(now(), 'YYMMDD') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6)),
          p_park, v_uid, p_trucks, p_from, p_to, v_units, p.price_unit, p.price,
          round(p.price * v_units * p_trucks, 2), p.currency, 'pending_payment', now() + interval '60 minutes',
          v_plates[1], v_plates)
  returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text, text[]) from public, anon;
grant execute on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text, text[]) to authenticated;

-- A car comes in (by its plate): any plate of a paid booking, once each.
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
  -- Its paid booking for now, if any: this plate is on it (it is not in the
  -- park — checked above) and the booking has a free place among its trucks.
  -- A truck of a running booking that went out may come back on it.
  select b.* into v_b from tir_park_bookings b
   where b.park_id = p_park and b.status in ('confirmed', 'checked_in')
     and v_plate = any(public._tir_park_booking_plates(b.plates, b.plate))
     and b.start_at <= now() + interval '12 hours' and b.end_at > now()
     and (select count(*) from tir_park_stays s where s.booking_id = b.id and s.exited_at is null) < b.trucks
   order by b.start_at limit 1 for update;
  if v_b.id is null and exists (select 1 from tir_park_bookings b where b.park_id = p_park and b.status = 'payment_review'
                                 and v_plate = any(public._tir_park_booking_plates(b.plates, b.plate)) and b.end_at > now()) then
    raise exception 'payment_in_review' using errcode = '22023';
  end if;
  if v_b.id is null and coalesce(p.capacity, 0) - public._tir_park_used(p_park, now(), now() + interval '1 minute') < 1 then
    raise exception 'no_space' using errcode = '23P01';
  end if;
  v_rate := case when p.price_unit = 'hour' then coalesce(p.price, 0) * 24 else coalesce(p.price, 0) end;
  insert into tir_park_stays (park_id, plate, entered_by, booking_id, rate, paid_until, currency)
  values (p_park, v_plate, auth.uid(), v_b.id, round(v_rate, 2), v_b.end_at, p.currency)
  returning * into v_s;
  if v_b.id is not null and v_b.status = 'confirmed' then
    update tir_park_bookings set status = 'checked_in', checked_in_at = now(), checked_in_by = auth.uid(), updated_at = now()
     where id = v_b.id;
  end if;
  return to_jsonb(v_s) || jsonb_build_object('booking_no', v_b.booking_no);
end $$;
revoke all on function public.tir_park_stay_enter(uuid, text) from public, anon;
grant execute on function public.tir_park_stay_enter(uuid, text) to authenticated;

-- A car leaves: the amount is taken now; the booking ends with its last truck.
create or replace function public.tir_park_stay_exit(p_stay uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_s tir_park_stays;
  v_b tir_park_bookings;
begin
  select * into v_s from tir_park_stays where id = p_stay for update;
  if v_s.id is null or auth.uid() is null or not public.can_work_tir_park(v_s.park_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_s.exited_at is not null then raise exception 'already_out' using errcode = '22023'; end if;
  update tir_park_stays
     set exited_at = now(), exited_by = auth.uid(),
         amount = public._tir_park_stay_amount(rate, entered_at, paid_until, now())
   where id = p_stay returning * into v_s;
  if v_s.booking_id is not null then
    select * into v_b from tir_park_bookings where id = v_s.booking_id for update;
    -- Finished: nobody of it is in the park, and every truck came (or its time is over).
    if v_b.status = 'checked_in'
       and not exists (select 1 from tir_park_stays where booking_id = v_b.id and exited_at is null)
       and ((select count(distinct plate) from tir_park_stays where booking_id = v_b.id) >= v_b.trucks or v_b.end_at <= now()) then
      update tir_park_bookings set status = 'completed', checked_out_at = now(), updated_at = now() where id = v_b.id;
    end if;
  end if;
  return to_jsonb(v_s);
end $$;
revoke all on function public.tir_park_stay_exit(uuid) from public, anon;
grant execute on function public.tir_park_stay_exit(uuid) to authenticated;

-- The cars in the park and the paid bookings expected today (+ plates).
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
    -- Paid bookings with trucks still to come today; 'plates' = those not come yet.
    'expected', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.id, 'booking_no', x.booking_no, 'plate', x.left_plates[1], 'plates', to_jsonb(x.left_plates),
                                          'trucks', x.trucks, 'start_at', x.start_at, 'end_at', x.end_at, 'status', x.status)
                       order by x.start_at)
        from (select b.*,
                     array(select pl from unnest(public._tir_park_booking_plates(b.plates, b.plate)) pl
                            where not exists (select 1 from tir_park_stays s where s.booking_id = b.id and s.plate = pl)) as left_plates
                from tir_park_bookings b
               where b.park_id = p_park and b.status in ('confirmed', 'payment_review', 'checked_in')
                 and b.start_at < public._tir_park_today_start() + interval '1 day' and b.end_at > now()) x
       where x.status <> 'checked_in' or cardinality(x.left_plates) > 0), '[]'::jsonb));
end $$;
revoke all on function public.tir_park_parked(uuid) from public, anon;
grant execute on function public.tir_park_parked(uuid) to authenticated;

-- The manager's list of bookings: + every plate.
create or replace function public.tir_park_manager_bookings(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', b.id, 'booking_no', b.booking_no, 'trucks', b.trucks, 'start_at', b.start_at, 'end_at', b.end_at,
      'status', case when b.status = 'pending_payment' and b.hold_until <= now() then 'expired' else b.status end,
      'amount', b.amount, 'currency', b.currency, 'paid_mode', b.paid_mode,
      'receipt_path', b.receipt_path, 'receipt_at', b.receipt_at, 'plate', b.plate,
      'plates', to_jsonb(public._tir_park_booking_plates(b.plates, b.plate)),
      'checked_in_at', b.checked_in_at, 'checked_out_at', b.checked_out_at,
      'driver', u.full_name)
      order by (b.status = 'payment_review') desc, b.start_at desc)
      from (select * from tir_park_bookings where park_id = p_park order by start_at desc limit 300) b
      left join users u on u.id = b.user_id), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_manager_bookings(uuid) from public, anon;
grant execute on function public.tir_park_manager_bookings(uuid) to authenticated;

-- The owner's numbers: a checked-in booking's places not taken by its trucks
-- in the park now stay reserved (the same count as _tir_park_used, 0091).
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
  select coalesce(sum(case when b.status = 'checked_in'
                           then greatest(0, b.trucks - (select count(*) from tir_park_stays s where s.booking_id = b.id and s.exited_at is null))
                           else b.trucks end), 0)::int
    into v_reserved from tir_park_bookings b
   where b.park_id = p_park and b.start_at <= now() and b.end_at > now()
     and (b.status in ('confirmed', 'payment_review', 'checked_in') or (b.status = 'pending_payment' and b.hold_until > now()));
  return jsonb_build_object(
    'capacity', coalesce(p.capacity, 0),
    'in_park', v_in,
    'reserved', v_reserved,
    'free', greatest(0, coalesce(p.capacity, 0) - v_in - v_reserved),
    'currency', p.currency,
    'open', p.booking_open,
    -- Money only for the owner (a worker sees places, not the takings).
    'today_paid', case when not v_owner then null else coalesce((select sum(amount) from tir_park_stays where park_id = p_park and exited_at >= v_today), 0)
                + coalesce((select sum(amount) from tir_park_bookings where park_id = p_park and confirmed_at >= v_today
                            and status in ('confirmed', 'checked_in', 'completed')), 0) end,
    'accruing', case when not v_owner then null else coalesce((select sum(public._tir_park_stay_amount(rate, entered_at, paid_until, now()))
                            from tir_park_stays where park_id = p_park and exited_at is null), 0) end,
    'today_in', (select count(*) from tir_park_stays where park_id = p_park and entered_at >= v_today),
    'today_out', (select count(*) from tir_park_stays where park_id = p_park and exited_at >= v_today));
end $$;
revoke all on function public.tir_park_owner_summary(uuid) from public, anon;
grant execute on function public.tir_park_owner_summary(uuid) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text, text[])') is null
     or to_regprocedure('public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text)') is null then
    raise exception '0092: final check failed — nothing changed';
  end if;
end $$;

commit;

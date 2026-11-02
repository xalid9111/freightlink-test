-- =====================================================================
-- 0082 — The truck's plate on a TIR park booking (owner, 02.11.2026).
--
-- Run AFTER 0079, 0080 and 0081.
--
-- A driver writes his truck's state number when he books (e.g.
-- 99-ZB-911). The park's manager sees it in his list, next to the
-- receipt ("Ödəniş yoxlanılır") and on the confirmed booking, and when
-- he checks the entry code; the driver sees it on his booking.
--
--   * tir_park_bookings.plate (new, nullable: old bookings stay as they
--     are, nothing is rewritten);
--   * _tir_park_plate(): tidies a plate — capitals, spaces / dots → "-"
--     ("99 zb 911" → "99-ZB-911"); 3–15 letters / digits, at least one
--     digit; otherwise the booking is refused with 'invalid_plate';
--   * tir_park_booking_create(park, from, to, trucks, plate) — the same
--     rules as 0080 plus the plate (the 4-argument one stays, so an old
--     app on a phone keeps working until it reloads);
--   * tir_park_manager_bookings: + plate.
--
-- Safe: forward-only, re-runnable. One nullable column, functions created
-- / re-created. No table, column or row is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.tir_parks_booking_now(uuid[])') is null then
    raise exception '0082: run 0079, 0080 and 0081 first — nothing changed';
  end if;
end $$;

alter table public.tir_park_bookings add column if not exists plate text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tir_park_bookings_plate_check') then
    alter table public.tir_park_bookings add constraint tir_park_bookings_plate_check
      check (plate is null or (char_length(plate) between 3 and 15 and plate ~ '^[[:alnum:]][[:alnum:]-]*[[:alnum:]]$'));
  end if;
end $$;

-- "99 zb 911" → "99-ZB-911"; null when it does not look like a plate.
create or replace function public._tir_park_plate(p text)
returns text language plpgsql immutable set search_path = public, pg_temp as $$
declare v text;
begin
  v := upper(btrim(coalesce(p, '')));
  v := regexp_replace(v, '[[:space:]._/]+', '-', 'g');
  v := regexp_replace(v, '-{2,}', '-', 'g');
  v := btrim(v, '-');
  if char_length(v) not between 3 and 15 or v !~ '^[[:alnum:]][[:alnum:]-]*[[:alnum:]]$' or v !~ '[0-9]' then
    return null;
  end if;
  return v;
end $$;
revoke all on function public._tir_park_plate(text) from public, anon, authenticated;

-- 0080's booking + the truck's plate.
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
                                 status, hold_until, plate)
  values ('TP' || to_char(now(), 'YYMMDD') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 6)),
          p_park, v_uid, p_trucks, p_from, p_to, v_units, p.price_unit, p.price,
          round(p.price * v_units * p_trucks, 2), p.currency, 'pending_payment', now() + interval '60 minutes', v_plate)
  returning * into v_b;
  return to_jsonb(v_b) - 'code';
end $$;
revoke all on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text) from public, anon;
grant execute on function public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text) to authenticated;

-- The manager's list: + the truck's plate.
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
      'checked_in_at', b.checked_in_at, 'checked_out_at', b.checked_out_at,
      'driver', u.full_name)
      order by (b.status = 'payment_review') desc, b.start_at desc)
      from (select * from tir_park_bookings where park_id = p_park order by start_at desc limit 300) b
      left join users u on u.id = b.user_id), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_manager_bookings(uuid) from public, anon;
grant execute on function public.tir_park_manager_bookings(uuid) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_park_booking_create(uuid, timestamptz, timestamptz, integer, text)') is null
     or to_regprocedure('public._tir_park_plate(text)') is null then
    raise exception '0082: final check failed — nothing changed';
  end if;
end $$;

commit;

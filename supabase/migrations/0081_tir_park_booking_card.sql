-- =====================================================================
-- 0081 — TIR park booking on the park card (owner, 02.11.2026).
--
-- Run AFTER 0079 and 0080. Builds on their tables; no new table, no
-- second booking system.
--
-- 1. tir_parks_booking_now(p_ids): for the parks on the TIRPark list, is
--    booking open now (0080's tir_park_bookable: approved park + manager,
--    "Rezervasiya aktiv", price, free places, the park's payment details)
--    and how many TIRs it can take right now ("Boş yerlər: 6"). Only a
--    yes / no and a number — no payment details, no driver data.
-- 2. "Rədd et" on a receipt now ends the booking (status 'cancelled',
--    cancel_reason 'payment_rejected', the manager's note kept), so its
--    space is free again at once. Before (0080) it went back to the
--    driver with a new 60-minute hold and kept the space taken.
--
-- Unchanged: a receipt being checked ('payment_review') keeps its space;
-- a cancelled / expired booking frees it; capacity >= free places
-- (0079 check + tir_park_manager_update).
--
-- Safe: forward-only, re-runnable. Two functions created / re-created.
-- No table, column or row is dropped or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.tir_park_pay_details') is null
     or to_regprocedure('public.tir_park_booking_reject_payment(uuid, text)') is null then
    raise exception '0081: run 0079 and 0080 first — nothing changed';
  end if;
end $$;

-- 1) Open / free places now, for many parks at once (the TIRPark list).
create or replace function public.tir_parks_booking_now(p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return '[]'::jsonb; end if;
  if cardinality(p_ids) > 500 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'park_id', p.id,
             'open', public.tir_park_bookable(p),
             'free', case when public.tir_park_bookable(p)
                          then greatest(0, p.bookable - public._tir_park_used(p.id, now(), now() + interval '1 minute'))
                          else 0 end))
      from tir_parks p
     where p.id = any (p_ids) and p.status = 'approved' and p.manager_status = 'approved'), '[]'::jsonb);
end $$;
revoke all on function public.tir_parks_booking_now(uuid[]) from public, anon;
grant execute on function public.tir_parks_booking_now(uuid[]) to authenticated;

-- 2) "Rədd et": the money did not come → the booking ends, the space is free.
create or replace function public.tir_park_booking_reject_payment(p_booking uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_b tir_park_bookings;
begin
  select * into v_b from tir_park_bookings where id = p_booking for update;
  if v_b.id is null or not public.is_tir_park_manager(v_b.park_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if v_b.status <> 'payment_review' then raise exception 'not_in_review' using errcode = '22023'; end if;
  update tir_park_bookings
     set status = 'cancelled', cancelled_at = now(), cancel_reason = 'payment_rejected', hold_until = null,
         reject_note = left(nullif(btrim(coalesce(p_note, '')), ''), 200), updated_at = now()
   where id = p_booking;
end $$;
revoke all on function public.tir_park_booking_reject_payment(uuid, text) from public, anon;
grant execute on function public.tir_park_booking_reject_payment(uuid, text) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_parks_booking_now(uuid[])') is null then
    raise exception '0081: final check failed — nothing changed';
  end if;
end $$;

commit;

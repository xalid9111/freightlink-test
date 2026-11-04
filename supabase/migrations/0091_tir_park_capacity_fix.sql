-- =====================================================================
-- 0091 — TIR park: capacity and money fixes (audit 04.11.2026).
--
-- Run AFTER 0086 (and 0087–0090).
--
-- 1. A truck whose booking time is over but which is still in the park
--    (overstay) counts in the capacity. Before, it was counted neither as
--    a booking (its time was over) nor as a car without a booking (it has
--    a booking), so a full park took one more truck.
-- 2. Trucks in the park now (without a booking, or overstaying) count
--    only for a time that includes NOW. Before, today's trucks lowered
--    the free places of every future day ("Boş yer yoxdur" next week).
--    Bookings themselves are counted for their own days, as before.
-- 3. The stays table (plates, times, money taken) is read directly only
--    by the park's owner (approved manager) and admins. Workers keep
--    working through the server functions (tir_park_parked,
--    tir_park_stay_enter / _exit, tir_park_owner_summary without money),
--    which are unchanged; they can no longer add up the takings with a
--    direct table query.
--
-- Safe: forward-only, re-runnable. One function re-created and one read
-- policy replaced. No table, column or row is changed or deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.tir_park_stays') is null
     or to_regprocedure('public._tir_park_used(uuid, timestamptz, timestamptz, uuid)') is null then
    raise exception '0091: run 0086 first — nothing changed';
  end if;
end $$;

-- 1 + 2) Places taken in [p_from, p_to).
create or replace function public._tir_park_used(p_park uuid, p_from timestamptz, p_to timestamptz, p_except uuid default null)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  -- Bookings for their own days (unchanged rule).
  select (select coalesce(sum(b.trucks), 0)::int
            from tir_park_bookings b
           where b.park_id = p_park and b.start_at < p_to and b.end_at > p_from
             and (p_except is null or b.id <> p_except)
             and (b.status in ('confirmed', 'checked_in', 'payment_review')
                  or (b.status = 'pending_payment' and b.hold_until > now())))
       -- Trucks in the park now, only when the time asked includes now and
       -- only those whose booking is not already counted above (no booking,
       -- overstay after the booking's end, or an early check-in).
       + case when p_from <= now() and p_to > now() then
           (select count(*)::int
              from tir_park_stays s
             where s.park_id = p_park and s.exited_at is null
               and not exists (
                 select 1 from tir_park_bookings b
                  where b.id = s.booking_id
                    and b.start_at < p_to and b.end_at > p_from
                    and (p_except is null or b.id <> p_except)
                    and (b.status in ('confirmed', 'checked_in', 'payment_review')
                         or (b.status = 'pending_payment' and b.hold_until > now()))))
         else 0 end;
$$;
revoke all on function public._tir_park_used(uuid, timestamptz, timestamptz, uuid) from public, anon, authenticated;

-- 3) Direct reading of the stays: the park's owner and admins only.
drop policy if exists "tir_park_stays_read" on public.tir_park_stays;
create policy "tir_park_stays_read" on public.tir_park_stays
  for select to authenticated using (public.is_tir_park_manager(park_id) or public.is_admin());

-- Final check.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'tir_park_stays' and policyname = 'tir_park_stays_read'
                  and qual not like '%can_work_tir_park%') then
    raise exception '0091: final check failed — nothing changed';
  end if;
end $$;

commit;

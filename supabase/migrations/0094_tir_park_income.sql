-- =====================================================================
-- 0094 — TIR park: income by day / month / year (owner, 04.11.2026).
--
-- Run AFTER 0092.
--
-- A tap on "Bu gün" in the owner panel shows three parts: Günlük (today),
-- Aylıq (this month), İllik (this year) — Baku days, the same as "Bu gün".
-- Each part: money taken at the exits (the same sum as "Bu gün") and the
-- paid bookings confirmed in that time (as in Hesabat).
--
-- Only the park's owner and app admins (_tir_park_owner_only) — workers
-- and the park's worker-admin never see money.
--
-- Safe: forward-only, re-runnable, read only. One function created; no
-- table, column or row is changed.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public._tir_park_owner_only(uuid)') is null
     or to_regprocedure('public._tir_park_today_start()') is null then
    raise exception '0094: run 0086 and 0087 first — nothing changed';
  end if;
end $$;

create or replace function public.tir_park_owner_income(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_day   timestamptz := public._tir_park_today_start();
  v_month timestamptz := date_trunc('month', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku';
  v_year  timestamptz := date_trunc('year', now() at time zone 'Asia/Baku') at time zone 'Asia/Baku';
  v_cur text;
begin
  perform public._tir_park_owner_only(p_park);
  select currency into v_cur from tir_parks where id = p_park;
  return jsonb_build_object(
    'currency', coalesce(v_cur, 'AZN'),
    'day_start', v_day, 'month_start', v_month, 'year_start', v_year,
    'day', jsonb_build_object(
      'cars', coalesce((select sum(amount) from tir_park_stays where park_id = p_park and exited_at >= v_day), 0),
      'exits', (select count(*) from tir_park_stays where park_id = p_park and exited_at >= v_day),
      'bookings', coalesce((select sum(amount) from tir_park_bookings where park_id = p_park and confirmed_at >= v_day
                              and status in ('confirmed', 'checked_in', 'completed')), 0)),
    'month', jsonb_build_object(
      'cars', coalesce((select sum(amount) from tir_park_stays where park_id = p_park and exited_at >= v_month), 0),
      'exits', (select count(*) from tir_park_stays where park_id = p_park and exited_at >= v_month),
      'bookings', coalesce((select sum(amount) from tir_park_bookings where park_id = p_park and confirmed_at >= v_month
                              and status in ('confirmed', 'checked_in', 'completed')), 0)),
    'year', jsonb_build_object(
      'cars', coalesce((select sum(amount) from tir_park_stays where park_id = p_park and exited_at >= v_year), 0),
      'exits', (select count(*) from tir_park_stays where park_id = p_park and exited_at >= v_year),
      'bookings', coalesce((select sum(amount) from tir_park_bookings where park_id = p_park and confirmed_at >= v_year
                              and status in ('confirmed', 'checked_in', 'completed')), 0)));
end $$;
revoke all on function public.tir_park_owner_income(uuid) from public, anon;
grant execute on function public.tir_park_owner_income(uuid) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.tir_park_owner_income(uuid)') is null then
    raise exception '0094: final check failed — nothing changed';
  end if;
end $$;

commit;

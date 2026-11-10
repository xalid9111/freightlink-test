-- =====================================================================
-- 0115 — UTEP Reklam: delete a (test) work day, and the month / year
-- cards (owner, 10.11.2026).
--
-- Run AFTER 0114.
--
-- 1. adbiz_delete_day(p_day): the company's owner or the Baş admin deletes
--    one work day with its jobs and its rasxod (the app asks first). The
--    whole day (day, jobs, rasxod) is kept in the history (adbiz_audit
--    'day.delete', who / when). A worker never deletes.
-- 2. adbiz_report_periods(p_company, p_year): for each month of the year
--    and for every year with work: the net income (jobs − expenses) and
--    the sum over the closed days of (the day's money left − the day's
--    target) — what was missed (−) or made over (+). Read-only; owner /
--    Baş admin only; past months are counted from the stored days.
--
-- Safe: forward-only, re-runnable. Two functions; nothing is deleted when
-- this file runs.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.adbiz_company_result_texts_save(uuid, text, text)') is null then
    raise exception '0115: run 0114 first — nothing changed';
  end if;
end $$;

-- 1) Delete one work day (owner / Baş admin), kept whole in the history --------------------------
create or replace function public.adbiz_delete_day(p_day uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_snapshot jsonb;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.adbiz_can_manage(d.company_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  v_snapshot := jsonb_build_object(
    'day', to_jsonb(d),
    'entries', coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at) from adbiz_entries e where e.day_id = d.id), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from adbiz_expenses x where x.day_id = d.id), '[]'::jsonb));
  perform public._adbiz_log(d.company_id, 'day.delete', 'day', d.id::text, v_snapshot, null);
  -- Its jobs and rasxod go with it (on delete cascade).
  delete from adbiz_days where id = d.id;
end $$;

-- 2) Month and year cards: net income and the days' minus / plus against their targets -----------
create or replace function public.adbiz_report_periods(p_company uuid, p_year integer)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_company is null or p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'months', (
      select jsonb_agg(jsonb_build_object('key', m, 'net', inc - exp, 'gap', gap) order by m) from (
        select m,
          coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                    where d.company_id = p_company and extract(year from d.work_date) = p_year and extract(month from d.work_date) = m), 0) inc,
          coalesce((select sum(x.amount) from adbiz_expenses x
                    where x.company_id = p_company and extract(year from x.spent_on) = p_year and extract(month from x.spent_on) = m), 0) exp,
          coalesce((select sum(g.left_money - g.target) from public._adbiz_day_gaps(p_company) g
                    where extract(year from g.work_date) = p_year and extract(month from g.work_date) = m), 0) gap
        from generate_series(1, 12) m) s),
    'years', coalesce((
      select jsonb_agg(jsonb_build_object('key', y, 'net', inc - exp, 'gap', gap) order by y) from (
        select y,
          coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                    where d.company_id = p_company and extract(year from d.work_date) = y), 0) inc,
          coalesce((select sum(x.amount) from adbiz_expenses x where x.company_id = p_company and extract(year from x.spent_on) = y), 0) exp,
          coalesce((select sum(g.left_money - g.target) from public._adbiz_day_gaps(p_company) g where extract(year from g.work_date) = y), 0) gap
        from (select distinct extract(year from work_date)::integer y from adbiz_days where company_id = p_company
              union select extract(year from public._adbiz_today())::integer) ys) s), '[]'::jsonb));
end $$;

-- Each closed day: its money left (jobs − its rasxod) and its own target.
create or replace function public._adbiz_day_gaps(p_company uuid)
returns table (work_date date, left_money numeric, target numeric)
language sql stable security definer set search_path = public, pg_temp as $$
  select d.work_date,
         coalesce((select sum(e.amount) from adbiz_entries e where e.day_id = d.id), 0)
           - coalesce((select sum(x.amount) from adbiz_expenses x where x.day_id = d.id), 0),
         d.target
  from adbiz_days d
  where d.company_id = p_company and d.status = 'closed' and d.target > 0;
$$;
revoke all on function public._adbiz_day_gaps(uuid) from public, anon, authenticated;

do $$
declare f text;
begin
  foreach f in array array['adbiz_delete_day(uuid)', 'adbiz_report_periods(uuid, integer)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;

-- =====================================================================
-- 0116 — UTEP Reklam: the old account carried over (owner, 10.11.2026:
-- "Hesabı köçür, çünki bu proqramla davam edəcəm").
--
-- Run AFTER 0115.
--
-- 1. adbiz_month_import: a month's figures from before the program (net
--    income and the days' minus / plus), per company. Read by the owner /
--    Baş admin; written only through adbiz_month_import_save (owner / Baş
--    admin, audited; both empty = the month's old figures taken off).
-- 2. adbiz_report_periods: every month / year card = the old figures + the
--    days written in the program; a year with old figures is listed too.
--    New months and years simply continue from the program's days.
-- 3. UTEP Reklam's 2026 figures from the owner's table, January to
--    November (November = up to 10.11, the program counts from then on;
--    December is not carried over). Added once — a re-run never changes a
--    month the owner has already set or fixed.
--
-- Safe: forward-only, re-runnable. One new table, functions created /
-- re-created, rows only added. Nothing deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.adbiz_report_periods(uuid, integer)') is null then
    raise exception '0116: run 0115 first — nothing changed';
  end if;
end $$;

-- 1) The old figures ----------------------------------------------------------------------------
create table if not exists public.adbiz_month_import (
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  year integer not null check (year between 2000 and 2100),
  month integer not null check (month between 1 and 12),
  net numeric(12,2) not null default 0 check (abs(net) <= 100000000),
  gap numeric(12,2) not null default 0 check (abs(gap) <= 100000000),
  updated_by uuid references public.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (company_id, year, month)
);
alter table public.adbiz_month_import enable row level security;
revoke all on public.adbiz_month_import from anon, authenticated;
grant select on public.adbiz_month_import to authenticated;
drop policy if exists adbiz_month_import_read on public.adbiz_month_import;
create policy adbiz_month_import_read on public.adbiz_month_import for select to authenticated
  using (public.adbiz_can_manage(company_id));

create or replace function public.adbiz_month_import_save(p_company uuid, p_year integer, p_month integer, p_net numeric, p_gap numeric)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_month_import;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_company is null or p_year is null or p_year < 2000 or p_year > 2100 or p_month is null or p_month < 1 or p_month > 12
     or abs(coalesce(p_net, 0)) > 100000000 or abs(coalesce(p_gap, 0)) > 100000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select * into v_old from adbiz_month_import where company_id = p_company and year = p_year and month = p_month for update;
  if p_net is null and p_gap is null then
    -- Taken off: the month shows only the program's days again.
    delete from adbiz_month_import where company_id = p_company and year = p_year and month = p_month;
  else
    insert into adbiz_month_import (company_id, year, month, net, gap, updated_by, updated_at)
    values (p_company, p_year, p_month, round(coalesce(p_net, 0), 2), round(coalesce(p_gap, 0), 2), auth.uid(), now())
    on conflict (company_id, year, month) do update
      set net = excluded.net, gap = excluded.gap, updated_by = excluded.updated_by, updated_at = now();
  end if;
  perform public._adbiz_log(p_company, 'month.import', 'month', format('%s-%s', p_year, lpad(p_month::text, 2, '0')),
    case when v_old.company_id is null then null else jsonb_build_object('net', v_old.net, 'gap', v_old.gap) end,
    case when p_net is null and p_gap is null then null
         else jsonb_build_object('net', round(coalesce(p_net, 0), 2), 'gap', round(coalesce(p_gap, 0), 2)) end);
end $$;

-- 2) The cards: the old figures + the program's days ----------------------------------------------
create or replace function public.adbiz_report_periods(p_company uuid, p_year integer)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_company is null or p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'months', (
      select jsonb_agg(jsonb_build_object('key', m, 'net', inc - exp + imp_net, 'gap', gap + imp_gap,
                                          'imported', has_imp, 'imp_net', imp_net, 'imp_gap', imp_gap) order by m) from (
        select m,
          coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                    where d.company_id = p_company and extract(year from d.work_date) = p_year and extract(month from d.work_date) = m), 0) inc,
          coalesce((select sum(x.amount) from adbiz_expenses x
                    where x.company_id = p_company and extract(year from x.spent_on) = p_year and extract(month from x.spent_on) = m), 0) exp,
          coalesce((select sum(g.left_money - g.target) from public._adbiz_day_gaps(p_company) g
                    where extract(year from g.work_date) = p_year and extract(month from g.work_date) = m), 0) gap,
          coalesce((select i.net from adbiz_month_import i where i.company_id = p_company and i.year = p_year and i.month = m), 0) imp_net,
          coalesce((select i.gap from adbiz_month_import i where i.company_id = p_company and i.year = p_year and i.month = m), 0) imp_gap,
          exists (select 1 from adbiz_month_import i where i.company_id = p_company and i.year = p_year and i.month = m) has_imp
        from generate_series(1, 12) m) s),
    'years', coalesce((
      select jsonb_agg(jsonb_build_object('key', y, 'net', inc - exp + imp_net, 'gap', gap + imp_gap,
                                          'imported', imp_net <> 0 or imp_gap <> 0, 'imp_net', imp_net, 'imp_gap', imp_gap) order by y) from (
        select y,
          coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                    where d.company_id = p_company and extract(year from d.work_date) = y), 0) inc,
          coalesce((select sum(x.amount) from adbiz_expenses x where x.company_id = p_company and extract(year from x.spent_on) = y), 0) exp,
          coalesce((select sum(g.left_money - g.target) from public._adbiz_day_gaps(p_company) g where extract(year from g.work_date) = y), 0) gap,
          coalesce((select sum(i.net) from adbiz_month_import i where i.company_id = p_company and i.year = y), 0) imp_net,
          coalesce((select sum(i.gap) from adbiz_month_import i where i.company_id = p_company and i.year = y), 0) imp_gap
        from (select distinct extract(year from work_date)::integer y from adbiz_days where company_id = p_company
              union select year from adbiz_month_import where company_id = p_company
              union select extract(year from public._adbiz_today())::integer) ys) s), '[]'::jsonb));
end $$;

do $$
declare f text;
begin
  foreach f in array array['adbiz_month_import_save(uuid, integer, integer, numeric, numeric)', 'adbiz_report_periods(uuid, integer)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- 3) UTEP Reklam's 2026 figures from the owner's table (once; never over the owner's own) ------------
insert into public.adbiz_month_import (company_id, year, month, net, gap)
select 'ad0b1200-0000-4000-8000-000000000001'::uuid, 2026, v.m, v.net, v.gap
from (values (1, 5784, -215), (2, 5455, -544), (3, 6010, 11), (4, 5732, -267), (5, 6076, 77), (6, 5632, -367),
             (7, 7456, 1457), (8, 6479, 480), (9, 6824, 825), (10, 5038, -961), (11, 1306, -4693)) v(m, net, gap)
where exists (select 1 from public.adbiz_companies where id = 'ad0b1200-0000-4000-8000-000000000001')
on conflict (company_id, year, month) do nothing;

notify pgrst, 'reload schema';
commit;

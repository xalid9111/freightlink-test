-- =====================================================================
-- 0133 — UTEP Reklam: the monthly target and the month's "Ümumi mənfi"
-- (owner, 21.11.2026: "ümumi mənfi hesablaması daim görünməlidir … ay
-- ərzində 6110 AZN-i işçi keçməlidir … 6110 olub olmamasını özüm təyin
-- edəcəm … ötən aylar 5999 qalsın, bu aydan sonra bütün aylar 6110-la").
--   * adbiz_month_targets: the Baş admin's monthly target of a company,
--     counted from the month it is set (company, from_month, amount);
--     a month uses the latest target set for it or before it. UTEP Reklam
--     starts with 6110 AZN from November 2026 (inserted once).
--   * A month WITH a target: gap = the month's net (jobs − expenses + the
--     old account's net) − target × the workers who worked that month (at
--     least one once the month has begun). A month BEFORE any target keeps
--     the old way (the days' gaps + the old account's own gap) — the old
--     figures (5999) never change.
--   * adbiz_month_target_set: Baş admin only, audited ('month_target').
--   * adbiz_my_month(user, date): the worker's own month on his notebook
--     (target, collected = his jobs − his day rasxod (+ the old account's
--     net when he is the month's only worker), gap); the worker himself or
--     the company's owner / the Baş admin.
-- Safe: forward-only, re-runnable; one new table, new functions,
-- adbiz_report_periods replaced (same signature); nothing deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.adbiz_month_import') is null then
    raise exception '0133: run 0110–0116 (UTEP Reklam) first — nothing changed';
  end if;
end $$;

create table if not exists public.adbiz_month_targets (
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  from_month date not null check (extract(day from from_month) = 1),
  amount numeric(12,2) not null check (amount > 0 and amount <= 100000000),
  set_by uuid references public.users(id) on delete set null,
  set_at timestamptz not null default now(),
  primary key (company_id, from_month)
);
alter table public.adbiz_month_targets enable row level security;
revoke all on public.adbiz_month_targets from anon, authenticated;
grant select on public.adbiz_month_targets to authenticated;
drop policy if exists adbiz_month_targets_read on public.adbiz_month_targets;
create policy adbiz_month_targets_read on public.adbiz_month_targets for select to authenticated
  using (coalesce(public.is_chief_admin(), false) or company_id = public.adbiz_my_company());

-- UTEP Reklam: 6110 AZN from November 2026 (once; never over a later fix).
insert into public.adbiz_month_targets (company_id, from_month, amount)
select c.id, date '2026-11-01', 6110 from public.adbiz_companies c
 where c.id = 'ad0b1200-0000-4000-8000-000000000001'
on conflict (company_id, from_month) do nothing;

-- The target of one month (null = before any target: the old way).
create or replace function public._adbiz_month_target(p_company uuid, p_year integer, p_month integer)
returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select t.amount from adbiz_month_targets t
   where t.company_id = p_company and t.from_month <= make_date(p_year, p_month, 1)
   order by t.from_month desc limit 1;
$$;
revoke all on function public._adbiz_month_target(uuid, integer, integer) from public, anon, authenticated;

-- One month of a company: net and gap (new way with a target, else the old way).
create or replace function public._adbiz_month_sum(p_company uuid, p_year integer, p_month integer)
returns table (net numeric, gap numeric, imp_net numeric, imp_gap numeric, has_imp boolean, target numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_inc numeric; v_exp numeric; v_days_gap numeric; v_t numeric; v_workers integer;
  v_start date := make_date(p_year, p_month, 1);
begin
  select coalesce(sum(e.amount), 0) into v_inc from adbiz_entries e join adbiz_days d on d.id = e.day_id
   where d.company_id = p_company and d.work_date >= v_start and d.work_date < v_start + interval '1 month';
  select coalesce(sum(x.amount), 0) into v_exp from adbiz_expenses x
   where x.company_id = p_company and x.spent_on >= v_start and x.spent_on < v_start + interval '1 month';
  select coalesce(sum(g.left_money - g.target), 0) into v_days_gap from public._adbiz_day_gaps(p_company) g
   where g.work_date >= v_start and g.work_date < v_start + interval '1 month';
  select coalesce(i.net, 0), coalesce(i.gap, 0), i.company_id is not null into imp_net, imp_gap, has_imp
    from (select 1) one left join adbiz_month_import i on i.company_id = p_company and i.year = p_year and i.month = p_month;
  v_t := public._adbiz_month_target(p_company, p_year, p_month);
  net := v_inc - v_exp + imp_net;
  target := v_t;
  if v_t is null then
    gap := v_days_gap + imp_gap;
  elsif v_start > public._adbiz_today() then
    gap := 0; -- a month not begun yet
  else
    select count(distinct d.user_id) into v_workers from adbiz_days d
     where d.company_id = p_company and d.work_date >= v_start and d.work_date < v_start + interval '1 month';
    gap := net - v_t * greatest(v_workers, 1);
  end if;
  return next;
end $$;
revoke all on function public._adbiz_month_sum(uuid, integer, integer) from public, anon, authenticated;

-- The month / year cards (0115 / 0116), now with the monthly target.
create or replace function public.adbiz_report_periods(p_company uuid, p_year integer)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_company is null or p_year is null or p_year < 2000 or p_year > 2100 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'months', (
      select jsonb_agg(jsonb_build_object('key', m, 'net', s.net, 'gap', s.gap, 'imported', s.has_imp,
                                          'imp_net', s.imp_net, 'imp_gap', s.imp_gap, 'target', s.target) order by m)
        from generate_series(1, 12) m, lateral public._adbiz_month_sum(p_company, p_year, m) s),
    'years', coalesce((
      select jsonb_agg(jsonb_build_object('key', y, 'net', net, 'gap', gap, 'imported', imp_net <> 0 or imp_gap <> 0,
                                          'imp_net', imp_net, 'imp_gap', imp_gap) order by y) from (
        select ys.y, sum(s.net) net, sum(s.gap) gap, sum(s.imp_net) imp_net, sum(s.imp_gap) imp_gap
          from (select distinct extract(year from work_date)::integer y from adbiz_days where company_id = p_company
                union select year from adbiz_month_import where company_id = p_company
                union select extract(year from public._adbiz_today())::integer) ys,
               generate_series(1, 12) m, lateral public._adbiz_month_sum(p_company, ys.y, m) s
         group by ys.y) t), '[]'::jsonb));
end $$;

-- The Baş admin sets the monthly target from a month on (audited).
create or replace function public.adbiz_month_target_set(p_company uuid, p_from date, p_amount numeric)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_from date; v_old numeric;
begin
  perform public._adbiz_require_chief();
  if p_company is null or p_from is null or p_amount is null or p_amount <= 0 or p_amount > 100000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if not exists (select 1 from adbiz_companies where id = p_company) then raise exception 'not_found' using errcode = 'P0002'; end if;
  v_from := date_trunc('month', p_from)::date;
  v_old := public._adbiz_month_target(p_company, extract(year from v_from)::integer, extract(month from v_from)::integer);
  insert into adbiz_month_targets (company_id, from_month, amount, set_by, set_at)
  values (p_company, v_from, round(p_amount, 2), auth.uid(), now())
  on conflict (company_id, from_month) do update set amount = excluded.amount, set_by = excluded.set_by, set_at = now();
  perform public._adbiz_log(p_company, 'month_target', 'company', p_company::text,
    case when v_old is null then null else jsonb_build_object('amount', v_old) end,
    jsonb_build_object('from', v_from, 'amount', round(p_amount, 2)));
end $$;

-- A worker's own month (his notebook): target, collected, gap.
create or replace function public.adbiz_my_month(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_company uuid; v_start date; v_t numeric; v_inc numeric; v_exp numeric; v_imp numeric := 0;
  v_others integer; v_days integer;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_user is null or p_date is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select m.company_id into v_company from adbiz_members m where m.user_id = p_user;
  if v_company is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not (p_user = auth.uid() and public.adbiz_my_company() = v_company) and not public.adbiz_can_manage(v_company) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  v_start := date_trunc('month', p_date)::date;
  v_t := public._adbiz_month_target(v_company, extract(year from v_start)::integer, extract(month from v_start)::integer);
  select coalesce(sum(e.amount), 0) into v_inc from adbiz_entries e join adbiz_days d on d.id = e.day_id
   where d.user_id = p_user and d.company_id = v_company and d.work_date >= v_start and d.work_date < v_start + interval '1 month';
  select coalesce(sum(x.amount), 0) into v_exp from adbiz_expenses x join adbiz_days d on d.id = x.day_id
   where d.user_id = p_user and d.company_id = v_company and d.work_date >= v_start and d.work_date < v_start + interval '1 month';
  select count(*) into v_days from adbiz_days d
   where d.user_id = p_user and d.company_id = v_company and d.work_date >= v_start and d.work_date < v_start + interval '1 month';
  select count(distinct d.user_id) into v_others from adbiz_days d
   where d.company_id = v_company and d.user_id <> p_user and d.work_date >= v_start and d.work_date < v_start + interval '1 month';
  -- The old account (before the program) counts for the month's only worker.
  if v_others = 0 then
    select coalesce(i.net, 0) into v_imp from adbiz_month_import i
     where i.company_id = v_company and i.year = extract(year from v_start) and i.month = extract(month from v_start);
    v_imp := coalesce(v_imp, 0);
  end if;
  return jsonb_build_object('month', v_start, 'target', v_t, 'collected', v_inc - v_exp + v_imp, 'days', v_days,
                            'gap', case when v_t is null then null else v_inc - v_exp + v_imp - v_t end);
end $$;

do $$
declare f text;
begin
  foreach f in array array['adbiz_report_periods(uuid, integer)', 'adbiz_month_target_set(uuid, date, numeric)', 'adbiz_my_month(uuid, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

commit;

notify pgrst, 'reload schema';

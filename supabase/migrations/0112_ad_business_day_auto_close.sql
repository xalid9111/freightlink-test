-- =====================================================================
-- 0112 — UTEP Reklam: the day closes by itself at 23:59 (Baku), and a
-- worker may re-open the day he closed by mistake (owner, 10.11.2026).
--
-- Run AFTER 0111.
--
-- 1. A work day ends at 23:59 Baku time: from 00:00 an open day of an
--    earlier date counts as closed — it is closed (closed_at = that day
--    23:59:59 Baku, closed_by empty = "automatic", audited) the moment
--    anybody of the company opens the notebook / the business page
--    (adbiz_sweep), opens the next day (adbiz_open_day), or — when the
--    project has pg_cron switched on — every night right after 23:59 Baku.
--    The worker writes only into TODAY's open day (also before the sweep).
-- 2. A worker who closed today's day himself may open it again the same
--    day (adbiz_reopen_day) and go on adding jobs / rasxod; a day closed
--    by the owner / Baş admin, closed automatically or of an earlier date
--    stays the owner's / Baş admin's to re-open, as before. Audited.
--
-- Safe: forward-only, re-runnable. Functions created / re-created (and the
-- nightly job only when pg_cron is already there). Nothing is dropped,
-- deleted or rewritten except closing the forgotten open days of earlier
-- dates, as the owner asked.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.adbiz_add_day_expense(uuid, text, numeric, uuid)') is null then
    raise exception '0112: run 0110 and 0111 first — nothing changed';
  end if;
end $$;

-- 1) Close the open days of earlier dates (one company, or every company) ---------------
create or replace function public._adbiz_close_stale(p_company uuid default null)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n integer;
begin
  with closed as (
    update adbiz_days d
       set status = 'closed',
           closed_at = ((d.work_date + 1)::timestamp at time zone 'Asia/Baku') - interval '1 second',
           closed_by = null
     where d.status = 'open'
       and d.work_date < public._adbiz_today()
       and (p_company is null or d.company_id = p_company)
    returning d.id, d.company_id, d.work_date
  ), logged as (
    insert into adbiz_audit (company_id, actor_id, action, entity, entity_id, old_value, new_value)
    select c.company_id, null, 'day.auto_close', 'day', c.id::text,
           jsonb_build_object('status', 'open'), jsonb_build_object('status', 'closed', 'at', '23:59', 'work_date', c.work_date)
    from closed c
    returning 1
  )
  select count(*) into v_n from logged;
  return v_n;
end $$;
revoke all on function public._adbiz_close_stale(uuid) from public, anon, authenticated;

-- Called by the app when the notebook / business page opens.
create or replace function public.adbiz_sweep()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v_company uuid := public.adbiz_my_company();
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if coalesce(public.is_chief_admin(), false) then return public._adbiz_close_stale(null); end if;
  if v_company is null then return 0; end if;
  return public._adbiz_close_stale(v_company);
end $$;
revoke all on function public.adbiz_sweep() from public, anon;
grant execute on function public.adbiz_sweep() to authenticated;

-- 2) Opening today closes the forgotten earlier day first -----------------------------------
create or replace function public.adbiz_open_day()
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_company uuid := public.adbiz_my_company(); v_day uuid; v_target numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if v_company is null then raise exception 'not_member' using errcode = '42501'; end if;
  perform public._adbiz_close_stale(v_company);
  select id into v_day from adbiz_days where user_id = auth.uid() and work_date = public._adbiz_today();
  if v_day is not null then return v_day; end if;
  select coalesce(m.personal_target, c.daily_target) into v_target
  from adbiz_members m join adbiz_companies c on c.id = m.company_id where m.user_id = auth.uid();
  insert into adbiz_days (company_id, user_id, work_date, target)
  values (v_company, auth.uid(), public._adbiz_today(), coalesce(v_target, 0))
  on conflict (user_id, work_date) do nothing
  returning id into v_day;
  if v_day is null then
    select id into v_day from adbiz_days where user_id = auth.uid() and work_date = public._adbiz_today();
  end if;
  return v_day;
end $$;

-- 3) The worker writes only into TODAY's open day ----------------------------------------------
create or replace function public._adbiz_day_writable(p_day adbiz_days)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.adbiz_can_manage(p_day.company_id)
      or (p_day.user_id = auth.uid() and p_day.status = 'open' and p_day.work_date = public._adbiz_today()
          and public.adbiz_my_company() = p_day.company_id);
$$;
revoke all on function public._adbiz_day_writable(adbiz_days) from public, anon, authenticated;

create or replace function public.adbiz_add_day_expense(p_day uuid, p_title text, p_amount numeric, p_client_key uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_title is null or char_length(btrim(p_title)) = 0 or char_length(btrim(p_title)) > 120
     or p_amount is null or p_amount <= 0 or p_amount > 1000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if p_client_key is not null then
    select id into v_id from adbiz_expenses where client_key = p_client_key;
    if v_id is not null then return v_id; end if;
  end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public._adbiz_day_writable(d) then
    raise exception using message = case when d.user_id = auth.uid() and (d.status = 'closed' or d.work_date < public._adbiz_today())
      then 'day_closed' else 'not_allowed' end, errcode = '42501';
  end if;
  insert into adbiz_expenses (company_id, spent_on, title, amount, client_key, created_by, day_id, user_id)
  values (d.company_id, d.work_date, btrim(p_title), round(p_amount, 2), p_client_key, auth.uid(), d.id, d.user_id)
  returning id into v_id;
  perform public._adbiz_log(d.company_id, 'expense.add', 'expense', v_id::text, null,
    jsonb_build_object('day_id', d.id, 'user_id', d.user_id, 'title', btrim(p_title), 'amount', round(p_amount, 2)));
  return v_id;
end $$;

-- adbiz_add_entry (0110) raises 'not_allowed' / 'day_closed' through
-- _adbiz_day_writable above; a past open day is refused for the worker.
create or replace function public.adbiz_add_entry(p_day uuid, p_title text, p_amount numeric, p_client_key uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_title is null or char_length(btrim(p_title)) = 0 or char_length(btrim(p_title)) > 120
     or p_amount is null or p_amount <= 0 or p_amount > 1000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if p_client_key is not null then
    select id into v_id from adbiz_entries where client_key = p_client_key;
    if v_id is not null then return v_id; end if;
  end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public._adbiz_day_writable(d) then
    raise exception using message = case when d.user_id = auth.uid() and (d.status = 'closed' or d.work_date < public._adbiz_today())
      then 'day_closed' else 'not_allowed' end, errcode = '42501';
  end if;
  insert into adbiz_entries (day_id, company_id, user_id, title, amount, client_key, created_by)
  values (d.id, d.company_id, d.user_id, btrim(p_title), round(p_amount, 2), p_client_key, auth.uid())
  returning id into v_id;
  if auth.uid() <> d.user_id or d.status = 'closed' then
    perform public._adbiz_log(d.company_id, 'entry.add', 'entry', v_id::text, null,
      jsonb_build_object('day_id', d.id, 'title', btrim(p_title), 'amount', round(p_amount, 2)));
  end if;
  return v_id;
end $$;

-- 4) Re-open: the owner / Baş admin any day; the worker only TODAY's day he
--    closed himself ----------------------------------------------------------------------------
create or replace function public.adbiz_reopen_day(p_day uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_own boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  v_own := d.user_id = auth.uid() and d.closed_by = auth.uid() and d.work_date = public._adbiz_today()
           and public.adbiz_my_company() = d.company_id;
  if not (public.adbiz_can_manage(d.company_id) or v_own) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if d.status = 'open' then return; end if;
  update adbiz_days set status = 'open', closed_at = null, closed_by = null where id = p_day;
  perform public._adbiz_log(d.company_id, 'day.reopen', 'day', p_day::text,
    jsonb_build_object('status', 'closed', 'closed_at', d.closed_at, 'closed_by', d.closed_by),
    jsonb_build_object('status', 'open', 'by', case when v_own then 'worker' else 'manager' end));
end $$;

do $$
declare f text;
begin
  foreach f in array array['adbiz_open_day()', 'adbiz_add_day_expense(uuid, text, numeric, uuid)',
                           'adbiz_add_entry(uuid, text, numeric, uuid)', 'adbiz_reopen_day(uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- 5) Every night right after 23:59 Baku (00:00 Baku = 20:00 UTC) — only when pg_cron
--    is already on; the closed time written is 23:59:59 of that day ---------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('adbiz-auto-close', '0 20 * * *', 'select public._adbiz_close_stale(null)');
  end if;
exception when others then
  -- pg_cron missing or not allowed: the days still close when the app sweeps.
  null;
end $$;

-- Forgotten open days of earlier dates: closed now, once.
select public._adbiz_close_stale(null);

notify pgrst, 'reload schema';
commit;

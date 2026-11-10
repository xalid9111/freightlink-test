-- =====================================================================
-- 0113 — UTEP Reklam: the owner's words for the worker, the target on /
-- off, and jobs paid by card (owner, 10.11.2026).
--
-- Run AFTER 0112.
--
-- 1. The company's owner (and the Baş admin) writes the words the workers
--    see instead of "Hədəfə qalan" (adbiz_companies.target_label) and a
--    task for every worker (adbiz_companies.task_note); a task for one
--    worker on his membership (adbiz_members.task_note).
--    adbiz_company_texts_save / adbiz_member_task_save — audited.
-- 2. The switch on the "Gündəlik hədəf" card (adbiz_companies.show_target):
--    off = the workers see no target, bar or "Mənfi" (only jobs and
--    rasxod). The target itself stays the Baş admin's (0110).
--    adbiz_company_show_target — owner / Baş admin, audited.
-- 3. A job paid by card (adbiz_entries.paid_card, a tick): set when the
--    job is added (adbiz_add_entry … p_card) or changed later with
--    adbiz_entry_set_card — the worker only on his own TODAY's open day,
--    the owner / Baş admin on any day; every change audited. Card money is
--    income like any other; the report shows it apart ('card', per worker).
--
-- 4. A fix: for an account that is in no company, the rights checks
--    (adbiz_can_manage / _adbiz_day_writable) gave "unknown" (null)
--    instead of "no", and a null check lets the call through. Both now
--    answer a plain yes / no (also the worker's own re-open), so a stranger
--    is always refused.
--
-- Safe: forward-only, re-runnable. Nullable / defaulted columns, functions
-- created / re-created; adbiz_add_entry gets a 5th argument with a default
-- (the old 4-argument function is replaced, old calls still work). Nothing
-- deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.adbiz_sweep()') is null then
    raise exception '0113: run 0110, 0111 and 0112 first — nothing changed';
  end if;
end $$;

-- 1) Columns ------------------------------------------------------------------------------
alter table public.adbiz_companies add column if not exists target_label text;
alter table public.adbiz_companies add column if not exists task_note text;
alter table public.adbiz_companies add column if not exists show_target boolean not null default true;
alter table public.adbiz_members add column if not exists task_note text;
alter table public.adbiz_entries add column if not exists paid_card boolean not null default false;
alter table public.adbiz_companies enable row level security;
alter table public.adbiz_members enable row level security;
alter table public.adbiz_entries enable row level security;

-- 0) The rights checks answer yes / no, never null (a stranger was let through) ---------------
create or replace function public.adbiz_can_manage(p_company uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(public.is_chief_admin(), false)
      or coalesce(public.adbiz_my_role() = 'owner' and public.adbiz_my_company() = p_company, false);
$$;
revoke all on function public.adbiz_can_manage(uuid) from public, anon;
grant execute on function public.adbiz_can_manage(uuid) to authenticated;

create or replace function public._adbiz_day_writable(p_day adbiz_days)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.adbiz_can_manage(p_day.company_id)
      or coalesce(p_day.user_id = auth.uid() and p_day.status = 'open' and p_day.work_date = public._adbiz_today()
                  and public.adbiz_my_company() = p_day.company_id, false);
$$;
revoke all on function public._adbiz_day_writable(adbiz_days) from public, anon, authenticated;

-- The worker's own re-open (0112) with the same plain yes / no.
create or replace function public.adbiz_reopen_day(p_day uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_own boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  v_own := coalesce(d.user_id = auth.uid() and d.closed_by = auth.uid() and d.work_date = public._adbiz_today()
                    and public.adbiz_my_company() = d.company_id, false);
  if not (public.adbiz_can_manage(d.company_id) or v_own) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if d.status = 'open' then return; end if;
  update adbiz_days set status = 'open', closed_at = null, closed_by = null where id = p_day;
  perform public._adbiz_log(d.company_id, 'day.reopen', 'day', p_day::text,
    jsonb_build_object('status', 'closed', 'closed_at', d.closed_at, 'closed_by', d.closed_by),
    jsonb_build_object('status', 'open', 'by', case when v_own then 'worker' else 'manager' end));
end $$;

-- Empty text = nothing (the app shows its own words then).
create or replace function public._adbiz_text(p text, p_max integer)
returns text language plpgsql immutable set search_path = public, pg_temp as $$
begin
  if p is null or char_length(btrim(p)) = 0 then return null; end if;
  if char_length(btrim(p)) > p_max then raise exception 'invalid_argument' using errcode = '22023'; end if;
  return btrim(p);
end $$;
revoke all on function public._adbiz_text(text, integer) from public, anon, authenticated;

-- 2) The owner's words: the "Hədəfə qalan" caption and the task for every worker --------------
create or replace function public.adbiz_company_texts_save(p_company uuid, p_label text, p_task text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_companies; v_label text := public._adbiz_text(p_label, 60); v_task text := public._adbiz_text(p_task, 500);
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select * into v_old from adbiz_companies where id = p_company for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update adbiz_companies set target_label = v_label, task_note = v_task, updated_at = now() where id = p_company;
  perform public._adbiz_log(p_company, 'company.texts', 'company', p_company::text,
    jsonb_build_object('target_label', v_old.target_label, 'task_note', v_old.task_note),
    jsonb_build_object('target_label', v_label, 'task_note', v_task));
end $$;

-- A task for one worker (his own card only).
create or replace function public.adbiz_member_task_save(p_user uuid, p_task text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_members; v_task text := public._adbiz_text(p_task, 500);
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_old from adbiz_members where user_id = p_user for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.adbiz_can_manage(v_old.company_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  update adbiz_members set task_note = v_task, updated_at = now() where user_id = p_user;
  perform public._adbiz_log(v_old.company_id, 'member.task', 'member', p_user::text,
    jsonb_build_object('task_note', v_old.task_note), jsonb_build_object('task_note', v_task));
end $$;

-- 3) The target shown to the workers or not -----------------------------------------------------
create or replace function public.adbiz_company_show_target(p_company uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_on is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select show_target into v_old from adbiz_companies where id = p_company for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update adbiz_companies set show_target = p_on, updated_at = now() where id = p_company;
  perform public._adbiz_log(p_company, 'company.show_target', 'company', p_company::text,
    jsonb_build_object('show_target', v_old), jsonb_build_object('show_target', p_on));
end $$;

-- 4) A job paid by card: the tick when it is added … --------------------------------------------
drop function if exists public.adbiz_add_entry(uuid, text, numeric, uuid);
create or replace function public.adbiz_add_entry(p_day uuid, p_title text, p_amount numeric, p_client_key uuid default null,
                                                  p_card boolean default false)
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
  insert into adbiz_entries (day_id, company_id, user_id, title, amount, client_key, created_by, paid_card)
  values (d.id, d.company_id, d.user_id, btrim(p_title), round(p_amount, 2), p_client_key, auth.uid(), coalesce(p_card, false))
  returning id into v_id;
  if auth.uid() <> d.user_id or d.status = 'closed' then
    perform public._adbiz_log(d.company_id, 'entry.add', 'entry', v_id::text, null,
      jsonb_build_object('day_id', d.id, 'title', btrim(p_title), 'amount', round(p_amount, 2), 'paid_card', coalesce(p_card, false)));
  end if;
  return v_id;
end $$;

-- … and later: the worker on his own TODAY's open day (a mistake), the owner / Baş admin any day.
create or replace function public.adbiz_entry_set_card(p_entry uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare e adbiz_entries; d adbiz_days;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_on is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select * into e from adbiz_entries where id = p_entry for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into d from adbiz_days where id = e.day_id for update;
  if not public._adbiz_day_writable(d) then
    raise exception using message = case when d.user_id = auth.uid() and (d.status = 'closed' or d.work_date < public._adbiz_today())
      then 'day_closed' else 'not_allowed' end, errcode = '42501';
  end if;
  if e.paid_card = p_on then return; end if;
  update adbiz_entries set paid_card = p_on, updated_at = now() where id = p_entry;
  perform public._adbiz_log(e.company_id, 'entry.card', 'entry', p_entry::text,
    jsonb_build_object('title', e.title, 'amount', e.amount, 'paid_card', e.paid_card),
    jsonb_build_object('paid_card', p_on));
end $$;

-- 5) The report: card money apart (the company and each worker), the worker's task ---------------
create or replace function public.adbiz_report(p_company uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_income numeric; v_card numeric; v_exp numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_company is null or p_from is null or p_to is null or p_to < p_from then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select coalesce(sum(e.amount), 0), coalesce(sum(e.amount) filter (where e.paid_card), 0) into v_income, v_card
  from adbiz_entries e join adbiz_days d on d.id = e.day_id
  where d.company_id = p_company and d.work_date between p_from and p_to;
  select coalesce(sum(amount), 0) into v_exp from adbiz_expenses where company_id = p_company and spent_on between p_from and p_to;
  return jsonb_build_object(
    'income', v_income, 'card', v_card, 'cash', v_income - v_card, 'expenses', v_exp, 'net', v_income - v_exp,
    'days_open', (select count(*) from adbiz_days where company_id = p_company and work_date between p_from and p_to and status = 'open'),
    'days_closed', (select count(*) from adbiz_days where company_id = p_company and work_date between p_from and p_to and status = 'closed'),
    'workers', coalesce((
      select jsonb_agg(w order by w->>'name') from (
        select jsonb_build_object('user_id', u.id, 'name', u.full_name, 'role', m.role, 'is_active', m.is_active,
          'personal_target', m.personal_target, 'task_note', m.task_note,
          'total', coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                             where d.user_id = u.id and d.company_id = p_company and d.work_date between p_from and p_to), 0),
          'card', coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                            where d.user_id = u.id and d.company_id = p_company and d.work_date between p_from and p_to and e.paid_card), 0),
          'days', (select count(*) from adbiz_days d where d.user_id = u.id and d.company_id = p_company and d.work_date between p_from and p_to)) w
        from adbiz_members m join users u on u.id = m.user_id where m.company_id = p_company) s), '[]'::jsonb),
    'by_day', coalesce((
      select jsonb_agg(jsonb_build_object('date', x.work_date, 'income', x.income) order by x.work_date desc) from (
        select d.work_date, coalesce(sum(e.amount), 0) income from adbiz_days d left join adbiz_entries e on e.day_id = d.id
        where d.company_id = p_company and d.work_date between p_from and p_to group by d.work_date) x), '[]'::jsonb));
end $$;

-- 6) Rights on the functions ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['adbiz_company_texts_save(uuid, text, text)', 'adbiz_member_task_save(uuid, text)',
                           'adbiz_company_show_target(uuid, boolean)', 'adbiz_add_entry(uuid, text, numeric, uuid, boolean)',
                           'adbiz_entry_set_card(uuid, boolean)', 'adbiz_report(uuid, date, date)', 'adbiz_reopen_day(uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
commit;

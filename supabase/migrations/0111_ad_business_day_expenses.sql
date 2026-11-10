-- =====================================================================
-- 0111 — UTEP Reklam: the worker's day expenses (rasxod) and no own
-- changes after saving (owner, 10.11.2026).
--
-- Run AFTER 0110.
--
-- 1. A worker writes the day's expenses (name + amount) into his own OPEN
--    day (adbiz_add_day_expense). They are company expenses
--    (adbiz_expenses) bound to the day and the worker (day_id, user_id), so
--    the owner's report counts them as before. The day's money left =
--    the jobs − the day's expenses (worked out in the app from the server
--    rows; the target only motivates).
-- 2. The worker reads only his own day expenses (RLS); the owner / Baş
--    admin read every expense of their company, as before.
-- 3. Once saved, a job or an expense is the worker's no more: changing or
--    deleting one — also on an open day — is for the company's owner and
--    the Baş admin only (adbiz_update_entry / adbiz_delete_entry /
--    adbiz_expense_save with an id / adbiz_expense_delete). Adding jobs
--    into his open day stays the worker's (as in 0110). Every change is
--    audited (old / new / who / when), as in 0110.
--
-- Safe: forward-only, re-runnable. Two nullable columns on adbiz_expenses,
-- one read policy, functions created / re-created. Nothing is dropped,
-- deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.adbiz_expenses') is null or to_regprocedure('public.adbiz_can_manage(uuid)') is null then
    raise exception '0111: run 0110 first — nothing changed';
  end if;
end $$;

-- 1) A day expense belongs to a day and its worker ------------------------------------
alter table public.adbiz_expenses add column if not exists day_id uuid references public.adbiz_days(id) on delete cascade;
alter table public.adbiz_expenses add column if not exists user_id uuid references public.users(id) on delete set null;
create index if not exists idx_adbiz_expenses_day on public.adbiz_expenses(day_id);

-- 2) The worker reads his own day expenses (the owner / Baş admin: all, as before) -----
alter table public.adbiz_expenses enable row level security;
drop policy if exists adbiz_expenses_read_own on public.adbiz_expenses;
create policy adbiz_expenses_read_own on public.adbiz_expenses for select to authenticated
  using (user_id = auth.uid() and company_id = public.adbiz_my_company());

-- 3) The worker adds a day expense to his own open day ------------------------------------
create or replace function public.adbiz_add_day_expense(p_day uuid, p_title text, p_amount numeric, p_client_key uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_title is null or char_length(btrim(p_title)) = 0 or char_length(btrim(p_title)) > 120
     or p_amount is null or p_amount <= 0 or p_amount > 1000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  -- A double tap: the same key gives back the same expense.
  if p_client_key is not null then
    select id into v_id from adbiz_expenses where client_key = p_client_key;
    if v_id is not null then return v_id; end if;
  end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not (public.adbiz_can_manage(d.company_id)
          or (d.user_id = auth.uid() and d.status = 'open' and public.adbiz_my_company() = d.company_id)) then
    raise exception using message = case when d.user_id = auth.uid() and d.status = 'closed' then 'day_closed' else 'not_allowed' end,
      errcode = '42501';
  end if;
  insert into adbiz_expenses (company_id, spent_on, title, amount, client_key, created_by, day_id, user_id)
  values (d.company_id, d.work_date, btrim(p_title), round(p_amount, 2), p_client_key, auth.uid(), d.id, d.user_id)
  returning id into v_id;
  perform public._adbiz_log(d.company_id, 'expense.add', 'expense', v_id::text, null,
    jsonb_build_object('day_id', d.id, 'user_id', d.user_id, 'title', btrim(p_title), 'amount', round(p_amount, 2)));
  return v_id;
end $$;
revoke all on function public.adbiz_add_day_expense(uuid, text, numeric, uuid) from public, anon;
grant execute on function public.adbiz_add_day_expense(uuid, text, numeric, uuid) to authenticated;

-- 4) Saved jobs: changed / deleted only by the owner or the Baş admin -----------------------
create or replace function public.adbiz_update_entry(p_entry uuid, p_title text, p_amount numeric)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare e adbiz_entries; d adbiz_days;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_title is null or char_length(btrim(p_title)) = 0 or char_length(btrim(p_title)) > 120
     or p_amount is null or p_amount <= 0 or p_amount > 1000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  select * into e from adbiz_entries where id = p_entry for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into d from adbiz_days where id = e.day_id for update;
  if not public.adbiz_can_manage(d.company_id) then
    raise exception using message = case when d.user_id = auth.uid() and d.status = 'closed' then 'day_closed' else 'not_allowed' end,
      errcode = '42501';
  end if;
  update adbiz_entries set title = btrim(p_title), amount = round(p_amount, 2), updated_at = now() where id = p_entry;
  perform public._adbiz_log(e.company_id, 'entry.update', 'entry', p_entry::text,
    jsonb_build_object('title', e.title, 'amount', e.amount),
    jsonb_build_object('title', btrim(p_title), 'amount', round(p_amount, 2)));
end $$;

create or replace function public.adbiz_delete_entry(p_entry uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare e adbiz_entries; d adbiz_days;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into e from adbiz_entries where id = p_entry for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into d from adbiz_days where id = e.day_id for update;
  if not public.adbiz_can_manage(d.company_id) then
    raise exception using message = case when d.user_id = auth.uid() and d.status = 'closed' then 'day_closed' else 'not_allowed' end,
      errcode = '42501';
  end if;
  delete from adbiz_entries where id = p_entry;
  perform public._adbiz_log(e.company_id, 'entry.delete', 'entry', p_entry::text,
    jsonb_build_object('day_id', e.day_id, 'title', e.title, 'amount', e.amount), null);
end $$;

-- 5) A day expense moves with its day in the report (unchanged sums) -------------------------
-- adbiz_expense_save / adbiz_expense_delete (0110) already require the
-- owner or the Baş admin for a change / delete — the worker's own day
-- expenses included. Nothing else to change.

-- 6) Live: the worker's day expenses on every device --------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'adbiz_expenses') then
    alter publication supabase_realtime add table public.adbiz_expenses;
  end if;
end $$;

notify pgrst, 'reload schema';
commit;

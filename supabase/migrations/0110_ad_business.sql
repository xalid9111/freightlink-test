-- =====================================================================
-- 0110 — UTEP Reklam: ad business management (owner, 10.11.2026).
--
-- Run AFTER 0104 (is_chief_admin) — any time after 0109.
--
-- A separate sub-module, many companies from the start (UTEP Reklam is the
-- first one): every advertising company has an owner (Sahibkar) and
-- workers (İşçi), its own daily target, its workers' work days and jobs,
-- its expenses and its reports. The existing ads / banner / Premium tables
-- are NOT touched.
--
-- 1. Only the Baş admin (is_chief_admin) turns the module on for a user:
--    he finds an existing account, puts it into a company as Sahibkar or
--    İşçi (at once — no invitation, no extra approval), switches it off /
--    on again, creates companies, sets the company's daily target and, if
--    needed, a worker's own target. The user's FreightLink role and other
--    features are never changed (users.role is not touched).
-- 2. A company's data is separate: RLS lets a member read only his own
--    company (a worker only his own days and jobs, an owner his company's
--    days, jobs, expenses, history); the Baş admin reads everything. No
--    table takes a direct write: every change goes through the functions
--    below, which check the caller's company, role and rights again.
-- 3. The work notebook: the worker opens today (Baku date) — the day keeps
--    the target that counts at that moment (a later target change never
--    rewrites an older day); adds jobs (name + amount), sees the total;
--    closes the day (also below the target — the target only motivates, it
--    never caps the earnings). A closed day is the worker's no more: only
--    his company's owner and the Baş admin change its jobs, re-open or
--    close it. A double tap never adds a job twice (client_key).
-- 4. Every change of money (job added by someone else, changed, deleted;
--    day re-opened / closed by the owner or the admin; expense; target;
--    membership) is written to adbiz_audit with the old and the new value,
--    the time and the account that did it.
--
-- Safe: forward-only, re-runnable. New tables only (+ the first company,
-- "UTEP Reklam", once). Nothing is dropped, deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.is_chief_admin()') is null then
    raise exception '0110: run 0104 first — nothing changed';
  end if;
end $$;

-- 1) Tables ---------------------------------------------------------------------------
create table if not exists public.adbiz_companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 2 and 80),
  daily_target numeric(12,2) not null default 0 check (daily_target >= 0 and daily_target <= 1000000),
  owner_manages_staff boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One company per account (a person works for one advertising company).
create table if not exists public.adbiz_members (
  user_id uuid primary key references public.users(id) on delete cascade,
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  role text not null check (role in ('owner', 'worker')),
  is_active boolean not null default true,
  personal_target numeric(12,2) check (personal_target is null or (personal_target >= 0 and personal_target <= 1000000)),
  added_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_adbiz_members_company on public.adbiz_members(company_id);

create table if not exists public.adbiz_days (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  work_date date not null,
  status text not null default 'open' check (status in ('open', 'closed')),
  target numeric(12,2) not null default 0,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by uuid references public.users(id) on delete set null,
  unique (user_id, work_date)
);
create index if not exists idx_adbiz_days_company_date on public.adbiz_days(company_id, work_date desc);

create table if not exists public.adbiz_entries (
  id uuid primary key default gen_random_uuid(),
  day_id uuid not null references public.adbiz_days(id) on delete cascade,
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  amount numeric(12,2) not null check (amount > 0 and amount <= 1000000),
  client_key uuid unique,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_adbiz_entries_day on public.adbiz_entries(day_id, created_at);
create index if not exists idx_adbiz_entries_company on public.adbiz_entries(company_id, created_at);

create table if not exists public.adbiz_expenses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  spent_on date not null,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  amount numeric(12,2) not null check (amount > 0 and amount <= 10000000),
  client_key uuid unique,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_adbiz_expenses_company on public.adbiz_expenses(company_id, spent_on desc);

create table if not exists public.adbiz_target_history (
  id bigserial primary key,
  company_id uuid not null references public.adbiz_companies(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  old_target numeric(12,2),
  new_target numeric(12,2),
  changed_by uuid references public.users(id) on delete set null,
  changed_at timestamptz not null default now()
);
create index if not exists idx_adbiz_target_history_company on public.adbiz_target_history(company_id, changed_at desc);

create table if not exists public.adbiz_audit (
  id bigserial primary key,
  company_id uuid references public.adbiz_companies(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  action text not null,
  entity text not null,
  entity_id text,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_adbiz_audit_company on public.adbiz_audit(company_id, created_at desc);

-- The first company, once (the target is set by the Baş admin later).
insert into public.adbiz_companies (id, name, daily_target)
values ('ad0b1200-0000-4000-8000-000000000001', 'UTEP Reklam', 0)
on conflict (id) do nothing;

-- 2) Who is who ------------------------------------------------------------------------
-- My active membership in an active company (null = none).
create or replace function public.adbiz_my_company()
returns uuid language sql stable security definer set search_path = public, pg_temp as $$
  select m.company_id from adbiz_members m join adbiz_companies c on c.id = m.company_id
  where m.user_id = auth.uid() and m.is_active and c.is_active;
$$;
create or replace function public.adbiz_my_role()
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select m.role from adbiz_members m join adbiz_companies c on c.id = m.company_id
  where m.user_id = auth.uid() and m.is_active and c.is_active;
$$;
-- The caller may run this company's books: the Baş admin, or its active owner.
create or replace function public.adbiz_can_manage(p_company uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(public.is_chief_admin(), false)
      or (public.adbiz_my_role() = 'owner' and public.adbiz_my_company() = p_company);
$$;
revoke all on function public.adbiz_my_company() from public, anon;
revoke all on function public.adbiz_my_role() from public, anon;
revoke all on function public.adbiz_can_manage(uuid) from public, anon;
grant execute on function public.adbiz_my_company() to authenticated;
grant execute on function public.adbiz_my_role() to authenticated;
grant execute on function public.adbiz_can_manage(uuid) to authenticated;

create or replace function public._adbiz_log(p_company uuid, p_action text, p_entity text, p_entity_id text, p_old jsonb, p_new jsonb)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into adbiz_audit (company_id, actor_id, action, entity, entity_id, old_value, new_value)
  values (p_company, auth.uid(), p_action, p_entity, p_entity_id, p_old, p_new);
$$;
revoke all on function public._adbiz_log(uuid, text, text, text, jsonb, jsonb) from public, anon, authenticated;

create or replace function public._adbiz_today()
returns date language sql stable set search_path = public, pg_temp as $$
  select (now() at time zone 'Asia/Baku')::date;
$$;

-- 3) Row security: read only your own company; no direct writes ------------------------
alter table public.adbiz_companies enable row level security;
alter table public.adbiz_members enable row level security;
alter table public.adbiz_days enable row level security;
alter table public.adbiz_entries enable row level security;
alter table public.adbiz_expenses enable row level security;
alter table public.adbiz_target_history enable row level security;
alter table public.adbiz_audit enable row level security;
do $$
declare t text;
begin
  foreach t in array array['adbiz_companies','adbiz_members','adbiz_days','adbiz_entries','adbiz_expenses','adbiz_target_history','adbiz_audit'] loop
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

drop policy if exists adbiz_companies_read on public.adbiz_companies;
create policy adbiz_companies_read on public.adbiz_companies for select to authenticated
  using (public.is_chief_admin() or id = public.adbiz_my_company());

drop policy if exists adbiz_members_read on public.adbiz_members;
create policy adbiz_members_read on public.adbiz_members for select to authenticated
  using (public.is_chief_admin() or user_id = auth.uid()
         or (public.adbiz_my_role() = 'owner' and company_id = public.adbiz_my_company()));

drop policy if exists adbiz_days_read on public.adbiz_days;
create policy adbiz_days_read on public.adbiz_days for select to authenticated
  using (public.is_chief_admin()
         or (user_id = auth.uid() and company_id = public.adbiz_my_company())
         or (public.adbiz_my_role() = 'owner' and company_id = public.adbiz_my_company()));

drop policy if exists adbiz_entries_read on public.adbiz_entries;
create policy adbiz_entries_read on public.adbiz_entries for select to authenticated
  using (public.is_chief_admin()
         or (user_id = auth.uid() and company_id = public.adbiz_my_company())
         or (public.adbiz_my_role() = 'owner' and company_id = public.adbiz_my_company()));

drop policy if exists adbiz_expenses_read on public.adbiz_expenses;
create policy adbiz_expenses_read on public.adbiz_expenses for select to authenticated
  using (public.adbiz_can_manage(company_id));

drop policy if exists adbiz_target_history_read on public.adbiz_target_history;
create policy adbiz_target_history_read on public.adbiz_target_history for select to authenticated
  using (public.adbiz_can_manage(company_id));

drop policy if exists adbiz_audit_read on public.adbiz_audit;
create policy adbiz_audit_read on public.adbiz_audit for select to authenticated
  using (public.adbiz_can_manage(company_id));

-- 4) Me: what Profil shows ---------------------------------------------------------------
-- null = no "Reklam" entry (the module is off for this account).
create or replace function public.adbiz_me()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when auth.uid() is null then null
    else (
      select jsonb_build_object(
        'chief', coalesce(public.is_chief_admin(), false),
        'company_id', m.company_id,
        'company_name', c.name,
        'role', m.role,
        'manages_staff', m.role = 'owner' and c.owner_manages_staff,
        'daily_target', coalesce(m.personal_target, c.daily_target))
      from (select 1) x
      left join adbiz_members m on m.user_id = auth.uid() and m.is_active
      left join adbiz_companies c on c.id = m.company_id and c.is_active
      where coalesce(public.is_chief_admin(), false) or c.id is not null)
  end;
$$;
revoke all on function public.adbiz_me() from public, anon;
grant execute on function public.adbiz_me() to authenticated;

-- 5) Baş admin: companies, members, targets ------------------------------------------------
create or replace function public._adbiz_require_chief()
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not coalesce(public.is_chief_admin(), false) then raise exception 'chief_admin_only' using errcode = '42501'; end if;
end $$;
revoke all on function public._adbiz_require_chief() from public, anon, authenticated;

create or replace function public.adbiz_admin_company_save(
  p_id uuid, p_name text, p_daily_target numeric, p_owner_manages_staff boolean default false)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_companies; v_id uuid;
begin
  perform public._adbiz_require_chief();
  if p_name is null or char_length(btrim(p_name)) < 2 or p_daily_target is null or p_daily_target < 0 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if p_id is null then
    insert into adbiz_companies (name, daily_target, owner_manages_staff, created_by)
    values (btrim(p_name), round(p_daily_target, 2), coalesce(p_owner_manages_staff, false), auth.uid())
    returning id into v_id;
    insert into adbiz_target_history (company_id, old_target, new_target, changed_by)
    values (v_id, null, round(p_daily_target, 2), auth.uid());
    perform public._adbiz_log(v_id, 'company.create', 'company', v_id::text, null,
      jsonb_build_object('name', btrim(p_name), 'daily_target', round(p_daily_target, 2)));
    return v_id;
  end if;
  select * into v_old from adbiz_companies where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update adbiz_companies set name = btrim(p_name), daily_target = round(p_daily_target, 2),
    owner_manages_staff = coalesce(p_owner_manages_staff, false), updated_at = now() where id = p_id;
  -- A new target counts for days opened from now on; open / closed days keep theirs.
  if v_old.daily_target is distinct from round(p_daily_target, 2) then
    insert into adbiz_target_history (company_id, old_target, new_target, changed_by)
    values (p_id, v_old.daily_target, round(p_daily_target, 2), auth.uid());
  end if;
  perform public._adbiz_log(p_id, 'company.update', 'company', p_id::text,
    jsonb_build_object('name', v_old.name, 'daily_target', v_old.daily_target, 'owner_manages_staff', v_old.owner_manages_staff),
    jsonb_build_object('name', btrim(p_name), 'daily_target', round(p_daily_target, 2), 'owner_manages_staff', coalesce(p_owner_manages_staff, false)));
  return p_id;
end $$;

create or replace function public.adbiz_admin_company_set_active(p_id uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old boolean;
begin
  perform public._adbiz_require_chief();
  select is_active into v_old from adbiz_companies where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update adbiz_companies set is_active = coalesce(p_on, false), updated_at = now() where id = p_id;
  perform public._adbiz_log(p_id, 'company.active', 'company', p_id::text,
    jsonb_build_object('is_active', v_old), jsonb_build_object('is_active', coalesce(p_on, false)));
end $$;

-- Existing accounts only; name / e-mail / phone. Shows where each one already is.
create or replace function public.adbiz_admin_search_users(p_q text)
returns table (id uuid, full_name text, email text, phone text, company_id uuid, company_name text, role text, is_active boolean)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare q text := '%' || lower(btrim(coalesce(p_q, ''))) || '%';
begin
  perform public._adbiz_require_chief();
  if char_length(btrim(coalesce(p_q, ''))) < 2 then return; end if;
  return query
    select u.id, u.full_name, u.email, u.phone, m.company_id, c.name, m.role, m.is_active
    from users u
    left join adbiz_members m on m.user_id = u.id
    left join adbiz_companies c on c.id = m.company_id
    where lower(u.full_name) like q or lower(u.email) like q or coalesce(u.phone, '') like q
    order by u.full_name limit 30;
end $$;

-- Put an account into a company as owner / worker — at once (the Baş admin's
-- decision is the approval). Moving to another company keeps the old days.
create or replace function public.adbiz_admin_member_set(p_user uuid, p_company uuid, p_role text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_members;
begin
  perform public._adbiz_require_chief();
  if p_role not in ('owner', 'worker') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not exists (select 1 from users where id = p_user) then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not exists (select 1 from adbiz_companies where id = p_company) then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into v_old from adbiz_members where user_id = p_user for update;
  insert into adbiz_members (user_id, company_id, role, is_active, added_by)
  values (p_user, p_company, p_role, true, auth.uid())
  on conflict (user_id) do update set company_id = excluded.company_id, role = excluded.role,
    is_active = true, updated_at = now();
  perform public._adbiz_log(p_company, case when v_old.user_id is null then 'member.add' else 'member.change' end,
    'member', p_user::text,
    case when v_old.user_id is null then null
      else jsonb_build_object('company_id', v_old.company_id, 'role', v_old.role, 'is_active', v_old.is_active) end,
    jsonb_build_object('company_id', p_company, 'role', p_role, 'is_active', true));
end $$;

create or replace function public.adbiz_member_set_active(p_user uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_members; v_owner_ok boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_old from adbiz_members where user_id = p_user for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  -- The Baş admin always; an owner only for workers of his own company and
  -- only when the Baş admin allowed it (owner_manages_staff).
  v_owner_ok := v_old.role = 'worker' and p_user <> auth.uid()
    and public.adbiz_my_role() = 'owner' and public.adbiz_my_company() = v_old.company_id
    and exists (select 1 from adbiz_companies where id = v_old.company_id and owner_manages_staff);
  if not (coalesce(public.is_chief_admin(), false) or v_owner_ok) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update adbiz_members set is_active = coalesce(p_on, false), updated_at = now() where user_id = p_user;
  perform public._adbiz_log(v_old.company_id, 'member.active', 'member', p_user::text,
    jsonb_build_object('is_active', v_old.is_active), jsonb_build_object('is_active', coalesce(p_on, false)));
end $$;

-- An owner the Baş admin allowed to: add an existing account as a worker of
-- his own company (never a member of another company, never an owner).
create or replace function public.adbiz_owner_add_worker(p_email text)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_company uuid := public.adbiz_my_company(); v_user uuid; v_old adbiz_members;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.adbiz_my_role() is distinct from 'owner'
     or not exists (select 1 from adbiz_companies where id = v_company and owner_manages_staff) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  select id into v_user from users where lower(email) = lower(btrim(coalesce(p_email, '')));
  if v_user is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into v_old from adbiz_members where user_id = v_user for update;
  if found and (v_old.company_id <> v_company or v_old.role <> 'worker') then
    raise exception 'other_company' using errcode = '42501';
  end if;
  insert into adbiz_members (user_id, company_id, role, is_active, added_by)
  values (v_user, v_company, 'worker', true, auth.uid())
  on conflict (user_id) do update set is_active = true, updated_at = now();
  perform public._adbiz_log(v_company, 'member.add', 'member', v_user::text, null,
    jsonb_build_object('company_id', v_company, 'role', 'worker', 'by', 'owner'));
  return v_user;
end $$;

create or replace function public.adbiz_admin_member_target(p_user uuid, p_target numeric)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_members;
begin
  perform public._adbiz_require_chief();
  if p_target is not null and (p_target < 0 or p_target > 1000000) then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select * into v_old from adbiz_members where user_id = p_user for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update adbiz_members set personal_target = round(p_target, 2), updated_at = now() where user_id = p_user;
  if v_old.personal_target is distinct from round(p_target, 2) then
    insert into adbiz_target_history (company_id, user_id, old_target, new_target, changed_by)
    values (v_old.company_id, p_user, v_old.personal_target, round(p_target, 2), auth.uid());
  end if;
  perform public._adbiz_log(v_old.company_id, 'member.target', 'member', p_user::text,
    jsonb_build_object('personal_target', v_old.personal_target), jsonb_build_object('personal_target', round(p_target, 2)));
end $$;

-- 6) The work notebook ----------------------------------------------------------------------
-- Opens today's day for me (or returns it when it is already there).
create or replace function public.adbiz_open_day()
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_company uuid := public.adbiz_my_company(); v_day uuid; v_target numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if v_company is null then raise exception 'not_member' using errcode = '42501'; end if;
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

-- The owner / Baş admin opens a day for a worker (a forgotten day, a fix).
create or replace function public.adbiz_open_day_for(p_user uuid, p_date date)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare m adbiz_members; v_target numeric; v_day uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into m from adbiz_members where user_id = p_user;
  if not found or p_date is null or p_date > public._adbiz_today() then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(m.company_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select id into v_day from adbiz_days where user_id = p_user and work_date = p_date;
  if v_day is not null then return v_day; end if;
  select coalesce(m.personal_target, c.daily_target) into v_target from adbiz_companies c where c.id = m.company_id;
  insert into adbiz_days (company_id, user_id, work_date, target)
  values (m.company_id, p_user, p_date, coalesce(v_target, 0)) returning id into v_day;
  perform public._adbiz_log(m.company_id, 'day.open_for', 'day', v_day::text, null,
    jsonb_build_object('user_id', p_user, 'work_date', p_date));
  return v_day;
end $$;

-- Who may change this day's jobs: its worker while it is open; its company's
-- owner and the Baş admin at any time.
create or replace function public._adbiz_day_writable(p_day adbiz_days)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public.adbiz_can_manage(p_day.company_id)
      or (p_day.user_id = auth.uid() and p_day.status = 'open' and public.adbiz_my_company() = p_day.company_id);
$$;
revoke all on function public._adbiz_day_writable(adbiz_days) from public, anon, authenticated;

create or replace function public.adbiz_add_entry(p_day uuid, p_title text, p_amount numeric, p_client_key uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_title is null or char_length(btrim(p_title)) = 0 or char_length(btrim(p_title)) > 120
     or p_amount is null or p_amount <= 0 or p_amount > 1000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  -- A double tap: the same key gives back the same job.
  if p_client_key is not null then
    select id into v_id from adbiz_entries where client_key = p_client_key;
    if v_id is not null then return v_id; end if;
  end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public._adbiz_day_writable(d) then
    raise exception using message = case when d.user_id = auth.uid() and d.status = 'closed' then 'day_closed' else 'not_allowed' end, errcode = '42501';
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
  if not public._adbiz_day_writable(d) then
    raise exception using message = case when d.user_id = auth.uid() and d.status = 'closed' then 'day_closed' else 'not_allowed' end, errcode = '42501';
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
  if not public._adbiz_day_writable(d) then
    raise exception using message = case when d.user_id = auth.uid() and d.status = 'closed' then 'day_closed' else 'not_allowed' end, errcode = '42501';
  end if;
  delete from adbiz_entries where id = p_entry;
  perform public._adbiz_log(e.company_id, 'entry.delete', 'entry', p_entry::text,
    jsonb_build_object('day_id', e.day_id, 'title', e.title, 'amount', e.amount), null);
end $$;

-- Closing works below the target too (the target never blocks).
create or replace function public.adbiz_close_day(p_day uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days; v_total numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public._adbiz_day_writable(d) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if d.status = 'closed' then return; end if;
  select coalesce(sum(amount), 0) into v_total from adbiz_entries where day_id = p_day;
  update adbiz_days set status = 'closed', closed_at = now(), closed_by = auth.uid() where id = p_day;
  perform public._adbiz_log(d.company_id, 'day.close', 'day', p_day::text,
    jsonb_build_object('status', 'open'), jsonb_build_object('status', 'closed', 'total', v_total, 'target', d.target));
end $$;

-- Only the company's owner and the Baş admin re-open a closed day.
create or replace function public.adbiz_reopen_day(p_day uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare d adbiz_days;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into d from adbiz_days where id = p_day for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.adbiz_can_manage(d.company_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if d.status = 'open' then return; end if;
  update adbiz_days set status = 'open', closed_at = null, closed_by = null where id = p_day;
  perform public._adbiz_log(d.company_id, 'day.reopen', 'day', p_day::text,
    jsonb_build_object('status', 'closed', 'closed_at', d.closed_at), jsonb_build_object('status', 'open'));
end $$;

-- 7) Expenses (owner / Baş admin) ---------------------------------------------------------
create or replace function public.adbiz_expense_save(
  p_id uuid, p_company uuid, p_spent_on date, p_title text, p_amount numeric, p_client_key uuid default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_expenses; v_id uuid; v_company uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_spent_on is null or p_title is null or char_length(btrim(p_title)) = 0 or char_length(btrim(p_title)) > 120
     or p_amount is null or p_amount <= 0 or p_amount > 10000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if p_id is null then
    if p_client_key is not null then
      select id into v_id from adbiz_expenses where client_key = p_client_key;
      if v_id is not null then return v_id; end if;
    end if;
    v_company := coalesce(p_company, public.adbiz_my_company());
    if v_company is null or not public.adbiz_can_manage(v_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
    insert into adbiz_expenses (company_id, spent_on, title, amount, client_key, created_by)
    values (v_company, p_spent_on, btrim(p_title), round(p_amount, 2), p_client_key, auth.uid())
    returning id into v_id;
    perform public._adbiz_log(v_company, 'expense.add', 'expense', v_id::text, null,
      jsonb_build_object('spent_on', p_spent_on, 'title', btrim(p_title), 'amount', round(p_amount, 2)));
    return v_id;
  end if;
  select * into v_old from adbiz_expenses where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.adbiz_can_manage(v_old.company_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  update adbiz_expenses set spent_on = p_spent_on, title = btrim(p_title), amount = round(p_amount, 2), updated_at = now() where id = p_id;
  perform public._adbiz_log(v_old.company_id, 'expense.update', 'expense', p_id::text,
    jsonb_build_object('spent_on', v_old.spent_on, 'title', v_old.title, 'amount', v_old.amount),
    jsonb_build_object('spent_on', p_spent_on, 'title', btrim(p_title), 'amount', round(p_amount, 2)));
  return p_id;
end $$;

create or replace function public.adbiz_expense_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_expenses;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_old from adbiz_expenses where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not public.adbiz_can_manage(v_old.company_id) then raise exception 'not_allowed' using errcode = '42501'; end if;
  delete from adbiz_expenses where id = p_id;
  perform public._adbiz_log(v_old.company_id, 'expense.delete', 'expense', p_id::text,
    jsonb_build_object('spent_on', v_old.spent_on, 'title', v_old.title, 'amount', v_old.amount), null);
end $$;

-- 8) Report: income, expenses, net, per worker, per day (owner / Baş admin) ----------------
create or replace function public.adbiz_report(p_company uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_income numeric; v_exp numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_company is null or p_from is null or p_to is null or p_to < p_from then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select coalesce(sum(e.amount), 0) into v_income from adbiz_entries e join adbiz_days d on d.id = e.day_id
  where d.company_id = p_company and d.work_date between p_from and p_to;
  select coalesce(sum(amount), 0) into v_exp from adbiz_expenses where company_id = p_company and spent_on between p_from and p_to;
  return jsonb_build_object(
    'income', v_income, 'expenses', v_exp, 'net', v_income - v_exp,
    'days_open', (select count(*) from adbiz_days where company_id = p_company and work_date between p_from and p_to and status = 'open'),
    'days_closed', (select count(*) from adbiz_days where company_id = p_company and work_date between p_from and p_to and status = 'closed'),
    'workers', coalesce((
      select jsonb_agg(w order by w->>'name') from (
        select jsonb_build_object('user_id', u.id, 'name', u.full_name, 'role', m.role, 'is_active', m.is_active,
          'personal_target', m.personal_target,
          'total', coalesce((select sum(e.amount) from adbiz_entries e join adbiz_days d on d.id = e.day_id
                             where d.user_id = u.id and d.company_id = p_company and d.work_date between p_from and p_to), 0),
          'days', (select count(*) from adbiz_days d where d.user_id = u.id and d.company_id = p_company and d.work_date between p_from and p_to)) w
        from adbiz_members m join users u on u.id = m.user_id where m.company_id = p_company) s), '[]'::jsonb),
    'by_day', coalesce((
      select jsonb_agg(jsonb_build_object('date', x.work_date, 'income', x.income) order by x.work_date desc) from (
        select d.work_date, coalesce(sum(e.amount), 0) income from adbiz_days d left join adbiz_entries e on e.day_id = d.id
        where d.company_id = p_company and d.work_date between p_from and p_to group by d.work_date) x), '[]'::jsonb));
end $$;

-- 9) Rights on the functions -----------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'adbiz_admin_company_save(uuid, text, numeric, boolean)', 'adbiz_admin_company_set_active(uuid, boolean)',
    'adbiz_admin_search_users(text)', 'adbiz_admin_member_set(uuid, uuid, text)', 'adbiz_member_set_active(uuid, boolean)',
    'adbiz_owner_add_worker(text)', 'adbiz_admin_member_target(uuid, numeric)', 'adbiz_open_day()', 'adbiz_open_day_for(uuid, date)',
    'adbiz_add_entry(uuid, text, numeric, uuid)', 'adbiz_update_entry(uuid, text, numeric)', 'adbiz_delete_entry(uuid)',
    'adbiz_close_day(uuid)', 'adbiz_reopen_day(uuid)', 'adbiz_expense_save(uuid, uuid, date, text, numeric, uuid)',
    'adbiz_expense_delete(uuid)', 'adbiz_report(uuid, date, date)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public._adbiz_today() from public, anon;
grant execute on function public._adbiz_today() to authenticated;

-- 10) Live on every device: the notebook follows changes made elsewhere -----------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['adbiz_days', 'adbiz_entries'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

notify pgrst, 'reload schema';
commit;

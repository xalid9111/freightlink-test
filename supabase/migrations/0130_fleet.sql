-- =====================================================================
-- 0130 — "Maşınlarım" (owner's pictures and answers, 20.11.2026): a
-- carrier's own trucks, their jobs and expenses, on the Xəritə tab.
--   * A truck: its name (e.g. "Volvo FH 2022"), plate and the driver's name;
--     the driver may be linked to his own account by a one-time code (7
--     days) — then he sees the truck and its jobs (WITHOUT prices) and
--     writes expenses.
--   * A job: when, from → to, the agreed price and its currency (AZN · USD ·
--     EUR · RUB · TRY); planned → active → done (or cancelled).
--   * An expense: a name, an amount, a currency. The owner's own expense
--     counts at once; a driver's expense waits ("Təsdiq gözləyir") — the
--     owner gets a notice (the bell), opens the truck and approves or
--     rejects it. Only approved expenses are taken off the agreed prices
--     (profit = jobs' prices − approved expenses, per truck, per currency).
--   * Nothing is ever really deleted: "Sil" sets deleted_at (history kept).
-- Data kept apart: a user reads only his own trucks / jobs / expenses; a
-- linked driver reads his truck and his own expenses, and the jobs only
-- through fleet_driver_jobs() (no prices). Every write goes through the
-- functions below (checked on the server); no direct writes.
-- Safe: forward-only, re-runnable; four new tables, new functions; no
-- existing table, row or function is changed or deleted.
-- =====================================================================

create table if not exists public.fleet_trucks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  plate text check (plate is null or char_length(plate) <= 20),
  driver_name text check (driver_name is null or char_length(driver_name) <= 60),
  driver_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists fleet_trucks_owner_idx on public.fleet_trucks (owner_id) where deleted_at is null;
create index if not exists fleet_trucks_driver_idx on public.fleet_trucks (driver_id) where deleted_at is null and driver_id is not null;

create table if not exists public.fleet_jobs (
  id uuid primary key default gen_random_uuid(),
  truck_id uuid not null references public.fleet_trucks(id) on delete cascade,
  owner_id uuid not null references public.users(id) on delete cascade,
  start_at timestamptz not null,
  from_place text check (from_place is null or char_length(from_place) <= 80),
  to_place text check (to_place is null or char_length(to_place) <= 80),
  price numeric(14,2) check (price is null or price >= 0),
  currency text not null default 'AZN' check (currency in ('AZN', 'USD', 'EUR', 'RUB', 'TRY')),
  note text check (note is null or char_length(note) <= 300),
  status text not null default 'planned' check (status in ('planned', 'active', 'done', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists fleet_jobs_truck_idx on public.fleet_jobs (truck_id, start_at) where deleted_at is null;
create index if not exists fleet_jobs_owner_idx on public.fleet_jobs (owner_id, start_at) where deleted_at is null;

create table if not exists public.fleet_expenses (
  id uuid primary key default gen_random_uuid(),
  truck_id uuid not null references public.fleet_trucks(id) on delete cascade,
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'AZN' check (currency in ('AZN', 'USD', 'EUR', 'RUB', 'TRY')),
  status text not null default 'approved' check (status in ('approved', 'pending', 'rejected')),
  created_by uuid not null references public.users(id) on delete cascade,
  decided_by uuid references public.users(id) on delete set null,
  decided_at timestamptz,
  client_key text check (client_key is null or char_length(client_key) <= 64),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists fleet_expenses_truck_idx on public.fleet_expenses (truck_id, created_at) where deleted_at is null;
create unique index if not exists fleet_expenses_client_key on public.fleet_expenses (created_by, client_key) where client_key is not null;

create table if not exists public.fleet_driver_invites (
  id uuid primary key default gen_random_uuid(),
  truck_id uuid not null references public.fleet_trucks(id) on delete cascade,
  code text not null unique,
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_at timestamptz,
  used_by uuid references public.users(id) on delete set null,
  cancelled_at timestamptz
);

-- Reading: own rows only (a linked driver: his truck and his own expenses).
alter table public.fleet_trucks enable row level security;
alter table public.fleet_jobs enable row level security;
alter table public.fleet_expenses enable row level security;
alter table public.fleet_driver_invites enable row level security;
revoke all on public.fleet_trucks, public.fleet_jobs, public.fleet_expenses, public.fleet_driver_invites from anon, authenticated;
grant select on public.fleet_trucks, public.fleet_jobs, public.fleet_expenses to authenticated;

drop policy if exists fleet_trucks_read on public.fleet_trucks;
create policy fleet_trucks_read on public.fleet_trucks for select to authenticated
  using (owner_id = auth.uid() or driver_id = auth.uid());
drop policy if exists fleet_jobs_read on public.fleet_jobs;
create policy fleet_jobs_read on public.fleet_jobs for select to authenticated
  using (owner_id = auth.uid());
drop policy if exists fleet_expenses_read on public.fleet_expenses;
create policy fleet_expenses_read on public.fleet_expenses for select to authenticated
  using (owner_id = auth.uid() or created_by = auth.uid());

-- Helpers.
create or replace function public._fleet_me()
returns uuid language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'blocked' using errcode = '42501'; end if;
  return auth.uid();
end $$;
revoke all on function public._fleet_me() from public, anon, authenticated;

create or replace function public._fleet_owned_truck(p_truck uuid)
returns fleet_trucks language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v fleet_trucks;
begin
  select * into v from fleet_trucks where id = p_truck and deleted_at is null;
  if v.id is null or v.owner_id <> public._fleet_me() then
    raise exception 'not_owner' using errcode = '42501';
  end if;
  return v;
end $$;
revoke all on function public._fleet_owned_truck(uuid) from public, anon, authenticated;

create or replace function public._fleet_currency(p text)
returns text language plpgsql immutable as $$
begin
  if p is null or upper(p) not in ('AZN', 'USD', 'EUR', 'RUB', 'TRY') then
    raise exception 'invalid_currency' using errcode = '22023';
  end if;
  return upper(p);
end $$;
revoke all on function public._fleet_currency(text) from public, anon, authenticated;

-- A truck: new (p_id null) or changed by its owner.
create or replace function public.fleet_truck_save(p_id uuid, p_name text, p_plate text default null, p_driver_name text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_id uuid;
begin
  if char_length(btrim(coalesce(p_name, ''))) < 1 or char_length(btrim(p_name)) > 60 then
    raise exception 'name_required' using errcode = '22023';
  end if;
  if p_id is null then
    if (select count(*) from fleet_trucks where owner_id = v_me and deleted_at is null) >= 100 then
      raise exception 'too_many' using errcode = '54000';
    end if;
    insert into fleet_trucks (owner_id, name, plate, driver_name)
    values (v_me, btrim(p_name), nullif(upper(btrim(coalesce(p_plate, ''))), ''), nullif(btrim(coalesce(p_driver_name, '')), ''))
    returning id into v_id;
  else
    perform public._fleet_owned_truck(p_id);
    update fleet_trucks
       set name = btrim(p_name), plate = nullif(upper(btrim(coalesce(p_plate, ''))), ''),
           driver_name = nullif(btrim(coalesce(p_driver_name, '')), ''), updated_at = now()
     where id = p_id
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- "Sil": the truck leaves the lists; its jobs and expenses stay stored.
create or replace function public.fleet_truck_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._fleet_owned_truck(p_id);
  update fleet_trucks set deleted_at = now(), updated_at = now() where id = p_id;
end $$;

-- A job of a truck (owner only). A new job that has already started is active.
create or replace function public.fleet_job_save(
  p_id uuid, p_truck uuid, p_start_at timestamptz, p_from text, p_to text,
  p_price numeric, p_currency text, p_note text default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_t fleet_trucks := public._fleet_owned_truck(p_truck);
  v_cur text := public._fleet_currency(p_currency);
  v_id uuid;
begin
  if p_start_at is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if p_price is not null and p_price < 0 then raise exception 'invalid_amount' using errcode = '22023'; end if;
  if p_id is null then
    insert into fleet_jobs (truck_id, owner_id, start_at, from_place, to_place, price, currency, note, status)
    values (v_t.id, v_t.owner_id, p_start_at, nullif(btrim(coalesce(p_from, '')), ''), nullif(btrim(coalesce(p_to, '')), ''),
            p_price, v_cur, nullif(btrim(coalesce(p_note, '')), ''),
            case when p_start_at <= now() then 'active' else 'planned' end)
    returning id into v_id;
  else
    update fleet_jobs
       set start_at = p_start_at, from_place = nullif(btrim(coalesce(p_from, '')), ''), to_place = nullif(btrim(coalesce(p_to, '')), ''),
           price = p_price, currency = v_cur, note = nullif(btrim(coalesce(p_note, '')), ''), updated_at = now()
     where id = p_id and truck_id = v_t.id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.fleet_job_set_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_truck uuid;
begin
  if p_status not in ('planned', 'active', 'done', 'cancelled') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select truck_id into v_truck from fleet_jobs where id = p_id and deleted_at is null;
  if v_truck is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public._fleet_owned_truck(v_truck);
  update fleet_jobs set status = p_status, updated_at = now() where id = p_id;
end $$;

create or replace function public.fleet_job_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_truck uuid;
begin
  select truck_id into v_truck from fleet_jobs where id = p_id and deleted_at is null;
  if v_truck is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public._fleet_owned_truck(v_truck);
  update fleet_jobs set deleted_at = now(), updated_at = now() where id = p_id;
end $$;

-- An expense: the owner's counts at once; the linked driver's waits for the
-- owner (a notice in the bell). A double tap never adds twice (client_key).
create or replace function public.fleet_expense_add(p_truck uuid, p_name text, p_amount numeric, p_currency text, p_client_key text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_t fleet_trucks;
  v_cur text := public._fleet_currency(p_currency);
  v_e fleet_expenses;
  v_driver boolean;
begin
  select * into v_t from fleet_trucks where id = p_truck and deleted_at is null;
  if v_t.id is null or (v_t.owner_id <> v_me and v_t.driver_id is distinct from v_me) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_name, ''))) < 1 or char_length(btrim(p_name)) > 60 then
    raise exception 'name_required' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;
  if p_client_key is not null then
    select * into v_e from fleet_expenses where created_by = v_me and client_key = p_client_key;
    if v_e.id is not null then return jsonb_build_object('id', v_e.id, 'status', v_e.status); end if;
  end if;
  v_driver := v_t.owner_id <> v_me;
  insert into fleet_expenses (truck_id, owner_id, name, amount, currency, status, created_by, client_key)
  values (v_t.id, v_t.owner_id, btrim(p_name), round(p_amount, 2), v_cur,
          case when v_driver then 'pending' else 'approved' end, v_me, p_client_key)
  returning * into v_e;
  if v_driver then
    begin
      insert into notifications (user_id, type, title, body, data)
      values (v_t.owner_id, 'fleet_expense',
              'Rasxod təsdiq gözləyir: ' || v_e.name,
              v_t.name || ' · ' || rtrim(rtrim(to_char(v_e.amount, 'FM999999999990.00'), '0'), '.') || ' ' || v_e.currency,
              jsonb_build_object('truck_id', v_t.id, 'expense_id', v_e.id, 'amount', v_e.amount, 'currency', v_e.currency,
                                 'name', v_e.name, 'truck', v_t.name, 'dedupe', 'fle:' || v_e.id))
      on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
    exception when others then
      raise notice 'notice (fleet expense) skipped: %', sqlerrm;
    end;
  end if;
  return jsonb_build_object('id', v_e.id, 'status', v_e.status);
end $$;

-- The owner changes an expense (name, amount, currency); it then counts.
create or replace function public.fleet_expense_update(p_id uuid, p_name text, p_amount numeric, p_currency text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_e fleet_expenses;
  v_cur text := public._fleet_currency(p_currency);
begin
  select * into v_e from fleet_expenses where id = p_id and deleted_at is null;
  if v_e.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public._fleet_owned_truck(v_e.truck_id);
  if char_length(btrim(coalesce(p_name, ''))) < 1 or char_length(btrim(p_name)) > 60 then
    raise exception 'name_required' using errcode = '22023';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then
    raise exception 'invalid_amount' using errcode = '22023';
  end if;
  update fleet_expenses
     set name = btrim(p_name), amount = round(p_amount, 2), currency = v_cur, updated_at = now(),
         status = case when status = 'pending' then 'approved' else status end,
         decided_by = case when status = 'pending' then auth.uid() else decided_by end,
         decided_at = case when status = 'pending' then now() else decided_at end
   where id = p_id;
end $$;

-- The owner approves / rejects a driver's waiting expense.
create or replace function public.fleet_expense_decide(p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_e fleet_expenses;
begin
  select * into v_e from fleet_expenses where id = p_id and deleted_at is null;
  if v_e.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public._fleet_owned_truck(v_e.truck_id);
  if v_e.status <> 'pending' then raise exception 'already_decided' using errcode = '55000'; end if;
  update fleet_expenses
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), updated_at = now()
   where id = p_id;
end $$;

-- "Sil": the owner any expense, the driver only his own still waiting one.
create or replace function public.fleet_expense_remove(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_e fleet_expenses;
begin
  select * into v_e from fleet_expenses where id = p_id and deleted_at is null;
  if v_e.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_e.owner_id <> v_me and not (v_e.created_by = v_me and v_e.status = 'pending') then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update fleet_expenses set deleted_at = now(), updated_at = now() where id = p_id;
end $$;

-- Linking the driver: the owner makes a one-time code (7 days) and gives it
-- to the driver; the driver enters it with his own account.
create or replace function public.fleet_invite_create(p_truck uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_t fleet_trucks := public._fleet_owned_truck(p_truck);
  v_code text;
  v_i fleet_driver_invites;
begin
  if (select count(*) from fleet_driver_invites where created_by = v_t.owner_id and created_at > now() - interval '1 day') >= 30 then
    raise exception 'too_many' using errcode = '54000';
  end if;
  update fleet_driver_invites set cancelled_at = now() where truck_id = v_t.id and used_at is null and cancelled_at is null;
  loop
    v_code := public._tir_park_new_code();
    exit when not exists (select 1 from fleet_driver_invites where code = v_code);
  end loop;
  insert into fleet_driver_invites (truck_id, code, created_by) values (v_t.id, v_code, v_t.owner_id) returning * into v_i;
  return jsonb_build_object('code', v_i.code, 'expires_at', v_i.expires_at);
end $$;

create or replace function public.fleet_driver_join(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := public._fleet_me();
  v_i fleet_driver_invites;
  v_t fleet_trucks;
begin
  select * into v_i from fleet_driver_invites
   where code = upper(btrim(coalesce(p_code, ''))) and used_at is null and cancelled_at is null and expires_at > now()
   for update;
  if v_i.id is null then raise exception 'invalid_code' using errcode = '22023'; end if;
  select * into v_t from fleet_trucks where id = v_i.truck_id and deleted_at is null;
  if v_t.id is null then raise exception 'invalid_code' using errcode = '22023'; end if;
  if v_t.owner_id = v_me then raise exception 'own_truck' using errcode = '22023'; end if;
  update fleet_driver_invites set used_at = now(), used_by = v_me where id = v_i.id;
  update fleet_trucks set driver_id = v_me, updated_at = now() where id = v_t.id;
  return jsonb_build_object('truck_id', v_t.id, 'name', v_t.name, 'plate', v_t.plate);
end $$;

create or replace function public.fleet_driver_unlink(p_truck uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._fleet_owned_truck(p_truck);
  update fleet_trucks set driver_id = null, updated_at = now() where id = p_truck;
  update fleet_driver_invites set cancelled_at = now() where truck_id = p_truck and used_at is null and cancelled_at is null;
end $$;

-- The linked driver's jobs: when, where, status — never the price.
create or replace function public.fleet_driver_jobs()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_me uuid := public._fleet_me();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', j.id, 'truck_id', j.truck_id, 'start_at', j.start_at,
                                        'from_place', j.from_place, 'to_place', j.to_place,
                                        'status', j.status, 'note', j.note)
                     order by j.start_at)
      from fleet_jobs j join fleet_trucks t on t.id = j.truck_id
     where t.driver_id = v_me and t.deleted_at is null and j.deleted_at is null
       and j.status <> 'cancelled' and j.start_at > now() - interval '60 days'), '[]'::jsonb);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'fleet_truck_save(uuid, text, text, text)', 'fleet_truck_remove(uuid)',
    'fleet_job_save(uuid, uuid, timestamptz, text, text, numeric, text, text)', 'fleet_job_set_status(uuid, text)', 'fleet_job_remove(uuid)',
    'fleet_expense_add(uuid, text, numeric, text, text)', 'fleet_expense_update(uuid, text, numeric, text)',
    'fleet_expense_decide(uuid, boolean)', 'fleet_expense_remove(uuid)',
    'fleet_invite_create(uuid)', 'fleet_driver_join(text)', 'fleet_driver_unlink(uuid)', 'fleet_driver_jobs()']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

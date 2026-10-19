-- =====================================================================
-- 0045 — Founder account is protected (owner, 19.10.2026)
--
-- The founder's account (e-mail xelilov.1881@gmail.com, bound by its
-- user id in public.founders) can be changed ONLY by the founder:
-- no other admin can change its role, give / take the blue tick (verified),
-- block, deactivate, rename or delete it — through any admin button or
-- the API. A trigger on public.users refuses every change to that row made
-- by another signed-in person ('founder_protected'). The founder (signed
-- in as himself) and the SQL editor / server can still change it.
--
-- Safe: forward-only, re-runnable. One new table, three functions, one
-- trigger; no existing row, policy or function is changed or deleted.
-- =====================================================================

create table if not exists public.founders (
  user_id uuid primary key references public.users (id) on delete cascade,
  email text not null,
  added_at timestamptz not null default now()
);
alter table public.founders enable row level security;
revoke all on public.founders from anon, authenticated;

-- Binds the founder's e-mail to his user id (exact e-mail only). Re-runnable.
create or replace function public.founder_sync()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  insert into founders (user_id, email)
  select u.id, lower(u.email)
    from auth.users u join public.users p on p.id = u.id
   where lower(u.email) = 'xelilov.1881@gmail.com'
  on conflict (user_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.founder_sync() from public, anon, authenticated;
select public.founder_sync();

create or replace function public.is_founder(p_uid uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from founders f where f.user_id = p_uid);
$$;
revoke all on function public.is_founder(uuid) from public, anon;
grant execute on function public.is_founder(uuid) to authenticated;

-- For the admin panel: which accounts are locked (shown with a lock).
create or replace function public.founder_ids()
returns setof uuid language sql stable security definer set search_path = public, pg_temp as $$
  select user_id from founders;
$$;
revoke all on function public.founder_ids() from public, anon;
grant execute on function public.founder_ids() to authenticated;

-- Nobody but the founder changes or deletes the founder's row. Runs for
-- the API and for every admin_* function (they act as the signed-in
-- admin, auth.uid() is that admin). The SQL editor / server (no signed-in
-- user) is trusted, like the other guards.
create or replace function public.founder_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is not null and v_actor is distinct from old.id and public.is_founder(old.id) then
    raise exception 'founder_protected' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
revoke all on function public.founder_guard() from public, anon, authenticated;
drop trigger if exists aa_founder_guard on public.users;
create trigger aa_founder_guard
  before update or delete on public.users
  for each row execute function public.founder_guard();

notify pgrst, 'reload schema';

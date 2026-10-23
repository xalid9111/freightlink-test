-- =====================================================================
-- 0059 — VIP loads on the Loads page (owner, 23.10.2026)
--
-- * VIP = cargo.is_featured (+ featured_until; NULL = no end), columns
--   from 0006. Only an admin turns it on / off here
--   (admin_set_cargo_vip, logged). Paid VIP can use the same columns.
-- * 0006 guarded only UPDATE: a new load could be posted with
--   is_featured = true. Now a load posted by a normal user is never VIP.
-- * cargo_feed_settings.vip_every_rows: a row of VIP loads comes after
--   every 2 / 3 / 4 rows of normal loads (default 3). Everybody reads it;
--   only an admin changes it (admin_set_cargo_vip_every, logged) — no
--   code change needed.
--
-- Safe: forward-only, re-runnable. One new table, functions and a
-- trigger. No existing row is changed or deleted.
-- =====================================================================

-- A new load of a normal user is never VIP (admins / payment service may).
create or replace function public.zz_cargo_featured_on_insert()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if (new.is_featured or new.featured_until is not null)
     and coalesce(auth.role(), '') <> 'service_role'
     and not public.is_admin() then
    new.is_featured := false;
    new.featured_until := null;
  end if;
  return new;
end $$;
drop trigger if exists zz_cargo_featured_on_insert on public.cargo;
create trigger zz_cargo_featured_on_insert before insert on public.cargo
  for each row execute function public.zz_cargo_featured_on_insert();

-- Admins only: VIP on (until a date, or with no end) / off.
create or replace function public.admin_set_cargo_vip(p_id uuid, p_on boolean, p_until timestamptz default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  select jsonb_build_object('is_featured', is_featured, 'featured_until', featured_until) into v_old
    from cargo where id = p_id;
  if v_old is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if p_on and p_until is not null and p_until <= now() then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  update cargo
     set is_featured = coalesce(p_on, false),
         featured_until = case when coalesce(p_on, false) then p_until else null end
   where id = p_id;
  perform public._admin_log(case when p_on then 'cargo.vip_on' else 'cargo.vip_off' end, 'cargo', p_id::text, v_old,
    jsonb_build_object('is_featured', coalesce(p_on, false), 'featured_until', case when p_on then p_until end));
end $$;

-- How often a VIP row comes (Loads page) -------------------------------
create table if not exists public.cargo_feed_settings (
  id integer primary key default 1 check (id = 1),
  vip_every_rows integer not null default 3 check (vip_every_rows in (2, 3, 4)),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
insert into public.cargo_feed_settings (id) values (1) on conflict (id) do nothing;

alter table public.cargo_feed_settings enable row level security;
revoke all on public.cargo_feed_settings from anon, authenticated;
grant select on public.cargo_feed_settings to anon, authenticated;
drop policy if exists "cargo_feed_settings_read" on public.cargo_feed_settings;
create policy "cargo_feed_settings_read" on public.cargo_feed_settings for select using (true);

create or replace function public.admin_set_cargo_vip_every(p_rows integer)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old integer;
begin
  perform public._require_admin();
  if p_rows is null or p_rows not in (2, 3, 4) then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select vip_every_rows into v_old from cargo_feed_settings where id = 1;
  insert into cargo_feed_settings (id, vip_every_rows, updated_at, updated_by)
  values (1, p_rows, now(), auth.uid())
  on conflict (id) do update set vip_every_rows = excluded.vip_every_rows, updated_at = now(), updated_by = auth.uid();
  perform public._admin_log('cargo.vip_every', 'cargo_feed_settings', '1',
    jsonb_build_object('vip_every_rows', v_old), jsonb_build_object('vip_every_rows', p_rows));
  return p_rows;
end $$;

revoke all on function public.admin_set_cargo_vip(uuid, boolean, timestamptz) from public, anon;
revoke all on function public.admin_set_cargo_vip_every(integer) from public, anon;
grant execute on function public.admin_set_cargo_vip(uuid, boolean, timestamptz) to authenticated;
grant execute on function public.admin_set_cargo_vip_every(integer) to authenticated;

notify pgrst, 'reload schema';

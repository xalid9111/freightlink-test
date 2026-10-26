-- =====================================================================
-- 0068 — Site open / closed (owner, 25.10.2026)
--
-- * Admin panel → Dashboard: "Sayt açıq / bağlı". While the site is
--   closed only administrators use the app; everybody else (signed in or
--   not) sees the owner's notice instead of the app.
-- * The notice is written by the admin when closing (shown as typed).
-- * One row (site_settings, id = 1). Nobody reads or writes the table
--   directly: site_status() tells the app the state (also before sign-in,
--   so the notice shows on the login page), and only an admin changes it
--   through admin_set_site_status (checked on the server, logged).
--
-- Safe: forward-only, re-runnable. One new table with one row, two
-- functions. No existing row is changed or deleted. The site starts OPEN.
-- =====================================================================

begin;

create table if not exists public.site_settings (
  id integer primary key default 1 check (id = 1),
  closed boolean not null default false,
  message text check (message is null or char_length(message) <= 1000),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
insert into public.site_settings (id) values (1) on conflict (id) do nothing;

alter table public.site_settings enable row level security;
revoke all on public.site_settings from anon, authenticated;

-- The state for the app (everyone, also before sign-in).
create or replace function public.site_status()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
           'closed', coalesce(s.closed, false),
           'message', s.message,
           'admin', public.is_admin())
    from (select 1) one
    left join public.site_settings s on s.id = 1;
$$;
revoke all on function public.site_status() from public;
grant execute on function public.site_status() to anon, authenticated;

-- Admins only: close (with the notice) or open the site; logged.
create or replace function public.admin_set_site_status(p_closed boolean, p_message text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old public.site_settings;
  v_msg text := nullif(btrim(coalesce(p_message, '')), '');
begin
  perform public._require_admin();
  if p_closed is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if v_msg is not null and char_length(v_msg) > 1000 then raise exception 'message_too_long' using errcode = '22023'; end if;
  select * into v_old from site_settings where id = 1;
  insert into site_settings (id, closed, message, updated_at, updated_by)
  values (1, p_closed, v_msg, now(), auth.uid())
  on conflict (id) do update
    set closed = excluded.closed,
        -- Opening keeps the last notice, so it is there to re-use next time.
        message = case when excluded.closed then excluded.message else coalesce(excluded.message, site_settings.message) end,
        updated_at = now(),
        updated_by = auth.uid();
  perform public._admin_log(case when p_closed then 'site.closed' else 'site.opened' end, 'site_settings', '1',
    jsonb_build_object('closed', v_old.closed, 'message', v_old.message),
    jsonb_build_object('closed', p_closed, 'message', v_msg));
  return public.site_status();
end $$;
revoke all on function public.admin_set_site_status(boolean, text) from public, anon;
grant execute on function public.admin_set_site_status(boolean, text) to authenticated;

-- Final check: everything in place.
do $$
begin
  if to_regclass('public.site_settings') is null
     or to_regprocedure('public.site_status()') is null
     or to_regprocedure('public.admin_set_site_status(boolean, text)') is null
     or not exists (select 1 from public.site_settings where id = 1) then
    raise exception '0068: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

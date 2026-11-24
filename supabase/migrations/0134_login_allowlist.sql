-- =====================================================================
-- 0134 — Who stays in while the site is closed (owner, 24.11.2026: "sayt
-- bağlıdır aktiv etdiyimdə sadəcə icazə girişi olan istifadəçilər saytda
-- qala bilir: admin, Baş admin və icazə verilən istifadəçi").
--
-- * users.login_allowed: the account may use the app while the site is
--   closed (0068). Empty / false = not. Admins (also the Baş admin) always.
-- * site_status() (0068) also answers 'allowed' for the caller (admin OR
--   on the list), so the app lets him in; everybody else (visitors too)
--   keeps seeing the owner's notice, as before.
-- * login_allowlist_hook(event): a Supabase Auth "Custom Access Token" hook
--   — once the owner switches it on in Supabase (Authentication → Hooks),
--   the server itself refuses a sign-in / token renewal of a not-allowed
--   account WHILE THE SITE IS CLOSED (a new account is not on the list, so
--   no registration then either). An open site: everybody as before. Any
--   error inside lets the token through (a glitch never locks everybody
--   out); the app check stays as well.
-- * Only admins give / take the permission, through
--   admin_user_login_allowed_set (checked on the server, Audit Log). A user
--   never gives it to himself (trigger, every signed-in path).
--
-- Safe: forward-only, re-runnable. One new column left empty (no row's
-- data changes), one replaced function with the same answer plus one field,
-- three new functions, one trigger. Nothing is deleted.
-- =====================================================================

begin;

alter table public.users add column if not exists login_allowed boolean;

-- May this account use the app now? (an open site = yes; admins = yes)
create or replace function public.login_allowed_for(p_user uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select not coalesce((select s.closed from site_settings s where s.id = 1), false)
      or exists (select 1 from users u
                  where u.id = p_user
                    and (u.role = 'admin' or coalesce(u.login_allowed, false)));
$$;
revoke all on function public.login_allowed_for(uuid) from public, anon, authenticated;

-- 0068's state + 'allowed' (same keys as before, one more): the caller is
-- an admin or on the list — he keeps using a closed site.
create or replace function public.site_status()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
           'closed', coalesce(s.closed, false),
           'message', s.message,
           'admin', public.is_admin(),
           'allowed', auth.uid() is not null
                      and exists (select 1 from users u where u.id = auth.uid()
                                     and (u.role = 'admin' or coalesce(u.login_allowed, false))))
    from (select 1) one
    left join public.site_settings s on s.id = 1;
$$;
revoke all on function public.site_status() from public;
grant execute on function public.site_status() to anon, authenticated;

-- Admins only: one account on / off the list; logged.
create or replace function public.admin_user_login_allowed_set(p_user uuid, p_allowed boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old boolean;
begin
  perform public._require_admin();
  if p_user is null or p_allowed is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select coalesce(login_allowed, false) into v_old from users where id = p_user;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update users set login_allowed = p_allowed, updated_at = now() where id = p_user;
  perform public._admin_log(case when p_allowed then 'user.login_allowed' else 'user.login_denied' end, 'user', p_user::text,
    jsonb_build_object('login_allowed', v_old), jsonb_build_object('login_allowed', p_allowed));
end $$;
revoke all on function public.admin_user_login_allowed_set(uuid, boolean) from public, anon;
grant execute on function public.admin_user_login_allowed_set(uuid, boolean) to authenticated;

-- Nobody gives himself the permission (users may update their own row).
create or replace function public.users_login_allowed_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.login_allowed is distinct from old.login_allowed
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.users_login_allowed_guard() from public, anon, authenticated;
drop trigger if exists zz_users_login_allowed_guard on public.users;
create trigger zz_users_login_allowed_guard before update of login_allowed on public.users
  for each row execute function public.users_login_allowed_guard();

-- Supabase Auth hook (Authentication → Hooks → Customize Access Token):
-- refuses the token of a not-allowed account while the site is closed.
create or replace function public.login_allowlist_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_user uuid;
begin
  begin
    v_user := (event ->> 'user_id')::uuid;
    if v_user is not null and not public.login_allowed_for(v_user) then
      return jsonb_build_object('error', jsonb_build_object(
        'http_code', 403,
        'message', 'site_closed: Sayt hazırda bağlıdır'));
    end if;
  exception when others then
    return event; -- a glitch never locks everybody out
  end;
  return event;
end $$;
revoke all on function public.login_allowlist_hook(jsonb) from public, anon, authenticated;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    execute 'grant usage on schema public to supabase_auth_admin';
    execute 'grant execute on function public.login_allowlist_hook(jsonb) to supabase_auth_admin';
  end if;
end $$;

-- Final check: everything in place.
do $$
begin
  if to_regprocedure('public.login_allowed_for(uuid)') is null
     or to_regprocedure('public.admin_user_login_allowed_set(uuid, boolean)') is null
     or to_regprocedure('public.login_allowlist_hook(jsonb)') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'users' and column_name = 'login_allowed') then
    raise exception '0134: final check failed — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

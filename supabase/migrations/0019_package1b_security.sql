-- =====================================================================
-- 0019 — PACKAGE 1B: user privacy & account security (forward-only)
--
-- Apply AFTER 0018. If 0018 is missing, 0019 still applies safely (it
-- normalizes search_path itself) but warns: 0018 holds other critical fixes.
--
-- SAFE FORWARD MIGRATION
--   * No table dropped, truncated or recreated; no row changed or deleted.
--   * Only one SELECT policy, one view, two functions and grants change.
--   * 0001–0018 are NOT edited. Idempotent (safe to run twice).
--
-- TRANSACTION: no BEGIN/COMMIT inside — `supabase db push` and the SQL
-- Editor run it atomically; with psql use --single-transaction.
--
-- BEFORE RUNNING ON PRODUCTION
--   1. Backup.
--   2. Deploy the Package 1B Flutter build FIRST and let clients update.
--      It works before and after this migration (it falls back to the old
--      queries while the view / RPC do not exist yet).
--   3. Old PWA builds still cached on phones keep working for login,
--      own profile, loads, chat and admin, but show OTHER users' names /
--      avatars / phone as empty until they reload (they read
--      public.users directly). See docs/reports/PACKAGE_1B_REPORT.md.
--
-- What changes
--   1. public.users: each signed-in user reads ONLY their own row;
--      admins read all rows (existing users_admin_full policy).
--      email, phone, preferred_lang, is_blocked, blocked_until,
--      block_reason are therefore no longer visible to other users.
--   2. public.user_profiles: read-only view with PUBLIC columns only
--      (name, avatar, role, badges, last seen, active flag) for every
--      user — what other people may legitimately see.
--   3. get_cargo_contact(load): poster's name / phone / e-mail for a load
--      the caller can see (keeps the load-detail contact block working).
--      get_user_contact(user): phone / e-mail released only when there is
--      a reason (self, admin, paid contact unlock, the person wrote to you,
--      the person runs a live advert or has an open published load).
--   4. guard_user_protected_columns(): no auth.uid()-is-null shortcut;
--      trusted-caller check by current_user (as guard_service_provider in
--      0018); e-mail, id, created_at also pinned (e-mail squatting could
--      block a victim's signup through the unique constraint).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) public.users rows: own row only (+ admins via users_admin_full)
-- ---------------------------------------------------------------------
-- Root cause: users_select_all (0002, narrowed to `authenticated` in 0009)
-- was `using (true)`: every signed-in user could list every user's
-- e-mail, phone, preferred language and moderation state (is_blocked,
-- blocked_until, block_reason).
drop policy if exists "users_select_all" on public.users;
drop policy if exists "users_select_own" on public.users;
-- NOTE: plain auth.uid(), deliberately NOT wrapped in (select …): the
-- users_update_self policy (0002) reads public.users in its WITH CHECK,
-- and Postgres raises "infinite recursion detected in policy" when a
-- re-entered relation's policies contain a sub-query. Users only ever
-- match one row here, so the per-row call costs nothing.
create policy "users_select_own" on public.users
  for select to authenticated
  using (id = auth.uid());
-- users_admin_full (0002: FOR ALL USING is_admin()) remains and gives
-- admins every row and column — the admin panel (incl. its Realtime
-- stream of public.users) keeps working unchanged.

-- ---------------------------------------------------------------------
-- 2) Public profile view
-- ---------------------------------------------------------------------
-- Owned by the migration role, so it reads public.users with the owner's
-- rights (bypassing the row filter above) but exposes ONLY these
-- columns. security_barrier stops user-supplied filter functions from
-- being pushed below the view. This is intentionally a definer-rights
-- view (Supabase's linter will flag "security_definer_view"): that is how
-- the column subset is published to everyone.
create or replace view public.user_profiles
with (security_barrier = true) as
  select u.id,
         u.role,
         u.full_name,
         u.avatar_url,
         u.is_verified,
         u.is_early_member,
         u.last_seen_at,
         u.is_active,
         u.created_at
  from public.users u;

comment on view public.user_profiles is
  'Public profile fields of every user (no e-mail, phone, language or moderation data). '
  'Readable by signed-in users only. Contact data: get_user_contact().';

revoke all on public.user_profiles from public, anon, authenticated;
grant select on public.user_profiles to authenticated;
grant select on public.user_profiles to service_role;

-- ---------------------------------------------------------------------
-- 3) Contact details on a need-to-know basis
-- ---------------------------------------------------------------------
-- Returns {"full_name", "phone", "email", "reason"}; phone / email are
-- null when the caller has no reason to see them.
--   self / admin              -> phone + email
--   paid unlock (0006) of a load owned by that user -> phone + email
--     (this used to be only a UI gate because the data was public)
--   that user has sent the caller a direct message -> phone
--     (call button in an active chat)
--   that user runs a live advert -> phone (advertiser profile)
-- Blocked / deactivated callers only ever get their own data.
create or replace function public.get_user_contact(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_u public.users;
  v_reason text;
  v_full boolean := false;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_u from public.users where id = p_user;
  if not found then
    return null;
  end if;

  if p_user = v_me then
    v_reason := 'self'; v_full := true;
  elsif public.is_admin() then
    v_reason := 'admin'; v_full := true;
  elsif public.is_blocked(v_me) then
    v_reason := null;
  elsif exists (
      select 1 from public.contact_unlocks cu
      join public.cargo c on c.id = cu.cargo_id
      where cu.carrier_id = public.current_carrier_id() and c.owner_id = p_user) then
    v_reason := 'unlocked'; v_full := true;
  elsif exists (
      select 1 from public.messages m
      where m.sender_id = p_user and m.receiver_id = v_me) then
    v_reason := 'messaged_you';
  elsif exists (
      select 1 from public.ads a
      where a.advertiser_id = p_user and a.is_active
        and now() >= a.starts_at and now() < a.ends_at) then
    v_reason := 'advertiser';
  elsif exists (
      select 1 from public.cargo c
      where c.owner_id = p_user and c.status = 'new' and not c.is_hidden) then
    -- has a published, open load: the phone is already shown on that
    -- load (get_cargo_contact), so the profile's call button may show it
    v_reason := 'open_load';
  end if;

  return jsonb_build_object(
    'full_name', v_u.full_name,
    'phone',     case when v_reason is not null then v_u.phone end,
    'email',     case when v_full then v_u.email end,
    'reason',    v_reason);
end;
$$;
revoke execute on function public.get_user_contact(uuid) from public, anon;
grant execute on function public.get_user_contact(uuid) to authenticated, service_role;

-- Contact block on a load's detail page ("Elan sahibi ilə əlaqə").
-- Existing marketplace behaviour is kept: anyone signed in who can SEE the
-- load (same rule as the cargo SELECT policy from 0012) gets the poster's
-- name, phone and e-mail. What is no longer possible is reading the
-- contact data of users who have not published a load to you.
-- Blocked / deactivated callers get nothing (they cannot act on it).
create or replace function public.get_cargo_contact(p_cargo uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_c public.cargo;
  v_u public.users;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_c from public.cargo where id = p_cargo;
  if not found then
    return null;
  end if;
  if not (not v_c.is_hidden or v_c.owner_id = v_me or public.is_admin()
          or public.can_see_hidden_cargo(p_cargo)) then
    return null;                               -- caller cannot see this load
  end if;
  if v_c.owner_id <> v_me and not public.is_admin() and public.is_blocked(v_me) then
    return null;
  end if;
  select * into v_u from public.users where id = v_c.owner_id;
  return jsonb_build_object(
    'owner_id',  v_c.owner_id,
    'full_name', v_u.full_name,
    'phone',     v_u.phone,
    'email',     v_u.email);
end;
$$;
revoke execute on function public.get_cargo_contact(uuid) from public, anon;
grant execute on function public.get_cargo_contact(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 4) Protected user columns: trusted-caller check, e-mail pinned
-- ---------------------------------------------------------------------
-- Before: SECURITY DEFINER + "auth.uid() is null -> allow everything".
-- Now SECURITY INVOKER; API roles (anon / authenticated) are restricted
-- unless is_admin(); SQL editor, service_role and SECURITY DEFINER
-- functions (admin_* RPCs, signup trigger) are trusted.
create or replace function public.guard_user_protected_columns()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;                   -- trusted server-side code
  end if;
  if public.is_admin() then
    return new;                   -- admin using the API directly
  end if;
  new.id := old.id;
  new.email := old.email;         -- comes from Supabase Auth, not the client
  new.created_at := old.created_at;
  new.role := old.role;
  new.is_verified := old.is_verified;
  new.is_early_member := old.is_early_member;
  new.is_blocked := old.is_blocked;
  new.blocked_until := old.blocked_until;
  new.block_reason := old.block_reason;
  new.is_active := old.is_active;
  return new;
end;
$$;
-- (trigger guard_user_protected on public.users from 0009 already calls it)

-- ---------------------------------------------------------------------
-- 4b) search_path of every SECURITY DEFINER function (same rule as 0018)
-- ---------------------------------------------------------------------
-- 0019 no longer ASSUMES 0018 ran: on a database without 0018 the 0005–0017
-- functions still have `search_path=public` (pg_temp implicitly first) and
-- is_admin()/current_carrier_id() have none. They are normalized here with
-- the same rule and the same strict check as 0018 (idempotent: a database
-- that already ran 0018 is left unchanged).
do $$
declare
  f record;
  v_new text;
begin
  for f in
    select p.oid::regprocedure as sig,
           p.proowner,
           (select substr(c, 13) from unnest(coalesce(p.proconfig, '{}')) c
             where c like 'search_path=%' limit 1) as sp
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and not exists (select 1 from pg_depend d                 -- extension-owned
                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
  loop
    if f.sp is null then
      -- no path at all (is_admin, current_carrier_id in 0002): Supabase's
      -- default lookup order, with pg_temp pinned last
      v_new := 'public, extensions, pg_temp';
    elsif btrim(f.sp) in ('', '""') then
      continue;                 -- empty path = strictest form: keep as is
    elsif f.sp ~* '(^|,)\s*"?pg_temp"?\s*$' then
      continue;                 -- already safe: pg_temp is last
    else
      -- keep every schema the function relies on, put pg_temp last
      select string_agg(x, ', ' order by ord) into v_new
      from (select btrim(x0) as x, ord
            from unnest(string_to_array(f.sp, ',')) with ordinality as t(x0, ord)) s
      where x <> '' and lower(btrim(x, '"')) <> 'pg_temp';
      v_new := coalesce(v_new || ', ', '') || 'pg_temp';
    end if;
    if not pg_has_role(current_user, f.proowner, 'USAGE') then
      raise warning '0019: % is owned by % — cannot change its search_path from this role',
        f.sig, pg_get_userbyid(f.proowner);
      continue;                 -- the self-check below will name it
    end if;
    execute format('alter function %s set search_path = %s', f.sig, v_new);
    raise notice '0019: % search_path: % -> %', f.sig, coalesce(f.sp, '<none>'), v_new;
  end loop;
end $$;

-- 0018 carries other critical fixes (admin signup, service visibility, …).
do $$
begin
  if to_regprocedure('public.service_provider_notes(uuid[])') is null then
    raise warning '0019: migration 0018 has NOT been applied to this database — apply 0018 as well (see docs/reports/PACKAGE_1_SECURITY_REPORT.md)';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 5) Self-checks (abort + roll back if something is off)
-- ---------------------------------------------------------------------
do $$
declare v_bad text; v_ext text;
begin
  select string_agg(format('%s [owner %s, search_path=%s]', s.sig, s.owner, coalesce(s.sp, '<none>')), '; ')
    into v_bad
  from (select p.oid::regprocedure::text as sig,
               pg_get_userbyid(p.proowner) as owner,
               (select substr(c, 13) from unnest(coalesce(p.proconfig, '{}')) c
                 where c like 'search_path=%' limit 1) as sp
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.prosecdef
          and not exists (select 1 from pg_depend d
                          where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')) s
  where s.sp is null
     or not (btrim(s.sp) in ('', '""') or s.sp ~* '(^|,)\s*"?pg_temp"?\s*$');
  if v_bad is not null then
    raise exception '0019 self-check: SECURITY DEFINER function(s) with missing or unsafe search_path (must be set, and either empty or with pg_temp last): %', v_bad;
  end if;

  -- extension-owned functions are managed by their extension: reported, not altered
  select string_agg(p.oid::regprocedure::text, ', ') into v_ext
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
    and exists (select 1 from pg_depend d
                where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e');
  if v_ext is not null then
    raise notice '0019: extension-owned SECURITY DEFINER functions in public (not checked): %', v_ext;
  end if;
end $$;

do $$
declare v_bad text;
begin
  -- the open policy must be gone, the own-row policy present
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'users'
             and policyname = 'users_select_all') then
    raise exception '0019 self-check: users_select_all still present';
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'users'
                 and policyname = 'users_admin_full') then
    raise exception '0019 self-check: users_admin_full missing — admins would lose access';
  end if;
  -- no private column in the public view
  select string_agg(column_name, ', ') into v_bad
  from information_schema.columns
  where table_schema = 'public' and table_name = 'user_profiles'
    and column_name in ('email','phone','preferred_lang','is_blocked','blocked_until','block_reason');
  if v_bad is not null then
    raise exception '0019 self-check: private columns in user_profiles: %', v_bad;
  end if;
end $$;

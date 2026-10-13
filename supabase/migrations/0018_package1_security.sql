-- =====================================================================
-- 0018 — PACKAGE 1: critical database security (forward-only, corrective)
--
-- SAFE FORWARD MIGRATION
--   * No table is dropped, truncated or recreated. No row is deleted or
--     changed. (Only privileges, policies, functions, one trigger
--     function and one CHECK constraint are redefined.)
--   * Historical migrations 0001–0017 are NOT edited.
--   * Idempotent: running it twice gives the same result.
--
-- BEFORE RUNNING ON PRODUCTION
--   1. Take a backup (Dashboard → Database → Backups, or
--      `supabase db dump --data-only > backup_before_0018.sql` plus
--      `supabase db dump > schema_before_0018.sql`).
--   2. Deploy the matching Flutter build FIRST (services_repository.dart
--      from this package). It works both before and after this migration.
--      Clients still running the OLD build will get "permission denied"
--      on service detail / edit / admin-services screens until they
--      reload, because the old build reads `select *` (which includes
--      admin_note) — see section 3.
--   3. Run the read-only audit query at the bottom (section 9) and check
--      that every admin account is one you expect.
--
-- What it fixes (details in docs/reports/PACKAGE_1_SECURITY_REPORT.md):
--   1. Signup could create an ADMIN account (role taken from client
--      metadata).
--   2. Pending service profiles were visible to every user.
--   3. admin_note (internal moderation note) was readable by every
--      signed-in user, via the table and via nearby_services().
--   4. guard_service_provider() trusted a session setting
--      (app.service_rating_sync) that any SQL session can set, and let
--      blocked owners keep editing.
--   5. SECURITY DEFINER hygiene: missing / incomplete search_path,
--      EXECUTE granted to anon on every RPC.
--   6. reports.target_type constraint is pinned by exact name and
--      preserves every target type already present in the data.
--
-- TRANSACTION: the file has no BEGIN/COMMIT of its own so it composes
-- with the caller's transaction. `supabase db push` and the Dashboard
-- SQL Editor both run it atomically. With psql use:
--   psql --single-transaction -v ON_ERROR_STOP=1 -f 0018_package1_security.sql
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) Signup may never grant the admin role
-- ---------------------------------------------------------------------
-- Root cause: handle_new_auth_user() (0005) copied raw_user_meta_data->>'role'
-- straight into public.users.role. raw_user_meta_data is whatever the
-- client passes to auth.signUp(data: {...}), and the users.role CHECK
-- allows 'admin'. Anyone could register as admin with the public anon key.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := new.raw_user_meta_data->>'role';
begin
  -- Only self-service roles are accepted from signup metadata.
  -- 'admin' (or anything unknown) silently becomes the default role.
  if v_role is null or v_role not in ('cargo_owner', 'carrier', 'driver') then
    v_role := 'cargo_owner';
  end if;
  insert into public.users (id, email, full_name, role, phone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    v_role,
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 2) Service provider visibility
-- ---------------------------------------------------------------------
-- Ordinary users: approved profiles whose owner is not blocked.
-- Owners: their own profile in any status. Admins: everything.
-- (select …) wrappers let Postgres evaluate auth.uid()/is_admin() once
-- per query instead of once per row.
drop policy if exists "service_providers_select" on public.service_providers;
create policy "service_providers_select" on public.service_providers
  for select to authenticated
  using (
    (status = 'approved' and (owner_id is null or not public.is_blocked(owner_id)))
    or owner_id = (select auth.uid())
    or (select public.is_admin())
  );

-- ---------------------------------------------------------------------
-- 3) admin_note is not readable through the API
-- ---------------------------------------------------------------------
-- RLS filters rows, not columns, so the note is protected with column
-- privileges: API roles may read every column EXCEPT admin_note.
-- The owner (own profile) and admins read it through
-- service_provider_notes() below. Columns added to the table in the
-- future are NOT readable until granted explicitly (deny by default).
revoke select on table public.service_providers from anon, authenticated;
do $$
declare v_cols text;
begin
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into v_cols
  from information_schema.columns
  where table_schema = 'public' and table_name = 'service_providers'
    and column_name <> 'admin_note';
  execute format('grant select (%s) on table public.service_providers to authenticated', v_cols);
end $$;

create or replace function public.service_provider_notes(p_ids uuid[])
returns table (id uuid, admin_note text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select s.id, s.admin_note
  from public.service_providers s
  where s.id = any (p_ids[1:500])
    and auth.uid() is not null
    and (s.owner_id = auth.uid() or public.is_admin());
$$;

-- nearby_services(): same signature and output shape, except
--   * only APPROVED profiles (no pending / rejected / suspended),
--   * admin_note is no longer part of the result.
-- Still SECURITY INVOKER, so RLS and column privileges also apply.
create or replace function public.nearby_services(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 100,
  p_category text default null,
  p_min_rating numeric default 0,
  p_only_active boolean default false,
  p_kind text default null,
  p_query text default null,
  p_limit integer default 200
) returns jsonb
language sql stable security invoker set search_path = public, pg_temp as $$
  with params as (
    select greatest(1, least(coalesce(p_radius_km, 100), 3000))::double precision as r,
           greatest(1, least(coalesce(p_limit, 200), 500)) as lim,
           nullif(btrim(coalesce(p_query, '')), '') as q
  ), box as (
    select r, lim, q,
           r / 111.0 as dlat,
           r / (111.0 * greatest(cos(radians(p_lat)), 0.02)) as dlng
    from params
  ), hits as (
    select s.id, s.owner_id, s.kind, s.name, s.specialty, s.description, s.categories,
           s.country, s.city, s.address, s.lat, s.lng, s.is_mobile, s.service_radius_km,
           s.phone, s.whatsapp, s.working_hours, s.is_24h, s.is_active, s.status,
           s.is_verified, s.added_by_admin, s.photos, s.rating_avg, s.rating_count,
           s.created_at, s.updated_at,
           2 * 6371 * asin(sqrt(
             power(sin(radians(s.lat - p_lat) / 2), 2) +
             cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2)
           )) as distance_km
    from public.service_providers s, box b
    where s.status = 'approved'
      and s.lat between p_lat - b.dlat and p_lat + b.dlat
      and (b.dlng >= 180 or s.lng between p_lng - b.dlng and p_lng + b.dlng)
      and (p_category is null or p_category = any(s.categories))
      and (p_kind is null or s.kind = p_kind)
      and s.rating_avg >= coalesce(p_min_rating, 0)
      and (not coalesce(p_only_active, false) or s.is_active)
      and (s.owner_id is null or not public.is_blocked(s.owner_id))
      and (b.q is null or s.name ilike '%' || b.q || '%' or s.city ilike '%' || b.q || '%'
           or s.specialty ilike '%' || b.q || '%')
  )
  select coalesce(jsonb_agg(to_jsonb(h) order by h.distance_km), '[]'::jsonb)
  from (
    select h.* from hits h, box b
    where h.distance_km <= b.r
    order by h.distance_km
    limit (select lim from box)
  ) h;
$$;

-- ---------------------------------------------------------------------
-- 4) guard_service_provider(): no untrusted bypass
-- ---------------------------------------------------------------------
-- Root cause (0017): the guard let ANY row change through when the
-- session setting app.service_rating_sync = 'on'. Session settings are
-- not a security boundary — any SQL session can set them with
-- set_config(). It was also SECURITY DEFINER, so it could not tell who
-- really issued the statement.
--
-- Now SECURITY INVOKER and keyed on current_user, which a client cannot
-- forge:
--   * current_user = anon / authenticated  -> API request: enforce rules
--     (admins, checked with is_admin(), may change anything)
--   * any other role (postgres / SQL editor, service_role, and every
--     SECURITY DEFINER function such as admin_* or recalc_service_rating)
--     -> trusted server-side code
create or replace function public.guard_service_provider()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  if current_user not in ('anon', 'authenticated') then
    return new;                       -- trusted server-side caller
  end if;
  if public.is_admin() then
    return new;                       -- admin using the API directly
  end if;
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if public.is_blocked(auth.uid()) then
    raise exception 'account_blocked' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'pending';
    new.is_verified := false;
    new.added_by_admin := false;
    new.admin_note := null;
    new.rating_avg := 0;
    new.rating_count := 0;
    new.created_at := now();
    new.updated_at := now();
  else
    new.id := old.id;
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.is_verified := old.is_verified;
    new.added_by_admin := old.added_by_admin;
    new.admin_note := old.admin_note;
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
    new.created_at := old.created_at;
  end if;

  -- Only known categories are kept (unchanged from 0017).
  new.categories := coalesce(array(
    select distinct c from unnest(new.categories) c
    where exists (select 1 from public.service_categories sc where sc.id = c)
  ), '{}');
  return new;
end;
$$;

-- Rating recalculation no longer needs (or sets) the session flag: it is
-- SECURITY DEFINER, so the guard sees it as trusted server-side code.
-- Logic otherwise identical to 0017 (concurrency is reviewed in Package 2).
create or replace function public.recalc_service_rating()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  v_id := case when tg_op = 'DELETE' then old.provider_id else new.provider_id end;
  update public.service_providers p set
    rating_avg = coalesce((select round(avg(rating)::numeric, 2) from public.service_reviews where provider_id = v_id), 0),
    rating_count = (select count(*) from public.service_reviews where provider_id = v_id)
  where p.id = v_id;
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 5) SECURITY DEFINER hygiene
-- ---------------------------------------------------------------------
-- 5a) Every SECURITY DEFINER function in schema public gets a SAFE
--     search_path: set, and either empty or with pg_temp LAST (otherwise
--     Postgres searches pg_temp FIRST, so a temporary table could shadow a
--     public one inside a privileged function).
--     * no path (is_admin, current_carrier_id from 0002) -> public, extensions, pg_temp
--     * a path without pg_temp (0005–0017 used `public`)  -> same schemas + pg_temp
--     * empty path, or pg_temp already last               -> unchanged
--     Existing schemas are KEPT, so a hand-written function that relies on
--     e.g. `extensions` keeps working. Extension-owned functions are skipped.
--     ALTER FUNCTION … SET does not change any function body.
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
      raise warning '0018: % is owned by % — cannot change its search_path from this role',
        f.sig, pg_get_userbyid(f.proowner);
      continue;                 -- the self-check below will name it
    end if;
    execute format('alter function %s set search_path = %s', f.sig, v_new);
    raise notice '0018: % search_path: % -> %', f.sig, coalesce(f.sp, '<none>'), v_new;
  end loop;
end $$;

-- 5b) RPCs are callable by signed-in users only. Supabase grants EXECUTE
--     on every new function to PUBLIC and anon; each of these already
--     refuses anonymous callers inside its body, this removes the
--     entry point as well (defence in depth).
--     Helper functions used inside RLS policies (is_admin, is_blocked,
--     current_carrier_id, can_see_hidden_cargo, is_conversation_participant,
--     is_group_member*, is_service_owner, service_is_unclaimed,
--     can_manage_service_folder) keep their grants: policies on tables
--     that anon can query call them, and revoking would turn those
--     queries into errors.
do $$
declare
  v_sig text;
  v_proc regprocedure;
  v_rpcs text[] := array[
    -- admin (0012, 0015, 0017)
    'public._require_admin()',
    'public.admin_dashboard_stats()',
    'public.admin_update_cargo(uuid, jsonb)',
    'public.admin_set_cargo_hidden(uuid, boolean)',
    'public.admin_delete_cargo(uuid, text)',
    'public.admin_update_user(uuid, jsonb)',
    'public.admin_set_user_block(uuid, boolean, timestamptz, text)',
    'public.admin_set_user_active(uuid, boolean)',
    'public.admin_delete_user(uuid, text)',
    'public.admin_set_shipment_status(uuid, text, text)',
    'public.admin_set_offer_status(uuid, text, text)',
    'public.admin_set_report_status(uuid, text, text)',
    'public.admin_update_ad_order(uuid, text, text, text)',
    'public.admin_save_ad(uuid, uuid, uuid, text, text, timestamptz, timestamptz, boolean)',
    'public.admin_set_ad_active(uuid, boolean)',
    'public.admin_save_ad_package(text, text, integer, numeric, boolean)',
    'public.admin_set_ad_payment_info(text)',
    'public.admin_ad_counts()',
    'public.admin_save_service(uuid, jsonb)',
    'public.admin_set_service_status(uuid, text, text)',
    'public.admin_set_service_verified(uuid, boolean)',
    'public.admin_delete_service(uuid, text)',
    'public.admin_resolve_service_claim(uuid, boolean, text)',
    'public.admin_save_service_category(text, jsonb)',
    'public.admin_service_counts()',
    -- user actions (0006, 0011/0013, 0014, 0015, 0016, 0017, 0018)
    'public.unlock_contact(uuid)',
    'public.get_or_create_conversation(uuid, uuid, uuid)',
    'public.get_or_create_direct_conversation(uuid)',
    'public.create_chat_group(text, uuid[])',
    'public.add_chat_group_members(uuid, uuid[])',
    'public.remove_chat_group_member(uuid, uuid)',
    'public.rename_chat_group(uuid, text)',
    'public.mark_chat_group_read(uuid)',
    'public.create_ad_order(text, text)',
    'public.submit_ad_payment(uuid, text)',
    'public.cancel_ad_order(uuid)',
    'public.delete_my_cargo(uuid)',
    'public.get_ad_payment_info()',
    'public.nearby_services(double precision, double precision, double precision, text, numeric, boolean, text, text, integer)',
    'public.service_provider_notes(uuid[])'
  ];
begin
  foreach v_sig in array v_rpcs loop
    v_proc := to_regprocedure(v_sig);
    if v_proc is null then
      raise notice '0018: function % not found — skipped', v_sig;
      continue;
    end if;
    execute format('revoke execute on function %s from public, anon', v_proc);
    if v_sig = 'public._require_admin()' then
      -- internal helper: only called from SECURITY DEFINER functions
      execute format('revoke execute on function %s from authenticated', v_proc);
    else
      execute format('grant execute on function %s to authenticated', v_proc);
    end if;
    execute format('grant execute on function %s to service_role', v_proc);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6) reports.target_type constraint — narrow, data-preserving
-- ---------------------------------------------------------------------
-- 0017 dropped EVERY check constraint on reports whose definition
-- mentioned target_type (whatever its name or other content) and then
-- added a fixed list that would abort the migration if any existing row
-- held a different value. This section:
--   * touches only the constraint named reports_target_type_check;
--   * keeps every target_type value already stored (none is lost or
--     rejected), plus the known app values;
--   * does nothing when the current constraint already matches (the
--     normal case on a database where 0017 succeeded), so on production
--     this section is expected to be a no-op.
--   (If it does rebuild the constraint, reports is locked for the
--   duration of one scan of the table — milliseconds at current size.)
do $$
declare
  v_known text[] := array['cargo','user','message','offer','shipment','service','other'];
  v_extra text[];
  v_allowed text[];
  v_want text;
  v_have text;
begin
  select coalesce(array_agg(distinct r.target_type order by r.target_type), '{}')
    into v_extra
  from public.reports r
  where r.target_type is not null and r.target_type <> all (v_known);

  if cardinality(v_extra) > 0 then
    raise notice '0018: reports contains extra target_type values %, kept as allowed', v_extra;
  end if;
  v_allowed := v_known || v_extra;

  v_want := format('CHECK ((target_type = ANY (ARRAY[%s])))',
    (select string_agg(quote_literal(x) || '::text', ', ') from unnest(v_allowed) x));

  select pg_get_constraintdef(c.oid) into v_have
  from pg_constraint c
  where c.conrelid = 'public.reports'::regclass and c.conname = 'reports_target_type_check';

  if v_have is not distinct from v_want then
    raise notice '0018: reports_target_type_check already correct — unchanged';
  else
    if v_have is not null then
      alter table public.reports drop constraint reports_target_type_check;
    end if;
    execute format(
      'alter table public.reports add constraint reports_target_type_check check (target_type = any (array[%s]))',
      (select string_agg(quote_literal(x), ', ') from unnest(v_allowed) x));
    raise notice '0018: reports_target_type_check rebuilt with %', v_allowed;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 7) Self-check: fail the migration (and roll everything back) if any
--    SECURITY DEFINER function in public still has a missing or unsafe
--    search_path.
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
    raise exception '0018 self-check: SECURITY DEFINER function(s) with missing or unsafe search_path (must be set, and either empty or with pg_temp last): %', v_bad;
  end if;

  -- extension-owned functions are managed by their extension: reported, not altered
  select string_agg(p.oid::regprocedure::text, ', ') into v_ext
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
    and exists (select 1 from pg_depend d
                where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e');
  if v_ext is not null then
    raise notice '0018: extension-owned SECURITY DEFINER functions in public (not checked): %', v_ext;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 9) READ-ONLY AUDIT (run separately, after the migration). Lists every
--    admin account and what role the client asked for at signup.
--    Any admin whose signup metadata says 'admin' registered themselves
--    as admin through the hole fixed in section 1. Review manually;
--    this migration does NOT change any account.
--
--   select u.id, u.email, u.created_at,
--          a.raw_user_meta_data->>'role' as requested_role_at_signup
--   from public.users u join auth.users a on a.id = u.id
--   where u.role = 'admin'
--   order by u.created_at;
-- ---------------------------------------------------------------------

-- =====================================================================
-- 0107 — browsing without an account (owner, 07.11.2026).
--
-- The link opens the app straight away; a visitor who has not signed in
-- (the "anon" role) may LOOK at the public catalogue — Yüklər, TIR Bazarı,
-- TIRPark, Servislər / Mağazalar and the public profile pages — and is
-- sent to sign in for anything else (the app does that).
--
-- What a visitor may read is exactly what a signed-in stranger already
-- reads, and only on this allow-list of public catalogue tables:
--   * the same columns  (the "authenticated" column rights are copied),
--   * the same rows     (every SELECT policy "to authenticated" gets a
--                        twin "<name>_guest" "to anon" with the same rule;
--                        owner / admin parts of a rule are false for a
--                        visitor because auth.uid() is null).
-- Nothing else is opened: no users table, no messages, conversations,
-- bookings, payments, orders, favourites, job centre, admin tables.
-- Writing stays closed to visitors (no insert / update / delete right is
-- given; the server functions that change data keep asking for a login).
--
-- Safe: forward-only, re-runnable (the twin policies are re-made from the
-- current rules each run). No row is changed or deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.market_listings') is null or to_regclass('public.tir_parks') is null
     or to_regclass('public.service_providers') is null or to_regclass('public.user_profiles') is null then
    raise exception '0107: run the earlier migrations (0040, 0077, 0017, 0019) first — nothing changed';
  end if;
end $$;

do $$
declare
  t text;
  c text;
  p record;
  tables text[] := array[
    -- Yüklər
    'cargo', 'cargo_feed_settings', 'cargo_image_templates', 'cargo_size_cards', 'carriers', 'ratings', 'trucks',
    -- the ad card on Yüklər / TIR Bazarı (Premium places) and active ad banners
    'promo_cross', 'place_promo_cross', 'ads',
    -- TIR Bazarı
    'market_listings', 'market_hero',
    -- Servislər / Mağazalar
    'service_providers', 'service_categories', 'service_reviews', 'services_hero',
    -- TIRPark
    'tir_parks', 'tir_park_reviews', 'tirpark_hero',
    -- public profile pages
    'profile_details', 'profile_catalog_items'
  ];
begin
  foreach t in array tables loop
    if to_regclass('public.' || t) is null then continue; end if;

    -- 1) the same columns a signed-in stranger may read
    if has_table_privilege('authenticated', 'public.' || t, 'select') then
      execute format('grant select on public.%I to anon', t);
    else
      for c in
        select column_name from information_schema.column_privileges
        where table_schema = 'public' and table_name = t and grantee = 'authenticated' and privilege_type = 'SELECT'
      loop
        execute format('grant select (%I) on public.%I to anon', c, t);
      end loop;
    end if;

    -- 2) the same rows: a "to anon" twin of every "to authenticated" read rule
    for p in
      select policyname, qual from pg_policies
      where schemaname = 'public' and tablename = t and cmd = 'SELECT'
        and 'authenticated' = any(roles) and not ('public' = any(roles)) and not ('anon' = any(roles))
        and policyname not like '%\_guest' escape '\'
    loop
      execute format('drop policy if exists %I on public.%I', p.policyname || '_guest', t);
      execute format('create policy %I on public.%I for select to anon using (%s)', p.policyname || '_guest', t, p.qual);
    end loop;
  end loop;
end $$;

-- The public profile views (no phone / e-mail in them).
grant select on public.user_profiles to anon;
do $$ begin
  if to_regclass('public.user_activities') is not null then grant select on public.user_activities to anon; end if;
end $$;

-- Read-only helpers the rules above call, and the read-only search
-- functions of the browse pages (they run with the caller's rights, so
-- the rules above still decide what a visitor sees).
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'is_admin', 'is_blocked', 'can_see_hidden_cargo',
      'market_search', 'market_similar', 'market_premium_latest', 'market_vip_latest',
      'nearby_services', 'promo_cross_latest', 'place_cross_latest',
      -- pure helpers the search functions call
      'market_name_key', 'market_lifted_at', 'market_premium_active', 'market_vip_active')
  loop
    execute format('grant execute on function %s to anon', f);
  end loop;
end $$;

notify pgrst, 'reload schema';

commit;

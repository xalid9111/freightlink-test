-- ============================================================
-- FreightLink · Migration 0003 — Demo seed data
-- Every row here has is_demo = true so it can be found and purged
-- in one statement before going to production:
--   delete from public.cargo where is_demo = true;
-- (owner rows cascade-delete cargo_documents/offers/etc. via FKs)
--
-- IMPORTANT CAVEAT (added during Phase 3 verification): this migration
-- writes directly into Supabase's internal `auth.users` table via raw
-- SQL. That table is managed by GoTrue (Supabase Auth) and its exact
-- column set is not a documented, version-stable public API — this is
-- a common community pattern for seed scripts, but it is not the
-- officially supported way to create a user (the Auth API / SDK
-- signUp() is). If `supabase db push` fails specifically on the
-- `insert into auth.users` statement below on your Supabase project
-- version, the fix is to delete that one statement and instead create
-- the three demo accounts by actually registering through the app
-- (RoleSelect → Register) — the trigger in migration 0005 will create
-- their public.users rows correctly either way. The demo `cargo` rows
-- below only need valid `public.users` rows to reference, however
-- those rows come to exist.
-- ============================================================

-- Needed for crypt()/gen_salt() below. Supabase projects normally have
-- this enabled already (GoTrue itself depends on it), but declaring it
-- explicitly here means this migration doesn't silently depend on that
-- being true.
create extension if not exists pgcrypto;

-- Demo auth users. In a real environment these come from
-- supabase.auth.signUp(); this block creates matching auth.users rows
-- directly only so the demo is runnable standalone in a fresh project.
-- instance_id / aud / role are set to the exact values a real signUp()
-- call would produce, to minimize the chance of hitting a NOT NULL or
-- default-value mismatch against your project's schema version.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated', 'demo.owner1@freightlink.test', crypt('demo-password', gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222', 'authenticated', 'authenticated', 'demo.owner2@freightlink.test', crypt('demo-password', gen_salt('bf')), now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '33333333-3333-3333-3333-333333333333', 'authenticated', 'authenticated', 'demo.carrier1@freightlink.test', crypt('demo-password', gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

-- migration 0005 (applied after this one, in a fresh `db push`) would
-- normally create these rows via trigger — but 0005 doesn't exist yet
-- at the point this migration runs, so they're inserted directly here,
-- exactly as they were before 0005 was added. No double-insert risk.
insert into public.users (id, role, full_name, email, is_verified) values
  ('11111111-1111-1111-1111-111111111111', 'cargo_owner', 'CargoLine LLC (demo)', 'demo.owner1@freightlink.test', true),
  ('22222222-2222-2222-2222-222222222222', 'cargo_owner', 'Trans-Volga (demo)', 'demo.owner2@freightlink.test', true),
  ('33333333-3333-3333-3333-333333333333', 'carrier', 'Elvin Həsənov (demo)', 'demo.carrier1@freightlink.test', true)
on conflict (id) do nothing;

insert into public.carriers (id, user_id, status, current_latitude, current_longitude, rating_avg, completed_count, is_verified)
values ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'boş', 40.4093, 49.8671, 4.9, 127, true)
on conflict (id) do nothing;

insert into public.trucks (carrier_id, brand, model, year, capacity_kg, body_type, status)
values ('44444444-4444-4444-4444-444444444444', 'Mercedes-Benz', 'Actros', 2021, 24000, 'Tent', 'boş');

-- Demo cargo — same four shipments used in the Phase 1 frontend prototype,
-- now expressed against the real schema, all flagged is_demo = true.
insert into public.cargo (
  owner_id, pickup_country, pickup_city, pickup_latitude, pickup_longitude,
  destination_country, destination_city, destination_latitude, destination_longitude,
  cargo_type, weight_kg, truck_type, pickup_date, delivery_deadline,
  offered_price, currency, description, distance_km, status, is_demo
) values
  ('11111111-1111-1111-1111-111111111111', 'Türkiyə', 'İstanbul', 41.0082, 28.9784,
   'Azərbaycan', 'Bakı', 40.4093, 49.8671,
   'Qida məhsulları', 18000, 'Tent', current_date + 1, current_date + 4,
   1850, 'AZN', 'Palet üzərində, rampa lazımdır. (DEMO DATA)', 1250, 'new', true),

  ('22222222-2222-2222-2222-222222222222', 'Belarus', 'Minsk', 53.9006, 27.5590,
   'Türkiyə', 'İstanbul', 41.0082, 28.9784,
   'Soyuq zəncir', 22000, 'Refrigerated', current_date + 3, current_date + 9,
   3900, 'AZN', '−18°C temperatur rejimi tələb olunur. (DEMO DATA)', 2380, 'new', true),

  ('11111111-1111-1111-1111-111111111111', 'Azərbaycan', 'Bakı', 40.4093, 49.8671,
   'Gürcüstan', 'Tbilisi', 41.7151, 44.8271,
   'Tikinti materialları', 20000, 'Tent', current_date + 2, current_date + 4,
   1200, 'AZN', 'Yükləmə vaxtı: 08:00–12:00. (DEMO DATA)', 560, 'new', true),

  ('22222222-2222-2222-2222-222222222222', 'Türkiyə', 'Trabzon', 41.0027, 39.7168,
   'Azərbaycan', 'Gəncə', 40.6828, 46.3606,
   'Ümumi yük', 24000, 'Mega trailer', current_date + 4, current_date + 7,
   2400, 'AZN', 'Yük hündürlüyü 3.0 m. (DEMO DATA)', 980, 'new', true);

insert into public.platform_settings (key, value) values
  ('commission_pct', '5.0'),
  ('supported_locales', '["az","tr","en","ru","ka"]'),
  ('is_demo_data_present', 'true');

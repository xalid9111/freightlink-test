-- ============================================================
-- FreightLink · Migration 0001 — Schema (tables, FKs, indexes)
-- Apply with: supabase db push
-- ============================================================
create extension if not exists "uuid-ossp";

-- Fix from Phase 1 review: status/enum-like values are stored in
-- English everywhere (see note in PHASE2_REPORT.md, item 2). Only
-- user-facing display text is localized, in assets/i18n/*.json —
-- the database itself must stay language-neutral so a stored status
-- never has to change when a new UI language is added.

-- ---------------------------------------------------------------
-- USERS & ROLES
-- ---------------------------------------------------------------
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('cargo_owner','carrier','driver','admin')),
  full_name text not null,
  email text unique not null,
  phone text unique,
  preferred_lang text not null default 'az' check (preferred_lang in ('az','tr','en','ru','ka')),
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.users is 'One row per authenticated person. Role is fixed at signup; only admins may change it (enforced by RLS, see migration 0002).';

create table public.companies (
  id uuid primary key default uuid_generate_v4(),
  owner_user_id uuid not null references public.users(id) on delete cascade,
  legal_name text not null,
  tax_id text,
  country text,
  logo_url text,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_companies_owner on public.companies(owner_user_id);

create table public.carriers (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null unique references public.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  rating_avg numeric(2,1) not null default 0 check (rating_avg between 0 and 5),
  completed_count integer not null default 0,
  cancelled_count integer not null default 0,
  reliability_score numeric(5,2) not null default 0,
  status text not null default 'boş' check (status in ('boş','yola_hazır','məşğul','servisdə')),
  current_latitude numeric(9,6),
  current_longitude numeric(9,6),
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_carriers_user on public.carriers(user_id);
create index idx_carriers_company on public.carriers(company_id);
create index idx_carriers_location on public.carriers(current_latitude, current_longitude);

create table public.drivers (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid unique references public.users(id) on delete set null,
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  full_name text not null,
  license_no text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_drivers_carrier on public.drivers(carrier_id);

create table public.trucks (
  id uuid primary key default uuid_generate_v4(),
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  driver_id uuid references public.drivers(id) on delete set null,
  brand text,
  model text,
  year integer check (year between 1980 and 2100),
  capacity_kg numeric(10,2),
  body_type text, -- Tent | Refrigerated | Mega trailer | Sistern | ...
  length_m numeric(5,2),
  width_m numeric(5,2),
  height_m numeric(5,2),
  volume_m3 numeric(8,2),
  status text not null default 'boş' check (status in ('boş','məşğul','yola_hazır','servisdə')),
  current_latitude numeric(9,6),
  current_longitude numeric(9,6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_trucks_carrier on public.trucks(carrier_id);
create index idx_trucks_status on public.trucks(status);
create index idx_trucks_location on public.trucks(current_latitude, current_longitude);

-- ---------------------------------------------------------------
-- CARGO
-- ---------------------------------------------------------------
create table public.cargo (
  id uuid primary key default uuid_generate_v4(),
  owner_id uuid not null references public.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,

  pickup_country text not null,
  pickup_city text not null,
  pickup_address text,
  pickup_latitude numeric(9,6),
  pickup_longitude numeric(9,6),

  destination_country text not null,
  destination_city text not null,
  destination_address text,
  destination_latitude numeric(9,6),
  destination_longitude numeric(9,6),

  cargo_type text,
  weight_kg numeric(10,2) not null check (weight_kg > 0),
  volume_m3 numeric(8,2),
  pallet_count integer,

  truck_type text,

  pickup_date date not null,
  delivery_deadline date,

  offered_price numeric(10,2) not null check (offered_price >= 0),
  currency text not null default 'AZN',

  description text,

  distance_km numeric(8,1),

  status text not null default 'new' check (status in
    ('new','carrier_found','agreed','loading','in_transit','delivered','completed','cancelled')),

  is_demo boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_cargo_owner on public.cargo(owner_id);
create index idx_cargo_status on public.cargo(status);
create index idx_cargo_route on public.cargo(pickup_country, destination_country);
create index idx_cargo_pickup_date on public.cargo(pickup_date);
create index idx_cargo_truck_type on public.cargo(truck_type);
-- supports "nearby cargo" queries without a GIS extension for now;
-- swap for a PostGIS geography column + GiST index when volume needs it.
create index idx_cargo_pickup_geo on public.cargo(pickup_latitude, pickup_longitude);

create table public.cargo_documents (
  id uuid primary key default uuid_generate_v4(),
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  doc_type text not null check (doc_type in ('photo','invoice','loading_instruction','other')),
  file_url text not null,
  uploaded_by uuid references public.users(id),
  created_at timestamptz not null default now()
);
create index idx_cargo_documents_cargo on public.cargo_documents(cargo_id);

-- ---------------------------------------------------------------
-- OFFERS
-- ---------------------------------------------------------------
create table public.offers (
  id uuid primary key default uuid_generate_v4(),
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  truck_id uuid references public.trucks(id) on delete set null,
  offered_price numeric(10,2) not null check (offered_price >= 0),
  currency text not null default 'AZN',
  message text,
  status text not null default 'pending' check (status in
    ('pending','accepted','rejected','countered','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (cargo_id, carrier_id, created_at)
);
create index idx_offers_cargo on public.offers(cargo_id);
create index idx_offers_carrier on public.offers(carrier_id);
create index idx_offers_status on public.offers(status);

-- ---------------------------------------------------------------
-- SHIPMENTS
-- ---------------------------------------------------------------
create table public.shipments (
  id uuid primary key default uuid_generate_v4(),
  cargo_id uuid not null unique references public.cargo(id) on delete cascade,
  carrier_id uuid not null references public.carriers(id),
  driver_id uuid references public.drivers(id),
  truck_id uuid references public.trucks(id),
  accepted_offer_id uuid references public.offers(id),
  agreed_price numeric(10,2) not null check (agreed_price >= 0),
  currency text not null default 'AZN',
  pickup_time timestamptz,
  delivery_deadline timestamptz,
  delivered_at timestamptz,
  status text not null default 'new' check (status in
    ('new','carrier_found','agreed','loading','in_transit','delivered','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_shipments_cargo on public.shipments(cargo_id);
create index idx_shipments_carrier on public.shipments(carrier_id);
create index idx_shipments_status on public.shipments(status);

create table public.shipment_status (
  id uuid primary key default uuid_generate_v4(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  status text not null check (status in
    ('new','carrier_found','agreed','loading','in_transit','delivered','completed','cancelled')),
  note text,
  changed_by uuid references public.users(id),
  changed_at timestamptz not null default now()
);
create index idx_shipment_status_shipment on public.shipment_status(shipment_id, changed_at);

-- ---------------------------------------------------------------
-- LOCATIONS / ROUTES  (GPS + route history, live tracking, return-cargo AI)
-- ---------------------------------------------------------------
create table public.locations (
  id uuid primary key default uuid_generate_v4(),
  truck_id uuid references public.trucks(id) on delete cascade,
  shipment_id uuid references public.shipments(id) on delete cascade,
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  recorded_at timestamptz not null default now()
);
create index idx_locations_truck on public.locations(truck_id, recorded_at desc);
create index idx_locations_shipment on public.locations(shipment_id, recorded_at desc);
comment on table public.locations is 'GPS pings — one row per tracked point. Feeds live tracking, route history, and the "return cargo" AI (last known point of a truck finishing a route).';

create table public.routes (
  id uuid primary key default uuid_generate_v4(),
  shipment_id uuid references public.shipments(id) on delete cascade,
  provider text not null default 'mapbox', -- 'mapbox' | 'google_maps' — never hardcoded into business logic
  polyline text,
  distance_km numeric(8,1),
  duration_min integer,
  created_at timestamptz not null default now()
);
create index idx_routes_shipment on public.routes(shipment_id);

-- ---------------------------------------------------------------
-- MESSAGING
-- ---------------------------------------------------------------
-- Added beyond the literal table list: a lightweight `conversations`
-- table. The spec messages.conversation_id field implies grouping
-- by conversation; without this table that FK would have nothing to
-- reference. One conversation = one cargo_id + the two participants.
create table public.conversations (
  id uuid primary key default uuid_generate_v4(),
  cargo_id uuid references public.cargo(id) on delete cascade,
  shipment_id uuid references public.shipments(id) on delete set null,
  cargo_owner_id uuid not null references public.users(id),
  carrier_user_id uuid not null references public.users(id),
  created_at timestamptz not null default now(),
  unique (cargo_id, carrier_user_id)
);
create index idx_conversations_cargo on public.conversations(cargo_id);
create index idx_conversations_participants on public.conversations(cargo_owner_id, carrier_user_id);

create table public.message_attachments (
  id uuid primary key default uuid_generate_v4(),
  file_url text not null,
  file_type text,
  created_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  shipment_id uuid references public.shipments(id) on delete set null,
  sender_id uuid not null references public.users(id),
  receiver_id uuid not null references public.users(id),
  message text,
  attachment_id uuid references public.message_attachments(id),
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_messages_conversation on public.messages(conversation_id, created_at);
create index idx_messages_receiver on public.messages(receiver_id, read_at);
-- Required for Supabase Realtime: publish this table so clients can
-- subscribe to `postgres_changes` scoped to conversation_id (see
-- migration 0003 / lib/features/chat).
alter publication supabase_realtime add table public.messages;

-- ---------------------------------------------------------------
-- RATINGS
-- ---------------------------------------------------------------
create table public.ratings (
  id uuid primary key default uuid_generate_v4(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  reviewer_id uuid not null references public.users(id),
  reviewed_user_id uuid not null references public.users(id),
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (shipment_id, reviewer_id)
);
create index idx_ratings_reviewed_user on public.ratings(reviewed_user_id);
create index idx_ratings_shipment on public.ratings(shipment_id);

-- ---------------------------------------------------------------
-- VERIFICATION
-- ---------------------------------------------------------------
create table public.verification_documents (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  doc_type text not null check (doc_type in
    ('identity','company','driver_license','truck_documents','insurance','tax_info')),
  file_url text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_verification_user on public.verification_documents(user_id);
create index idx_verification_status on public.verification_documents(status);

-- ---------------------------------------------------------------
-- AI MATCHING
-- ---------------------------------------------------------------
create table public.ai_matches (
  id uuid primary key default uuid_generate_v4(),
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  truck_id uuid references public.trucks(id) on delete set null,
  match_score numeric(5,2) not null check (match_score between 0 and 100),
  distance_to_pickup numeric(8,1),
  estimated_distance numeric(8,1),
  estimated_duration integer,          -- minutes
  estimated_earnings numeric(10,2),
  matching_reasons jsonb,              -- e.g. ["truck_type_match","location_nearby","price_in_range"]
  model_version text,
  created_at timestamptz not null default now()
);
create index idx_ai_matches_cargo on public.ai_matches(cargo_id);
create index idx_ai_matches_carrier on public.ai_matches(carrier_id);
create index idx_ai_matches_score on public.ai_matches(match_score desc);
comment on table public.ai_matches is 'Persisted output of the Phase 11 Edge Function, so results are auditable and re-usable without re-calling OpenAI on every screen view.';

-- ---------------------------------------------------------------
-- PAYMENTS (mock-first, provider-abstracted per brief §22)
-- ---------------------------------------------------------------
create table public.payments (
  id uuid primary key default uuid_generate_v4(),
  shipment_id uuid not null references public.shipments(id),
  payer_id uuid not null references public.users(id),
  payee_id uuid not null references public.users(id),
  amount numeric(10,2) not null check (amount >= 0),
  currency text not null default 'AZN',
  commission_pct numeric(5,2) not null default 5.0,
  commission_amount numeric(10,2) generated always as (round(amount * commission_pct / 100, 2)) stored,
  carrier_payout numeric(10,2) generated always as (amount - round(amount * commission_pct / 100, 2)) stored,
  provider text not null default 'mock' check (provider in ('mock','stripe','local_az_provider','bank_gateway')),
  status text not null default 'deposited' check (status in ('deposited','released','refunded','failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_payments_shipment on public.payments(shipment_id);
create index idx_payments_participants on public.payments(payer_id, payee_id);

-- ---------------------------------------------------------------
-- NOTIFICATIONS
-- ---------------------------------------------------------------
create table public.notifications (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  type text not null,
  title text not null,
  body text,
  data jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_notifications_user on public.notifications(user_id, is_read);
alter publication supabase_realtime add table public.notifications;

-- ---------------------------------------------------------------
-- PLATFORM SETTINGS
-- ---------------------------------------------------------------
create table public.platform_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

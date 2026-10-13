-- ============================================================
-- FreightLink · Migration 0006 — Monetization architecture
-- (Contact Credits, Pro subscriptions, VIP/Featured loads)
--
-- Per the product instruction this implements from: build the correct
-- internal structure now; do NOT wire a temporary/fake payment flow.
-- Every actual payment integration point is marked with a comment
-- starting "PAYMENT INTEGRATION POINT". Nothing here talks to any
-- payment provider — there isn't one connected yet.
-- ============================================================

-- ---------------------------------------------------------------
-- CONTACT CREDITS (brief §7)
--
-- Design: a running-balance wallet (fast to read) PLUS an append-only
-- transaction ledger (why the balance is what it is, and an audit
-- trail — never just overwrite a balance with no record of why).
-- A carrier's balance is only ever changed through the
-- unlock_contact() function below or a future payment webhook —
-- never by a direct client UPDATE. This is enforced at the database
-- level (no UPDATE policy exists for credit_wallets — see RLS below),
-- not just by the app choosing not to expose an "edit balance" button.
-- ---------------------------------------------------------------
create table public.credit_wallets (
  carrier_id uuid primary key references public.carriers(id) on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table public.credit_transactions (
  id uuid primary key default uuid_generate_v4(),
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  delta integer not null,  -- positive = credits added, negative = spent
  reason text not null check (reason in
    ('signup_bonus', 'purchase', 'contact_unlock', 'admin_adjustment', 'pro_monthly_grant')),
  reference_id uuid,  -- e.g. the cargo_id unlocked, or a future payments.id
  created_at timestamptz not null default now()
);
create index idx_credit_transactions_carrier on public.credit_transactions(carrier_id, created_at desc);

create table public.contact_unlocks (
  id uuid primary key default uuid_generate_v4(),
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  unlocked_at timestamptz not null default now(),
  unique (carrier_id, cargo_id)  -- unlocking the same cargo twice must never charge twice
);
create index idx_contact_unlocks_carrier on public.contact_unlocks(carrier_id);

-- The ONE function allowed to spend credits. SECURITY DEFINER so it can
-- update credit_wallets (which has no client UPDATE policy) and insert
-- into credit_transactions/contact_unlocks atomically — either the
-- whole unlock succeeds (balance debited, transaction logged, unlock
-- recorded) or none of it does. Called from Flutter as:
--   supabase.rpc('unlock_contact', params: {'p_cargo_id': cargoId})
create or replace function public.unlock_contact(p_cargo_id uuid)
returns table (new_balance integer, already_unlocked boolean) as $$
declare
  v_carrier_id uuid;
  v_balance integer;
  v_already boolean;
begin
  select id into v_carrier_id from public.carriers where user_id = auth.uid();
  if v_carrier_id is null then
    raise exception 'Only a carrier account can unlock contact details.';
  end if;

  select exists(
    select 1 from public.contact_unlocks
    where carrier_id = v_carrier_id and cargo_id = p_cargo_id
  ) into v_already;

  if v_already then
    select balance into v_balance from public.credit_wallets where carrier_id = v_carrier_id;
    return query select v_balance, true;
    return;
  end if;

  -- Row lock prevents two simultaneous unlock calls (e.g. a double-tap)
  -- from both reading the same starting balance and both succeeding.
  select balance into v_balance from public.credit_wallets
    where carrier_id = v_carrier_id for update;

  if v_balance is null then
    insert into public.credit_wallets (carrier_id, balance) values (v_carrier_id, 0);
    v_balance := 0;
  end if;

  if v_balance < 1 then
    raise exception 'insufficient_credits' using errcode = 'P0001';
  end if;

  update public.credit_wallets set balance = balance - 1, updated_at = now()
    where carrier_id = v_carrier_id;
  insert into public.credit_transactions (carrier_id, delta, reason, reference_id)
    values (v_carrier_id, -1, 'contact_unlock', p_cargo_id);
  insert into public.contact_unlocks (carrier_id, cargo_id) values (v_carrier_id, p_cargo_id);

  return query select (v_balance - 1), false;
end;
$$ language plpgsql security definer set search_path = public;

-- New carriers start with a small free balance so the feature is
-- usable/testable before any purchase flow exists. This is a product
-- decision easy to change later (edit the constant below) — it is NOT
-- the payment integration point itself.
create or replace function public.grant_signup_credit_bonus()
returns trigger as $$
begin
  insert into public.credit_wallets (carrier_id, balance) values (new.id, 3);
  insert into public.credit_transactions (carrier_id, delta, reason)
    values (new.id, 3, 'signup_bonus');
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_carrier_created_grant_credits on public.carriers;
create trigger on_carrier_created_grant_credits
  after insert on public.carriers
  for each row execute function public.grant_signup_credit_bonus();

-- ---------------------------------------------------------------
-- PRO SUBSCRIPTION (brief §8)
--
-- Deliberately generic/extensible per the instruction "do not lock us
-- into one pricing model yet": plans are DATA (rows), not hardcoded
-- application logic, so adding a second paid tier or changing prices
-- later needs a row edit, not a code change.
-- ---------------------------------------------------------------
create table public.subscription_plans (
  plan_key text primary key,       -- 'free' | 'pro' | future tiers
  display_name text not null,
  price numeric(10,2),             -- NULL until pricing is finalized with a real payment provider
  currency text not null default 'AZN',
  billing_period text check (billing_period in ('monthly', 'yearly')),
  monthly_credit_grant integer not null default 0,
  benefits jsonb not null default '[]',  -- e.g. ["priority_search","advanced_filters"]
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.subscription_plans (plan_key, display_name, price, billing_period, monthly_credit_grant, benefits) values
  ('free', 'Free', 0, null, 0, '["basic_search"]'),
  -- PAYMENT INTEGRATION POINT: `price` stays NULL until a real payment
  -- provider is connected and pricing is finalized; the app must treat
  -- a NULL price as "not yet purchasable" rather than "free".
  ('pro', 'Pro', null, 'monthly', 20, '["priority_search","advanced_filters","more_contact_unlocks"]');

create table public.user_subscriptions (
  id uuid primary key default uuid_generate_v4(),
  carrier_id uuid not null references public.carriers(id) on delete cascade,
  plan_key text not null references public.subscription_plans(plan_key),
  status text not null default 'active' check (status in ('active', 'cancelled', 'expired')),
  current_period_end timestamptz,
  -- PAYMENT INTEGRATION POINT: populated by whatever payment provider
  -- webhook/Edge Function is added later (e.g. a Stripe subscription
  -- id). NULL means "not tied to any payment provider yet" — true for
  -- every row this migration can create today.
  provider_subscription_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (carrier_id, plan_key)
);
create index idx_user_subscriptions_carrier on public.user_subscriptions(carrier_id);

-- ---------------------------------------------------------------
-- VIP / FEATURED LOADS (brief §9)
--
-- A property of the cargo row itself (not a separate table) since it's
-- a simple flag + expiry, not an entity with its own lifecycle. The
-- guard trigger below is the real enforcement: a cargo owner's normal
-- RLS update rights (migration 0002, cargo_owner_write) let them edit
-- their own cargo freely, which would otherwise let them set
-- is_featured = true on their own listing for free. The trigger blocks
-- that specific change for anyone who isn't an admin or the future
-- payment service — this is server-side enforcement, not a UI
-- restriction (brief §17's explicit requirement).
-- ---------------------------------------------------------------
alter table public.cargo add column is_featured boolean not null default false;
alter table public.cargo add column featured_until timestamptz;
create index idx_cargo_featured on public.cargo(is_featured) where is_featured = true;

create or replace function public.guard_cargo_featured_columns()
returns trigger as $$
begin
  if (new.is_featured is distinct from old.is_featured
      or new.featured_until is distinct from old.featured_until)
     and coalesce(auth.role(), '') <> 'service_role'
     and not public.is_admin() then
    raise exception
      'is_featured/featured_until can only be changed by an admin or the payment '
      'integration service — see migration 0006 for the PAYMENT INTEGRATION POINT.';
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists guard_cargo_featured on public.cargo;
create trigger guard_cargo_featured
  before update on public.cargo
  for each row execute function public.guard_cargo_featured_columns();

-- ============================================================
-- RLS
-- ============================================================
alter table public.credit_wallets enable row level security;
alter table public.credit_transactions enable row level security;
alter table public.contact_unlocks enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.user_subscriptions enable row level security;

-- credit_wallets: carrier can SEE their own balance; there is
-- deliberately NO insert/update/delete policy for a normal user — the
-- only way this table changes is through unlock_contact() or the
-- signup-bonus trigger, both SECURITY DEFINER, both bypassing RLS.
create policy "credit_wallets_owner_select" on public.credit_wallets
  for select using (carrier_id = public.current_carrier_id() or public.is_admin());

create policy "credit_transactions_owner_select" on public.credit_transactions
  for select using (carrier_id = public.current_carrier_id() or public.is_admin());

create policy "contact_unlocks_owner_select" on public.contact_unlocks
  for select using (carrier_id = public.current_carrier_id() or public.is_admin());
-- Unlocks are also inserted only via unlock_contact() (SECURITY
-- DEFINER) — no client insert policy here either.

-- subscription_plans: public read (pricing/benefits are not secret),
-- admin-only write (changing what Pro includes is a business decision).
create policy "subscription_plans_select_all" on public.subscription_plans for select using (true);
create policy "subscription_plans_admin_write" on public.subscription_plans
  for all using (public.is_admin()) with check (public.is_admin());

create policy "user_subscriptions_owner_select" on public.user_subscriptions
  for select using (carrier_id = public.current_carrier_id() or public.is_admin());
-- No client write policy: a subscription is only ever created/changed
-- by the future payment provider's webhook (service_role) or an admin.
create policy "user_subscriptions_admin_write" on public.user_subscriptions
  for all using (public.is_admin()) with check (public.is_admin());

comment on table public.credit_wallets is
  'Carrier contact-credit balance. PAYMENT INTEGRATION POINT: a future '
  'purchase flow adds credits via an insert into credit_transactions '
  '(reason=''purchase'') plus a balance update, from a payment-provider '
  'webhook running with the service_role key — never from the client.';
comment on table public.user_subscriptions is
  'PAYMENT INTEGRATION POINT: rows here should only be created/updated '
  'by a payment provider webhook (service_role) once one is connected. '
  'No such integration exists yet.';

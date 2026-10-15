-- =====================================================================
-- 0037 — Finance & payments (TEST MODE first)
--
-- * Profile → "Maliyyə və ödənişlər": only the finance owner — the admin
--   account with the e-mail xelilov.1881@gmail.com, bound by its user id
--   in public.finance_admins (checked on the server in every function and
--   in RLS). Nobody else can read finance data, not even other admins.
-- * Card / Apple Pay / Google Pay checkout for ad orders. The amount comes
--   from the order on the server, never from the app. One open payment per
--   order + an idempotency key per checkout → a double click can never
--   create a second payment. An order becomes "paid" ONLY when a verified
--   provider event (webhook, checked by the Edge Function) says so, and
--   only in LIVE mode. TEST mode payments never change an order.
-- * Payout accounts (personal card / VÖEN business account): never the
--   full card number or CVV (only last 4 digits; the provider tokenises
--   the card). New accounts stay "pending verification" until the real
--   provider confirms them — nothing is activated by hand.
-- * Changes to payout accounts and settings need a fresh sign-in
--   (password entered again within the last 5 minutes, or MFA aal2).
-- * Append-only finance audit log.
-- * LIVE mode cannot be switched on by this version.
--
-- Safe: forward-only, re-runnable, new tables only; existing data is not
-- changed. admin_review_ad_order is re-created with ONE extra rule: an
-- order already paid by a confirmed card payment can be approved without a
-- receipt (everything else is identical to 0021).
-- =====================================================================

-- 1) Finance owner -----------------------------------------------------
create table if not exists public.finance_admins (
  user_id uuid primary key references public.users (id) on delete cascade,
  email text not null,
  added_at timestamptz not null default now()
);
alter table public.finance_admins enable row level security;
revoke all on public.finance_admins from anon, authenticated;

-- Binds the owner's e-mail to his user id (only an account that is already
-- an admin on the server). Re-runnable; no API access.
create or replace function public.finance_sync_owner()
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  insert into finance_admins (user_id, email)
  select u.id, lower(u.email)
    from auth.users u join public.users p on p.id = u.id
   where lower(u.email) = 'xelilov.1881@gmail.com' and p.role = 'admin'
  on conflict (user_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.finance_sync_owner() from public, anon, authenticated;
select public.finance_sync_owner();

create or replace function public.is_finance_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from finance_admins f join users p on p.id = f.user_id
     where f.user_id = auth.uid() and p.role = 'admin'
  );
$$;
revoke all on function public.is_finance_admin() from public, anon;
grant execute on function public.is_finance_admin() to authenticated;

create or replace function public._require_finance_admin()
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.is_finance_admin() then raise exception 'not_authorized' using errcode = '42501'; end if;
end $$;
revoke all on function public._require_finance_admin() from public, anon, authenticated;

-- Extra authentication: the session must come from a sign-in made in the
-- last p_seconds (the app asks for the password again), or be MFA (aal2).
create or replace function public._require_recent_auth(p_seconds integer default 300)
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
declare j jsonb := auth.jwt(); t double precision;
begin
  if j ->> 'aal' = 'aal2' then return; end if;
  select max((e ->> 'timestamp')::double precision) into t
    from jsonb_array_elements(case when jsonb_typeof(j -> 'amr') = 'array' then j -> 'amr' else '[]'::jsonb end) e
   where e ->> 'method' in ('password', 'otp', 'totp', 'recovery');
  if t is null or t < extract(epoch from now()) - p_seconds then
    raise exception 'reauth_required' using errcode = '42501';
  end if;
end $$;
revoke all on function public._require_recent_auth(integer) from public, anon, authenticated;

-- 2) Append-only audit log -----------------------------------------------
create table if not exists public.finance_audit (
  id bigserial primary key,
  actor uuid,
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists finance_audit_created_idx on public.finance_audit (created_at desc);
alter table public.finance_audit enable row level security;
revoke all on public.finance_audit from anon, authenticated;
grant select on public.finance_audit to authenticated;
drop policy if exists "finance_audit_read" on public.finance_audit;
create policy "finance_audit_read" on public.finance_audit for select to authenticated using (public.is_finance_admin());

create or replace function public._finance_audit_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'finance_audit_is_append_only' using errcode = '42501';
end $$;
drop trigger if exists finance_audit_no_change on public.finance_audit;
create trigger finance_audit_no_change before update or delete on public.finance_audit
  for each row execute function public._finance_audit_immutable();

create or replace function public._finance_log(p_action text, p_entity text, p_id text, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into finance_audit (actor, action, entity, entity_id, details)
  values (auth.uid(), p_action, p_entity, p_id, coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function public._finance_log(text, text, text, jsonb) from public, anon, authenticated;

-- 3) Settings (no row = defaults: OFF) --------------------------------------
create table if not exists public.payment_settings (
  id integer primary key default 1 check (id = 1),
  mode text not null default 'off' check (mode in ('off', 'test', 'live')),
  provider text not null default 'test' check (provider in ('test', 'payriff', 'epoint', 'stripe')),
  commission_pct numeric(5,2) not null default 0 check (commission_pct >= 0 and commission_pct <= 50),
  methods text[] not null default '{card,apple_pay,google_pay}',
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table public.payment_settings enable row level security;
revoke all on public.payment_settings from anon, authenticated;

create or replace function public._payment_settings()
returns public.payment_settings language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select s from payment_settings s where id = 1),
    row(1, 'off', 'test', 0, '{card,apple_pay,google_pay}'::text[], now(), null)::public.payment_settings
  );
$$;
revoke all on function public._payment_settings() from public, anon, authenticated;

create or replace function public.finance_get_settings()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare s public.payment_settings := public._payment_settings();
begin
  perform public._require_finance_admin();
  return jsonb_build_object('mode', s.mode, 'provider', s.provider, 'commission_pct', s.commission_pct,
                            'methods', to_jsonb(s.methods), 'updated_at', s.updated_at, 'live_available', false);
end $$;

create or replace function public.finance_set_settings(p_mode text, p_provider text, p_commission_pct numeric, p_methods text[])
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare old public.payment_settings := public._payment_settings();
begin
  perform public._require_finance_admin();
  perform public._require_recent_auth(300);
  if p_mode = 'live' then raise exception 'live_not_enabled' using errcode = '42501'; end if;
  if p_mode not in ('off', 'test') then raise exception 'invalid_mode' using errcode = '22023'; end if;
  if p_provider not in ('test', 'payriff', 'epoint', 'stripe') then raise exception 'invalid_provider' using errcode = '22023'; end if;
  -- Test mode only runs the built-in test provider (no real money).
  if p_mode = 'test' and p_provider <> 'test' then raise exception 'provider_not_configured' using errcode = '22023'; end if;
  if p_commission_pct is null or p_commission_pct < 0 or p_commission_pct > 50 then
    raise exception 'invalid_commission' using errcode = '22023';
  end if;
  if p_methods is null or cardinality(p_methods) = 0
     or exists (select 1 from unnest(p_methods) m where m not in ('card', 'apple_pay', 'google_pay')) then
    raise exception 'invalid_methods' using errcode = '22023';
  end if;
  insert into payment_settings (id, mode, provider, commission_pct, methods, updated_at, updated_by)
  values (1, p_mode, p_provider, round(p_commission_pct, 2), p_methods, now(), auth.uid())
  on conflict (id) do update set mode = excluded.mode, provider = excluded.provider,
    commission_pct = excluded.commission_pct, methods = excluded.methods,
    updated_at = now(), updated_by = auth.uid();
  perform public._finance_log('settings.update', 'payment_settings', '1',
    jsonb_build_object('old', jsonb_build_object('mode', old.mode, 'provider', old.provider, 'commission_pct', old.commission_pct, 'methods', old.methods),
                       'new', jsonb_build_object('mode', p_mode, 'provider', p_provider, 'commission_pct', p_commission_pct, 'methods', p_methods)));
  return public.finance_get_settings();
end $$;

-- 4) Payments ---------------------------------------------------------------
create table if not exists public.ad_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.ad_orders (id) on delete restrict,
  user_id uuid not null references public.users (id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  method text not null check (method in ('card', 'apple_pay', 'google_pay')),
  provider text not null,
  mode text not null check (mode in ('test', 'live')),
  status text not null default 'created' check (status in ('created', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded')),
  commission numeric(12,2) not null default 0 check (commission >= 0),
  idempotency_key text not null check (length(idempotency_key) between 8 and 80),
  provider_ref text,
  failure_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unique (user_id, idempotency_key)
);
create unique index if not exists ad_payments_provider_ref_uq on public.ad_payments (provider, provider_ref) where provider_ref is not null;
-- One open checkout per order (a double click returns the same one) and at
-- most one successful payment per order and mode.
create unique index if not exists ad_payments_one_open_per_order on public.ad_payments (order_id) where status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_order on public.ad_payments (order_id, mode) where status = 'succeeded';
create index if not exists ad_payments_created_idx on public.ad_payments (created_at desc);
alter table public.ad_payments enable row level security;
revoke all on public.ad_payments from anon, authenticated;
grant select on public.ad_payments to authenticated;
drop policy if exists "ad_payments_read_own_or_finance" on public.ad_payments;
create policy "ad_payments_read_own_or_finance" on public.ad_payments for select to authenticated
  using (user_id = auth.uid() or public.is_finance_admin());

create table if not exists public.ad_payment_events (
  id bigserial primary key,
  provider text not null,
  event_id text not null,
  payment_id uuid,
  type text not null,
  result text not null default 'received',
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  unique (provider, event_id)
);
alter table public.ad_payment_events enable row level security;
revoke all on public.ad_payment_events from anon, authenticated;

-- Is the card checkout open for the current user? LIVE: everybody signed
-- in. TEST: only the finance owner (customers never see test checkout).
create or replace function public.payment_checkout_available()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare s public.payment_settings := public._payment_settings();
begin
  if auth.uid() is null then return jsonb_build_object('available', false); end if;
  if s.mode = 'live' or (s.mode = 'test' and public.is_finance_admin()) then
    return jsonb_build_object('available', true, 'mode', s.mode, 'methods', to_jsonb(s.methods));
  end if;
  return jsonb_build_object('available', false, 'mode', s.mode);
end $$;
revoke all on function public.payment_checkout_available() from public, anon;
grant execute on function public.payment_checkout_available() to authenticated;

-- Start (or re-use) a checkout for my order. Amount = the order's price.
create or replace function public.payment_create(p_order uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_ord public.ad_orders;
  v_pay public.ad_payments;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not ((payment_checkout_available() ->> 'available')::boolean) then
    raise exception 'payments_disabled' using errcode = '42501';
  end if;
  if p_method is null or not (p_method = any (s.methods)) then raise exception 'invalid_method' using errcode = '22023'; end if;
  if p_key is null or length(p_key) not between 8 and 80 or p_key !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  -- Same key again (double click / retry) → the same payment.
  select * into v_pay from ad_payments where user_id = v_uid and idempotency_key = p_key;
  if v_pay.id is not null then return v_pay; end if;

  select * into v_ord from ad_orders where id = p_order for update;
  if v_ord.id is null or v_ord.advertiser_id is distinct from v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_ord.status <> 'pending_payment' or v_ord.payment_status <> 'unpaid' then
    raise exception 'order_not_payable' using errcode = '22023';
  end if;
  if coalesce(v_ord.price, 0) <= 0 then raise exception 'order_not_payable' using errcode = '22023'; end if;
  if exists (select 1 from ad_payments where order_id = p_order and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;

  -- An open checkout for this order already exists → return it.
  select * into v_pay from ad_payments where order_id = p_order and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  insert into ad_payments (order_id, user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (p_order, v_uid, v_ord.price, upper(coalesce(v_ord.currency, 'AZN')), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode,
          round(v_ord.price * s.commission_pct / 100, 2), p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('order_id', p_order, 'amount', v_pay.amount, 'currency', v_pay.currency, 'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.payment_create(uuid, text, text) from public, anon;
grant execute on function public.payment_create(uuid, text, text) to authenticated;

-- Customer: give up an open checkout (e.g. closed the sheet).
create or replace function public.payment_cancel(p_payment uuid)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare v_pay public.ad_payments;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  update ad_payments set status = 'cancelled', updated_at = now()
   where id = p_payment and user_id = auth.uid() and status = 'created'
  returning * into v_pay;
  if v_pay.id is null then
    select * into v_pay from ad_payments where id = p_payment and user_id = auth.uid();
    if v_pay.id is null then raise exception 'payment_not_found' using errcode = 'P0002'; end if;
  else
    perform public._finance_log('payment.cancel', 'payment', v_pay.id::text, '{}'::jsonb);
  end if;
  return v_pay;
end $$;
revoke all on function public.payment_cancel(uuid) from public, anon;
grant execute on function public.payment_cancel(uuid) to authenticated;

-- Edge Function (service role) only: provider reference after the
-- provider created its checkout session.
create or replace function public.payment_attach_provider(p_payment uuid, p_ref text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare v_pay public.ad_payments;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not_authorized' using errcode = '42501'; end if;
  update ad_payments set provider_ref = p_ref, status = 'pending', updated_at = now()
   where id = p_payment and status in ('created', 'pending') and (provider_ref is null or provider_ref = p_ref)
  returning * into v_pay;
  if v_pay.id is null then raise exception 'payment_not_open' using errcode = '22023'; end if;
  return v_pay;
end $$;
revoke all on function public.payment_attach_provider(uuid, text) from public, anon, authenticated;
grant execute on function public.payment_attach_provider(uuid, text) to service_role;

-- Edge Function (service role) only, AFTER it verified the provider's
-- signature. Idempotent per (provider, event id). Amount and currency must
-- match the payment exactly. Only LIVE successes mark the order as paid.
create or replace function public.finance_apply_provider_event(
  p_provider text, p_event_id text, p_payment uuid, p_type text,
  p_amount numeric, p_currency text, p_provider_ref text, p_payload jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_pay public.ad_payments;
  v_new text;
  v_result text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'not_authorized' using errcode = '42501'; end if;
  if p_event_id is null or length(p_event_id) not between 3 and 200 then raise exception 'invalid_event' using errcode = '22023'; end if;

  insert into ad_payment_events (provider, event_id, payment_id, type, payload)
  values (p_provider, p_event_id, p_payment, coalesce(p_type, ''), coalesce(p_payload, '{}'::jsonb))
  on conflict (provider, event_id) do nothing;
  if not found then return 'duplicate'; end if;

  select * into v_pay from ad_payments where id = p_payment for update;
  v_new := case p_type when 'payment.succeeded' then 'succeeded' when 'payment.failed' then 'failed' else null end;
  v_result := case
    when v_pay.id is null then 'unknown_payment'
    when v_new is null then 'ignored_type'
    when v_pay.provider <> p_provider then 'provider_mismatch'
    when p_provider = 'test' and v_pay.mode <> 'test' then 'provider_mismatch'
    when p_amount is distinct from v_pay.amount or upper(coalesce(p_currency, '')) <> v_pay.currency then 'amount_mismatch'
    when v_pay.provider_ref is not null and p_provider_ref is distinct from v_pay.provider_ref then 'ref_mismatch'
    when v_pay.status not in ('created', 'pending') then 'already_final'
    else 'applied' end;
  update ad_payment_events set result = v_result where provider = p_provider and event_id = p_event_id;
  if v_result <> 'applied' then
    perform public._finance_log('provider_event.rejected', 'payment', coalesce(p_payment::text, ''),
      jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'type', p_type, 'result', v_result));
    return v_result;
  end if;

  update ad_payments set status = v_new, provider_ref = coalesce(provider_ref, p_provider_ref),
         confirmed_at = case when v_new = 'succeeded' then now() else confirmed_at end,
         failure_reason = case when v_new = 'failed' then left(coalesce(p_payload ->> 'reason', 'declined'), 200) else null end,
         updated_at = now()
   where id = v_pay.id;

  if v_new = 'succeeded' and v_pay.mode = 'live' then
    update ad_orders
       set payment_status = 'paid', paid_at = coalesce(paid_at, now()),
           payment_reference = coalesce(payment_reference, left(v_pay.provider || ':' || coalesce(p_provider_ref, v_pay.id::text), 120)),
           status = case when status = 'pending_payment' then 'awaiting_approval' else status end,
           updated_at = now()
     where id = v_pay.order_id;
  end if;
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 5) Payout accounts & payouts --------------------------------------------
create table if not exists public.payout_accounts (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users (id) on delete cascade,
  kind text not null check (kind in ('card', 'business')),
  holder_name text not null check (length(btrim(holder_name)) between 2 and 120),
  bank_name text check (bank_name is null or length(bank_name) <= 80),
  card_last4 text check (card_last4 is null or card_last4 ~ '^[0-9]{4}$'),
  card_brand text check (card_brand is null or card_brand in ('visa', 'mastercard', 'other')),
  company_name text check (company_name is null or length(company_name) <= 160),
  voen text check (voen is null or voen ~ '^[0-9]{10}$'),
  iban text check (iban is null or iban ~ '^AZ[0-9]{2}[A-Z]{4}[A-Z0-9]{20}$'),
  provider_token text,
  status text not null default 'pending_verification' check (status in ('pending_verification', 'verified', 'disabled')),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  disabled_at timestamptz,
  check ((kind = 'card' and card_last4 is not null and voen is null and iban is null)
      or (kind = 'business' and voen is not null and iban is not null and company_name is not null and card_last4 is null))
);
create unique index if not exists payout_accounts_one_primary on public.payout_accounts (owner_id) where is_primary and status <> 'disabled';
alter table public.payout_accounts enable row level security;
revoke all on public.payout_accounts from anon, authenticated;

create table if not exists public.payouts (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.payout_accounts (id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  mode text not null check (mode in ('test', 'live')),
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  provider_ref text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table public.payouts enable row level security;
revoke all on public.payouts from anon, authenticated;

create or replace function public._payout_account_json(a public.payout_accounts)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'id', a.id, 'kind', a.kind, 'holder_name', a.holder_name, 'bank_name', a.bank_name,
    'card_last4', a.card_last4, 'card_brand', a.card_brand, 'company_name', a.company_name, 'voen', a.voen,
    -- the full IBAN never leaves the database (payouts run on the server)
    'iban_masked', case when a.iban is null then null else left(a.iban, 4) || ' •••• ' || right(a.iban, 4) end,
    'status', a.status, 'is_primary', a.is_primary, 'created_at', a.created_at, 'verified_at', a.verified_at);
$$;

create or replace function public.finance_list_payout_accounts()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_finance_admin();
  return coalesce((select jsonb_agg(public._payout_account_json(a) order by (a.status = 'disabled'), a.is_primary desc, a.created_at desc)
                     from payout_accounts a where a.owner_id = auth.uid()), '[]'::jsonb);
end $$;

-- Adds a card (last 4 digits only) or a VÖEN business account. It stays
-- "pending verification" — the real provider confirms it later.
create or replace function public.finance_add_payout_account(
  p_kind text, p_holder text, p_bank text default null, p_card_last4 text default null, p_card_brand text default null,
  p_company text default null, p_voen text default null, p_iban text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.payout_accounts; v_iban text := upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g'));
begin
  perform public._require_finance_admin();
  perform public._require_recent_auth(300);
  if (select count(*) from payout_accounts where owner_id = auth.uid() and status <> 'disabled') >= 10 then
    raise exception 'too_many_accounts' using errcode = '54000';
  end if;
  insert into payout_accounts (owner_id, kind, holder_name, bank_name, card_last4, card_brand, company_name, voen, iban, is_primary)
  values (auth.uid(), p_kind, btrim(p_holder), nullif(btrim(p_bank), ''),
          case when p_kind = 'card' then p_card_last4 end,
          case when p_kind = 'card' then coalesce(p_card_brand, 'other') end,
          case when p_kind = 'business' then nullif(btrim(p_company), '') end,
          case when p_kind = 'business' then p_voen end,
          case when p_kind = 'business' then nullif(v_iban, '') end,
          not exists (select 1 from payout_accounts where owner_id = auth.uid() and is_primary and status <> 'disabled'))
  returning * into a;
  perform public._finance_log('payout_account.add', 'payout_account', a.id::text,
    jsonb_build_object('kind', a.kind, 'card_last4', a.card_last4, 'voen', a.voen, 'status', a.status, 'is_primary', a.is_primary));
  return public._payout_account_json(a);
exception when check_violation then
  raise exception 'invalid_account' using errcode = '22023';
end $$;

create or replace function public.finance_set_primary_payout_account(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.payout_accounts;
begin
  perform public._require_finance_admin();
  perform public._require_recent_auth(300);
  select * into a from payout_accounts where id = p_id and owner_id = auth.uid() for update;
  if a.id is null or a.status = 'disabled' then raise exception 'account_not_found' using errcode = 'P0002'; end if;
  update payout_accounts set is_primary = false where owner_id = auth.uid() and is_primary and id <> p_id;
  update payout_accounts set is_primary = true where id = p_id returning * into a;
  perform public._finance_log('payout_account.primary', 'payout_account', p_id::text, '{}'::jsonb);
  return public.finance_list_payout_accounts();
end $$;

create or replace function public.finance_disable_payout_account(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.payout_accounts;
begin
  perform public._require_finance_admin();
  perform public._require_recent_auth(300);
  update payout_accounts set status = 'disabled', is_primary = false, disabled_at = now()
   where id = p_id and owner_id = auth.uid() and status <> 'disabled'
  returning * into a;
  if a.id is null then raise exception 'account_not_found' using errcode = 'P0002'; end if;
  perform public._finance_log('payout_account.disable', 'payout_account', p_id::text, '{}'::jsonb);
  return public.finance_list_payout_accounts();
end $$;

-- Withdrawals run only through a connected provider (none in this version).
create or replace function public.finance_request_payout(p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_finance_admin();
  perform public._require_recent_auth(300);
  if (public._payment_settings()).mode <> 'live' then raise exception 'payouts_need_live_provider' using errcode = '42501'; end if;
  raise exception 'provider_not_configured' using errcode = '42501';
end $$;

-- 6) Dashboard ---------------------------------------------------------------
create or replace function public.finance_summary(p_mode text default 'live')
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_gross numeric; v_comm numeric; v_pending numeric; v_pending_n integer; v_ok_n integer;
  v_sent numeric; v_inflight numeric;
begin
  perform public._require_finance_admin();
  if p_mode not in ('test', 'live') then raise exception 'invalid_mode' using errcode = '22023'; end if;
  select coalesce(sum(amount), 0), coalesce(sum(commission), 0), count(*)
    into v_gross, v_comm, v_ok_n from ad_payments where mode = p_mode and status = 'succeeded';
  select coalesce(sum(amount), 0), count(*) into v_pending, v_pending_n
    from ad_payments where mode = p_mode and status in ('created', 'pending');
  select coalesce(sum(amount) filter (where status = 'sent'), 0), coalesce(sum(amount) filter (where status = 'pending'), 0)
    into v_sent, v_inflight from payouts where mode = p_mode;
  return jsonb_build_object(
    'mode', p_mode,
    'currency', 'AZN',
    'gross', v_gross,
    'commission', v_comm,
    'confirmed_balance', v_gross - v_comm - v_sent,
    'pending', v_pending,
    'pending_count', v_pending_n,
    'succeeded_count', v_ok_n,
    'withdrawable', greatest(v_gross - v_comm - v_sent - v_inflight, 0),
    'transferred', v_sent,
    'payouts_in_progress', v_inflight,
    'has_verified_account', exists (select 1 from payout_accounts where owner_id = auth.uid() and status = 'verified'));
end $$;

create or replace function public.finance_payments(
  p_mode text default 'live', p_status text default null, p_from date default null, p_to date default null,
  p_search text default null, p_limit integer default 50, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare q text := nullif(btrim(coalesce(p_search, '')), '');
begin
  perform public._require_finance_admin();
  return coalesce((
    select jsonb_agg(r order by (r ->> 'created_at') desc)
      from (
        select jsonb_build_object(
                 'id', p.id, 'order_id', p.order_id, 'order_no', o.order_no, 'order_title', o.title,
                 'order_status', o.status, 'order_payment_status', o.payment_status,
                 'customer', coalesce(u.full_name, u.email), 'amount', p.amount, 'currency', p.currency,
                 'commission', p.commission, 'method', p.method, 'provider', p.provider, 'mode', p.mode,
                 'status', p.status, 'failure_reason', p.failure_reason,
                 'created_at', p.created_at, 'confirmed_at', p.confirmed_at) r
          from ad_payments p
          join ad_orders o on o.id = p.order_id
          left join users u on u.id = p.user_id
         where p.mode = p_mode
           and (p_status is null or p.status = p_status)
           and (p_from is null or p.created_at >= p_from)
           and (p_to is null or p.created_at < p_to + 1)
           and (q is null or p.id::text ilike q || '%' or o.id::text ilike q || '%'
                or coalesce(o.order_no::text, '') = q or coalesce(o.title, '') ilike '%' || q || '%'
                or coalesce(u.full_name, '') ilike '%' || q || '%')
         order by p.created_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;

create or replace function public.finance_audit_recent(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  perform public._require_finance_admin();
  return coalesce((select jsonb_agg(jsonb_build_object('action', a.action, 'entity', a.entity, 'entity_id', a.entity_id,
                                                       'details', a.details, 'created_at', a.created_at) order by a.id desc)
                     from (select * from finance_audit order by id desc limit least(greatest(coalesce(p_limit, 50), 1), 200)) a), '[]'::jsonb);
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'finance_get_settings()', 'finance_set_settings(text,text,numeric,text[])',
    'finance_list_payout_accounts()',
    'finance_add_payout_account(text,text,text,text,text,text,text,text)',
    'finance_set_primary_payout_account(uuid)', 'finance_disable_payout_account(uuid)',
    'finance_request_payout(numeric)', 'finance_summary(text)',
    'finance_payments(text,text,date,date,text,integer,integer)', 'finance_audit_recent(integer)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public._payout_account_json(public.payout_accounts) from public, anon, authenticated;

-- 7) Admin review: a card-paid order (server-confirmed) needs no receipt ----
create or replace function public.admin_review_ad_order(p_order uuid, p_approve boolean, p_note text default null)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old public.ad_orders;
  v_new public.ad_orders;
  v_start timestamptz;
  v_ad public.ads;
begin
  perform public._require_admin();
  select * into v_old from ad_orders where id = p_order for update;
  if v_old.id is null then raise exception 'not_found'; end if;

  if not p_approve then
    if nullif(btrim(p_note), '') is null then raise exception 'reason_required' using errcode = '22023'; end if;
    if v_old.status not in ('pending_payment','awaiting_approval','approved') then
      raise exception 'invalid_order_state' using errcode = '22023';
    end if;
    update ad_orders set status = 'rejected', admin_note = btrim(p_note), reviewed_at = now(), updated_at = now()
     where id = p_order returning * into v_new;
    perform public._admin_log('ad_order.reject', 'ad_order', p_order::text, to_jsonb(v_old), to_jsonb(v_new), p_note);
    return v_new;
  end if;

  -- Approve = "the money is on our account": a receipt the admin checked,
  -- or (0037) a card payment the provider confirmed (payment_status paid).
  if v_old.creative is null then raise exception 'not_template_order' using errcode = '22023'; end if;
  if v_old.status <> 'awaiting_approval' or (v_old.receipt_path is null and v_old.payment_status <> 'paid') then
    raise exception 'invalid_order_state' using errcode = '22023';
  end if;

  v_start := greatest(coalesce((v_old.starts_on::timestamp at time zone 'Asia/Baku'), now()), now());

  insert into ads (order_id, advertiser_id, title, image_url, creative, destination_type, destination_url,
                   target_countries, route_from, route_to, starts_at, ends_at, is_active)
  values (v_old.id, v_old.advertiser_id, v_old.title, coalesce(v_old.creative->>'image_url', v_old.image_url),
          v_old.creative, coalesce(v_old.destination_type, 'profile'), v_old.destination_url,
          coalesce(v_old.target_countries, '{}'), v_old.route_from, v_old.route_to,
          v_start, v_start + make_interval(days => v_old.days), true)
  returning * into v_ad;

  update ad_orders set
    payment_status = 'paid',
    paid_at = coalesce(paid_at, now()),
    status = 'active',
    admin_note = coalesce(nullif(btrim(p_note), ''), admin_note),
    reviewed_at = now(),
    ad_starts_at = v_ad.starts_at,
    ad_ends_at = v_ad.ends_at,
    updated_at = now()
  where id = p_order returning * into v_new;
  perform public._admin_log('ad_order.approve', 'ad_order', p_order::text, to_jsonb(v_old), to_jsonb(v_new), p_note);
  return v_new;
end;
$$;

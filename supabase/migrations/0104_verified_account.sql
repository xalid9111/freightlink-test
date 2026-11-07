-- =====================================================================
-- 0104 — "Təsdiqlənmiş hesab" (owner, 07.11.2026).
--
-- Two separate ways to the blue badge, never mixed:
--   1) Paid subscription: 20 AZN a month (verified_plans; the server sets
--      the price). The user orders it on the Profil card ("Ayda 20 AZN ·
--      Aktiv et"); the existing card checkout makes the payment
--      (ad_payments.verified_order_id); ONLY a verified LIVE payment
--      activates it (verified_subscriptions.paid_until += 1 month). A TEST
--      payment never activates it, and the payment is refused while the
--      shop is not live ('payments_not_live') — no made-up activation.
--   2) The Baş admin's own grant (users.is_verified, as before): only the
--      Baş admin (an admin who is the finance owner or the Founder — the
--      same rule as the app's "Baş admin idarəetməsi") changes it, with
--      admin_set_account_verified (logged). A trigger keeps the rule for
--      EVERY signed-in path: the API, admin_update_user, any RPC — an
--      ordinary admin or the user himself gets 'chief_admin_only'. The SQL
--      editor / server code without a signed-in user stays trusted.
-- account_verification(user) tells the app both, apart: granted (Baş
-- admin), paid (subscription; its end date only to the user himself and
-- admins) and verified (either).
--
-- Safe: forward-only, re-runnable; new tables, one nullable column on
-- ad_payments, functions, one trigger. Existing users.is_verified values
-- are kept (they count as the Baş admin's grant); no row changes.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.is_founder(uuid)') is null or to_regprocedure('public.is_finance_admin()') is null
     or to_regclass('public.place_promo_orders') is null then
    raise exception '0104: run 0037, 0045 and 0093 first — nothing changed';
  end if;
end $$;

-- 1) Who is the Baş admin --------------------------------------------------------
create or replace function public.is_chief_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select auth.uid() is not null
     and exists (select 1 from users u where u.id = auth.uid() and u.role = 'admin')
     and (public.is_founder(auth.uid()) or public.is_finance_admin());
$$;
revoke all on function public.is_chief_admin() from public, anon;
grant execute on function public.is_chief_admin() to authenticated;

-- 2) Only the Baş admin changes the grant (every signed-in path) ------------------
create or replace function public.users_verified_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.is_verified is distinct from old.is_verified
     and auth.uid() is not null
     and not public.is_chief_admin() then
    raise exception 'chief_admin_only' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function public.users_verified_guard() from public, anon, authenticated;
drop trigger if exists zz_users_verified_guard on public.users;
create trigger zz_users_verified_guard before update of is_verified on public.users
  for each row execute function public.users_verified_guard();

create or replace function public.admin_set_account_verified(p_user uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.is_chief_admin() then raise exception 'chief_admin_only' using errcode = '42501'; end if;
  if p_on is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select is_verified into v_old from users where id = p_user;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update users set is_verified = p_on, updated_at = now() where id = p_user;
  perform public._admin_log('user.verified_grant', 'user', p_user::text,
    jsonb_build_object('is_verified', v_old), jsonb_build_object('is_verified', p_on));
end $$;
revoke all on function public.admin_set_account_verified(uuid, boolean) from public, anon;
grant execute on function public.admin_set_account_verified(uuid, boolean) to authenticated;

-- 3) The paid subscription -----------------------------------------------------
create table if not exists public.verified_plans (
  months integer primary key check (months between 1 and 24),
  price numeric(12,2) not null check (price > 0),
  currency text not null default 'AZN' check (char_length(currency) between 3 and 4),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.verified_plans (months, price, currency) values (1, 20, 'AZN') on conflict (months) do nothing;
alter table public.verified_plans enable row level security;
revoke all on public.verified_plans from anon, authenticated;
grant select on public.verified_plans to authenticated;
drop policy if exists "verified_plans_read" on public.verified_plans;
create policy "verified_plans_read" on public.verified_plans for select to authenticated using (true);

-- Written only by a verified LIVE payment (definer functions below).
create table if not exists public.verified_subscriptions (
  user_id uuid primary key references public.users(id) on delete cascade,
  paid_until timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table public.verified_subscriptions enable row level security;
revoke all on public.verified_subscriptions from anon, authenticated;
grant select on public.verified_subscriptions to authenticated;
drop policy if exists "verified_subscriptions_read" on public.verified_subscriptions;
create policy "verified_subscriptions_read" on public.verified_subscriptions for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create table if not exists public.verified_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete restrict,
  months integer not null check (months between 1 and 24),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists verified_orders_user_idx on public.verified_orders (user_id, created_at desc);
alter table public.verified_orders enable row level security;
revoke all on public.verified_orders from anon, authenticated;
grant select on public.verified_orders to authenticated;
drop policy if exists "verified_orders_read" on public.verified_orders;
create policy "verified_orders_read" on public.verified_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()) or (select public.is_finance_admin()));

-- My subscription order (the server sets the price; a double tap = one order).
create or replace function public.verified_order_create(p_months integer default 1)
returns public.verified_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_plan public.verified_plans;
  v_ord public.verified_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  select * into v_plan from verified_plans where months = coalesce(p_months, 1) and is_active;
  if v_plan.months is null then raise exception 'invalid_plan' using errcode = '22023'; end if;
  select * into v_ord from verified_orders
   where user_id = v_uid and months = v_plan.months and status = 'pending_payment'
     and amount = v_plan.price and currency = upper(v_plan.currency)
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;
  insert into verified_orders (user_id, months, amount, currency)
  values (v_uid, v_plan.months, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.verified_order_create(integer) from public, anon;
grant execute on function public.verified_order_create(integer) to authenticated;

-- 4) Card payments for these orders (the existing checkout, LIVE only) ------------
alter table public.ad_payments add column if not exists verified_order_id uuid
  references public.verified_orders(id) on delete restrict;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target8') then
    alter table public.ad_payments add constraint ad_payments_one_target8
      check (num_nonnulls(order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                          tir_park_booking_id, place_promo_order_id, verified_order_id) = 1);
  end if;
  if exists (select 1 from pg_constraint where conname = 'ad_payments_one_target7') then
    alter table public.ad_payments drop constraint ad_payments_one_target7;
  end if;
end $$;
create unique index if not exists ad_payments_one_open_per_verified on public.ad_payments (verified_order_id)
  where verified_order_id is not null and status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_verified on public.ad_payments (verified_order_id, mode)
  where verified_order_id is not null and status = 'succeeded';

create or replace function public.verified_payment_create(p_order uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_ord public.verified_orders;
  v_pay public.ad_payments;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not ((payment_checkout_available() ->> 'available')::boolean) then
    raise exception 'payments_disabled' using errcode = '42501';
  end if;
  -- Only a real (LIVE) checkout: a test payment would activate nothing.
  if s.mode is distinct from 'live' then raise exception 'payments_not_live' using errcode = '42501'; end if;
  if p_method is null or not (p_method = any (s.methods)) then raise exception 'invalid_method' using errcode = '22023'; end if;
  if p_key is null or length(p_key) not between 8 and 80 or p_key !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where user_id = v_uid and idempotency_key = p_key;
  if v_pay.id is not null then return v_pay; end if;

  select * into v_ord from verified_orders where id = p_order for update;
  if v_ord.id is null or v_ord.user_id is distinct from v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_ord.status <> 'pending_payment' or coalesce(v_ord.amount, 0) <= 0 then
    raise exception 'order_not_payable' using errcode = '22023';
  end if;
  if exists (select 1 from ad_payments where verified_order_id = p_order and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where verified_order_id = p_order and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  insert into ad_payments (order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                           tir_park_booking_id, place_promo_order_id, verified_order_id,
                           user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (null, null, null, null, null, null, null, p_order, v_uid, v_ord.amount, upper(v_ord.currency), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode,
          round(v_ord.amount * s.commission_pct / 100, 2), p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('verified_order_id', p_order, 'months', v_ord.months,
                       'amount', v_pay.amount, 'currency', v_pay.currency, 'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.verified_payment_create(uuid, text, text) from public, anon;
grant execute on function public.verified_payment_create(uuid, text, text) to authenticated;

-- A verified LIVE payment: +months to the subscription.
create or replace function public._verified_apply(p_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_ord public.verified_orders;
begin
  update verified_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  insert into verified_subscriptions (user_id, paid_until, updated_at)
  values (v_ord.user_id, now() + make_interval(months => v_ord.months), now())
  on conflict (user_id) do update
    set paid_until = greatest(verified_subscriptions.paid_until, now()) + make_interval(months => v_ord.months),
        updated_at = now();
end $$;
revoke all on function public._verified_apply(uuid) from public, anon, authenticated;

-- 5) 0093's provider event with ONE extra step (the subscription, LIVE only).
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
  -- 0054: a VIP order is applied on a LIVE or a TEST success.
  if v_new = 'succeeded' and v_pay.market_vip_order_id is not null then
    perform public._market_vip_apply(v_pay.market_vip_order_id);
  end if;
  -- 0062: the same for a load VIP order.
  if v_new = 'succeeded' and v_pay.cargo_vip_order_id is not null then
    perform public._cargo_vip_apply(v_pay.cargo_vip_order_id);
  end if;
  -- 0066: İrəli çək / Premium orders, the same way.
  if v_new = 'succeeded' and v_pay.market_promo_order_id is not null then
    perform public._market_promo_apply(v_pay.market_promo_order_id);
  end if;
  -- 0067: the same for a load.
  if v_new = 'succeeded' and v_pay.cargo_promo_order_id is not null then
    perform public._cargo_promo_apply(v_pay.cargo_promo_order_id);
  end if;
  -- 0079: a TIR park booking — confirmed with its code, or freed.
  if v_pay.tir_park_booking_id is not null then
    if v_new = 'succeeded' then
      perform public._tir_park_booking_paid(v_pay.tir_park_booking_id, v_pay.mode);
    else
      perform public._tir_park_booking_failed(v_pay.tir_park_booking_id);
    end if;
  end if;
  -- 0093: a service / TIR park promotion, the same way as a load's.
  if v_new = 'succeeded' and v_pay.place_promo_order_id is not null then
    perform public._place_promo_apply(v_pay.place_promo_order_id);
  end if;
  -- 0104: "Təsdiqlənmiş hesab" — only a LIVE (real) payment activates it;
  -- a test payment never does (no made-up activation).
  if v_new = 'succeeded' and v_pay.verified_order_id is not null and v_pay.mode = 'live' then
    perform public._verified_apply(v_pay.verified_order_id);
  end if;
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id, 'vip_order_id', v_pay.market_vip_order_id,
                       'cargo_vip_order_id', v_pay.cargo_vip_order_id, 'market_promo_order_id', v_pay.market_promo_order_id,
                       'cargo_promo_order_id', v_pay.cargo_promo_order_id, 'tir_park_booking_id', v_pay.tir_park_booking_id,
                       'place_promo_order_id', v_pay.place_promo_order_id, 'verified_order_id', v_pay.verified_order_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 6) What the app shows: the two ways apart, and either.
create or replace function public.account_verification(p_user uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := coalesce(p_user, auth.uid());
  v_granted boolean;
  v_until timestamptz;
  v_own boolean;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  v_own := v_uid = auth.uid() or public.is_admin();
  select is_verified into v_granted from users where id = v_uid;
  if not found then return null; end if;
  select paid_until into v_until from verified_subscriptions where user_id = v_uid;
  return jsonb_build_object(
    'granted', coalesce(v_granted, false),
    'paid', v_until is not null and v_until > now(),
    'paid_until', case when v_own and v_until > now() then v_until end,
    'verified', coalesce(v_granted, false) or (v_until is not null and v_until > now()));
end $$;
revoke all on function public.account_verification(uuid) from public, anon;
grant execute on function public.account_verification(uuid) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.verified_payment_create(uuid, text, text)') is null
     or to_regprocedure('public._verified_apply(uuid)') is null
     or to_regprocedure('public.admin_set_account_verified(uuid, boolean)') is null then
    raise exception '0104: functions missing — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

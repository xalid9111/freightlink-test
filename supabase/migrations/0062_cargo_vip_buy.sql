-- =====================================================================
-- 0062 — Every user can make his own load VIP (owner, 24.10.2026)
--
-- The same way as TIR Bazarı (0044 / 0054):
--   * prices per number of days (cargo_vip_plans: 7 / 14 / 30 days =
--     5 / 9 / 15 AZN to start; only an admin changes them, logged);
--   * "VIP et" makes an order for MY open load (cargo_vip_order_create);
--   * the card checkout (Edge Function payments-checkout, ad_payments)
--     takes the amount from the order — the app never sends a price;
--   * only a verified successful payment (LIVE, or TEST while the shop
--     runs in test mode — owner's choice) makes the load VIP for the
--     plan's days (added to a VIP that is still running). A failed
--     payment changes nothing. Test payments stay marked "test" and never
--     count as income.
-- The admin's own "VIP et" (0059) stays as it is.
--
-- Safe: forward-only, re-runnable. New tables, one new nullable column on
-- ad_payments, functions; the payment-target check is widened to three
-- kinds (every existing row already has exactly one). No row is changed
-- or deleted.
-- =====================================================================

-- 1) Prices -------------------------------------------------------------------
create table if not exists public.cargo_vip_plans (
  days integer primary key check (days between 1 and 365),
  price numeric(12,2) not null check (price > 0),
  currency text not null default 'AZN' check (char_length(currency) between 3 and 4),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.cargo_vip_plans (days, price) values (7, 5), (14, 9), (30, 15)
on conflict (days) do nothing;
alter table public.cargo_vip_plans enable row level security;
revoke all on public.cargo_vip_plans from anon, authenticated;
grant select on public.cargo_vip_plans to authenticated;
drop policy if exists "cargo_vip_plans_read" on public.cargo_vip_plans;
create policy "cargo_vip_plans_read" on public.cargo_vip_plans for select to authenticated using (true);

create or replace function public.admin_cargo_set_vip_plan(p_days integer, p_price numeric, p_active boolean default true)
returns public.cargo_vip_plans language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.cargo_vip_plans; v_new public.cargo_vip_plans;
begin
  perform public._require_admin();
  if p_days is null or p_days not between 1 and 365 then raise exception 'invalid_days' using errcode = '22023'; end if;
  if p_price is null or p_price <= 0 or p_price > 100000 then raise exception 'invalid_price' using errcode = '22023'; end if;
  select * into v_old from cargo_vip_plans where days = p_days;
  insert into cargo_vip_plans (days, price, is_active, updated_at)
  values (p_days, round(p_price, 2), coalesce(p_active, true), now())
  on conflict (days) do update set price = excluded.price, is_active = excluded.is_active, updated_at = now()
  returning * into v_new;
  perform public._admin_log('cargo.vip_plan', 'cargo_vip_plan', p_days::text, to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end $$;
revoke all on function public.admin_cargo_set_vip_plan(integer, numeric, boolean) from public, anon;
grant execute on function public.admin_cargo_set_vip_plan(integer, numeric, boolean) to authenticated;

-- 2) Orders -------------------------------------------------------------------
create table if not exists public.cargo_vip_orders (
  id uuid primary key default gen_random_uuid(),
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete restrict,
  days integer not null check (days between 1 and 365),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists cargo_vip_orders_cargo_idx on public.cargo_vip_orders (cargo_id, created_at desc);
create index if not exists cargo_vip_orders_user_idx on public.cargo_vip_orders (user_id, created_at desc);
alter table public.cargo_vip_orders enable row level security;
revoke all on public.cargo_vip_orders from anon, authenticated;
grant select on public.cargo_vip_orders to authenticated;
drop policy if exists "cargo_vip_orders_read" on public.cargo_vip_orders;
create policy "cargo_vip_orders_read" on public.cargo_vip_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()) or (select public.is_finance_admin()));

-- "VIP et": an order for MY open load with the plan's price. An unpaid
-- order for the same load and plan is re-used (double tap = one order).
create or replace function public.cargo_vip_order_create(p_cargo uuid, p_days integer)
returns public.cargo_vip_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_c public.cargo;
  v_plan public.cargo_vip_plans;
  v_ord public.cargo_vip_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_c from cargo where id = p_cargo;
  if v_c.id is null or v_c.owner_id is distinct from v_uid then raise exception 'cargo_not_found' using errcode = 'P0002'; end if;
  if v_c.status <> 'new' or v_c.is_hidden then raise exception 'cargo_not_open' using errcode = '22023'; end if;
  select * into v_plan from cargo_vip_plans where days = p_days and is_active;
  if v_plan.days is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from cargo_vip_orders
   where cargo_id = p_cargo and user_id = v_uid and days = p_days and status = 'pending_payment'
     and amount = v_plan.price and currency = v_plan.currency
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into cargo_vip_orders (cargo_id, user_id, days, amount, currency)
  values (p_cargo, v_uid, v_plan.days, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.cargo_vip_order_create(uuid, integer) from public, anon;
grant execute on function public.cargo_vip_order_create(uuid, integer) to authenticated;

-- 3) Card payments for load VIP orders (same checkout as 0037 / 0044) ------
alter table public.ad_payments add column if not exists cargo_vip_order_id uuid
  references public.cargo_vip_orders(id) on delete restrict;
-- A payment belongs to exactly ONE thing: an ad order, a TIR Bazarı VIP
-- order or a load VIP order (0044 allowed the first two).
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target3') then
    alter table public.ad_payments add constraint ad_payments_one_target3
      check (num_nonnulls(order_id, market_vip_order_id, cargo_vip_order_id) = 1);
  end if;
  if exists (select 1 from pg_constraint where conname = 'ad_payments_one_target') then
    alter table public.ad_payments drop constraint ad_payments_one_target;
  end if;
end $$;
create unique index if not exists ad_payments_one_open_per_cargo_vip on public.ad_payments (cargo_vip_order_id)
  where cargo_vip_order_id is not null and status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_cargo_vip on public.ad_payments (cargo_vip_order_id, mode)
  where cargo_vip_order_id is not null and status = 'succeeded';

-- Start (or re-use) a checkout for my load VIP order. Amount = the order's
-- price. Same rules as market_vip_payment_create (0044).
create or replace function public.cargo_vip_payment_create(p_vip_order uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_ord public.cargo_vip_orders;
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

  select * into v_pay from ad_payments where user_id = v_uid and idempotency_key = p_key;
  if v_pay.id is not null then return v_pay; end if;

  select * into v_ord from cargo_vip_orders where id = p_vip_order for update;
  if v_ord.id is null or v_ord.user_id is distinct from v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_ord.status <> 'pending_payment' or coalesce(v_ord.amount, 0) <= 0 then
    raise exception 'order_not_payable' using errcode = '22023';
  end if;
  if exists (select 1 from ad_payments where cargo_vip_order_id = p_vip_order and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where cargo_vip_order_id = p_vip_order and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  insert into ad_payments (order_id, market_vip_order_id, cargo_vip_order_id, user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (null, null, p_vip_order, v_uid, v_ord.amount, upper(v_ord.currency), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode,
          round(v_ord.amount * s.commission_pct / 100, 2), p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('cargo_vip_order_id', p_vip_order, 'amount', v_pay.amount, 'currency', v_pay.currency, 'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.cargo_vip_payment_create(uuid, text, text) from public, anon;
grant execute on function public.cargo_vip_payment_create(uuid, text, text) to authenticated;

-- A verified successful payment: the order is paid and the load is VIP for
-- the plan's days (added to a VIP that is still running; an admin's VIP
-- without an end date stays without one). Called only from
-- finance_apply_provider_event, which runs as service_role — so 0006's
-- VIP guard lets this one change through.
create or replace function public._cargo_vip_apply(p_vip_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_ord public.cargo_vip_orders;
begin
  update cargo_vip_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_vip_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  update cargo
     set is_featured = true,
         featured_until = case when is_featured and featured_until is null then null
                               else greatest(coalesce(case when is_featured and featured_until > now() then featured_until end, now()), now())
                                    + make_interval(days => v_ord.days) end
   where id = v_ord.cargo_id;
end $$;
revoke all on function public._cargo_vip_apply(uuid) from public, anon, authenticated;

-- 4) 0054's function with ONE extra step: a load VIP payment marks its order
-- paid and makes the load VIP (LIVE, or TEST success like TIR Bazarı).
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
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id, 'vip_order_id', v_pay.market_vip_order_id,
                       'cargo_vip_order_id', v_pay.cargo_vip_order_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 5) The finance owner's payment list (0044) also names load VIP payments.
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
                 'id', p.id, 'order_id', coalesce(p.order_id, p.market_vip_order_id, p.cargo_vip_order_id), 'order_no', o.order_no,
                 'order_title', case when p.market_vip_order_id is not null
                                     then 'VIP ' || v.days || ' · ' || coalesce(nullif(btrim(coalesce(ml.brand, '') || ' ' || coalesce(ml.model, '')), ''), '#' || ml.listing_no::text)
                                     when p.cargo_vip_order_id is not null
                                     then 'VIP ' || cv.days || ' · ' || coalesce(c.pickup_city, '') || ' → ' || coalesce(c.destination_city, '')
                                     else o.title end,
                 'order_status', coalesce(o.status, v.status, cv.status), 'order_payment_status', coalesce(o.payment_status, v.status, cv.status),
                 'customer', coalesce(u.full_name, u.email), 'amount', p.amount, 'currency', p.currency,
                 'commission', p.commission, 'method', p.method, 'provider', p.provider, 'mode', p.mode,
                 'status', p.status, 'failure_reason', p.failure_reason,
                 'created_at', p.created_at, 'confirmed_at', p.confirmed_at) r
          from ad_payments p
          left join ad_orders o on o.id = p.order_id
          left join market_vip_orders v on v.id = p.market_vip_order_id
          left join market_listings ml on ml.id = v.listing_id
          left join cargo_vip_orders cv on cv.id = p.cargo_vip_order_id
          left join cargo c on c.id = cv.cargo_id
          left join users u on u.id = p.user_id
         where p.mode = p_mode
           and (p_status is null or p.status = p_status)
           and (p_from is null or p.created_at >= p_from)
           and (p_to is null or p.created_at < p_to + 1)
           and (q is null or p.id::text ilike q || '%' or coalesce(o.id, v.id, cv.id)::text ilike q || '%'
                or coalesce(o.order_no::text, '') = q or coalesce(o.title, '') ilike '%' || q || '%'
                or coalesce(u.full_name, '') ilike '%' || q || '%')
         order by p.created_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.finance_payments(text, text, date, date, text, integer, integer) from public, anon;
grant execute on function public.finance_payments(text, text, date, date, text, integer, integer) to authenticated;

notify pgrst, 'reload schema';

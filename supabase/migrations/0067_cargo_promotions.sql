-- =====================================================================
-- 0067 — Loads (Yüklər): "İrəli çək", VIP with a daily lift, "Premium"
-- (owner, 25.10.2026 — the same system as TIR Bazarı 0066)
--
-- * İrəli çək: packs of 1 / 3 / 5 / 10 lifts. The first lift is at once,
--   then one every 24 hours until the pack is used — worked out from the
--   time (no scheduled job): cargo_lifted_at() here, the same rule in the
--   app (CargoModel.liftedAt) which orders the Loads page.
-- * VIP (0062, orders unchanged): an active VIP also lifts once a day
--   (cargo.featured_since: when the load last became VIP).
-- * Premium: 1 / 5 / 15 / 30 days at the top of the Loads page, a daily
--   lift and VIP for the same days.
-- * Prices in cargo_promo_plans (İrəli çək, Premium; only an admin
--   changes them, logged). VIP keeps cargo_vip_plans; the owner's VIP
--   packs 1 / 5 / 15 / 30 days = 5 / 15 / 25 / 40 AZN are added, and the
--   old 7 / 14 day packs are switched off — only while they still have
--   their first prices (an admin's change is never overwritten).
-- * Paid like load VIP: an order (cargo_promo_order_create), the card
--   checkout (Edge Function payments-checkout, ad_payments) with the
--   order's own price, and only a verified successful payment (LIVE, or
--   TEST while the shop runs in test mode, as 0062) applies it.
--
-- Safe: forward-only, re-runnable. New tables, new nullable columns, one
-- new nullable column on ad_payments, functions; no row is deleted; no
-- user data is rewritten. One transaction with a final check.
-- Needs 0066 (ad_payments.market_promo_order_id).
-- =====================================================================

begin;

-- 1) New columns on the load (only trusted server code sets them) -------
alter table public.cargo add column if not exists featured_since timestamptz;
alter table public.cargo add column if not exists premium_until timestamptz;
alter table public.cargo add column if not exists premium_since timestamptz;
alter table public.cargo add column if not exists bump_start timestamptz;
alter table public.cargo add column if not exists bump_total integer;

do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.cargo'::regclass
                  and conname = 'cargo_bump_total_check') then
    alter table public.cargo add constraint cargo_bump_total_check
      check (bump_total is null or bump_total between 0 and 1000);
  end if;
end $$;

-- When a load becomes VIP (or its VIP is extended) it lifts. Nobody sets
-- this column by hand: it follows is_featured / featured_until, which
-- 0006 / 0059 already guard.
create or replace function public.cargo_featured_since()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' then
    if new.is_featured and (not old.is_featured or new.featured_until is distinct from old.featured_until) then
      new.featured_since := clock_timestamp();
    elsif not new.is_featured then
      new.featured_since := null;
    else
      new.featured_since := old.featured_since;
    end if;
  else
    new.featured_since := case when new.is_featured then clock_timestamp() end;
  end if;
  return new;
end $$;
drop trigger if exists zz_cargo_featured_since on public.cargo;
create trigger zz_cargo_featured_since
  before insert or update on public.cargo
  for each row execute function public.cargo_featured_since();

-- An owner can never set Premium or lifts himself (only an admin, the
-- payment service or the trusted apply function below).
create or replace function public.cargo_promo_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if coalesce(auth.role(), '') = 'service_role' or public.is_admin()
     or current_setting('app.cargo_trusted', true) = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.premium_until := null;
    new.premium_since := null;
    new.bump_start := null;
    new.bump_total := null;
  else
    new.premium_until := old.premium_until;
    new.premium_since := old.premium_since;
    new.bump_start := old.bump_start;
    new.bump_total := old.bump_total;
  end if;
  return new;
end $$;
drop trigger if exists zz_cargo_promo_guard on public.cargo;
create trigger zz_cargo_promo_guard
  before insert or update on public.cargo
  for each row execute function public.cargo_promo_guard();

create or replace function public.cargo_vip_active(p_on boolean, p_until timestamptz)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select coalesce(p_on, false) and (p_until is null or p_until > now());
$$;

create or replace function public.cargo_premium_active(p_until timestamptz)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select p_until is not null and p_until > now();
$$;

-- The time a load last came to the front: posted, or its latest lift
-- (İrəli çək pack: at once, then every 24 h until used; VIP / Premium:
-- once a day while active; a VIP from before 0067 counts from the time
-- the load was posted). The app uses the same rule.
create or replace function public.cargo_lifted_at(c public.cargo)
returns timestamptz language sql stable set search_path = public, pg_temp as $$
  select greatest(
    c.created_at,
    case when coalesce(c.bump_total, 0) > 0 and c.bump_start is not null and c.bump_start <= now()
         then c.bump_start + make_interval(days => least(c.bump_total - 1,
                floor(extract(epoch from now() - c.bump_start) / 86400)::int)) end,
    case when public.cargo_vip_active(c.is_featured, c.featured_until) and coalesce(c.featured_since, c.created_at) <= now()
         then coalesce(c.featured_since, c.created_at)
              + make_interval(days => floor(extract(epoch from now() - coalesce(c.featured_since, c.created_at)) / 86400)::int) end,
    case when public.cargo_premium_active(c.premium_until) and c.premium_since is not null and c.premium_since <= now()
         then c.premium_since + make_interval(days => floor(extract(epoch from now() - c.premium_since) / 86400)::int) end);
$$;
revoke all on function public.cargo_lifted_at(public.cargo) from public, anon;
grant execute on function public.cargo_lifted_at(public.cargo) to authenticated;

-- 2) Prices -----------------------------------------------------------------
create table if not exists public.cargo_promo_plans (
  kind text not null check (kind in ('bump', 'premium')),
  qty integer not null check (qty between 1 and 365),
  price numeric(12,2) not null check (price > 0),
  currency text not null default 'AZN' check (char_length(currency) between 3 and 4),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (kind, qty)
);
insert into public.cargo_promo_plans (kind, qty, price) values
  ('bump', 1, 3), ('bump', 3, 6), ('bump', 5, 9), ('bump', 10, 15),
  ('premium', 1, 7), ('premium', 5, 20), ('premium', 15, 45), ('premium', 30, 60)
on conflict (kind, qty) do nothing;
alter table public.cargo_promo_plans enable row level security;
revoke all on public.cargo_promo_plans from anon, authenticated;
grant select on public.cargo_promo_plans to authenticated;
drop policy if exists "cargo_promo_plans_read" on public.cargo_promo_plans;
create policy "cargo_promo_plans_read" on public.cargo_promo_plans for select to authenticated using (true);

-- VIP packs as agreed; the first 0062 prices only (never an admin's).
insert into public.cargo_vip_plans (days, price) values (1, 5), (5, 15), (15, 25)
on conflict (days) do nothing;
update public.cargo_vip_plans set price = 40, updated_at = now() where days = 30 and price = 15;
update public.cargo_vip_plans set is_active = false, updated_at = now()
 where is_active and ((days = 7 and price = 5) or (days = 14 and price = 9));

create or replace function public.admin_cargo_set_promo_plan(p_kind text, p_qty integer, p_price numeric, p_active boolean default true)
returns public.cargo_promo_plans language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.cargo_promo_plans; v_new public.cargo_promo_plans;
begin
  perform public._require_admin();
  if p_kind is null or p_kind not in ('bump', 'premium') then raise exception 'invalid_kind' using errcode = '22023'; end if;
  if p_qty is null or p_qty not between 1 and 365 then raise exception 'invalid_qty' using errcode = '22023'; end if;
  if p_price is null or p_price <= 0 or p_price > 100000 then raise exception 'invalid_price' using errcode = '22023'; end if;
  select * into v_old from cargo_promo_plans where kind = p_kind and qty = p_qty;
  insert into cargo_promo_plans (kind, qty, price, is_active, updated_at)
  values (p_kind, p_qty, round(p_price, 2), coalesce(p_active, true), now())
  on conflict (kind, qty) do update set price = excluded.price, is_active = excluded.is_active, updated_at = now()
  returning * into v_new;
  perform public._admin_log('cargo.promo_plan', 'cargo_promo_plan', p_kind || ':' || p_qty, to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end $$;
revoke all on function public.admin_cargo_set_promo_plan(text, integer, numeric, boolean) from public, anon;
grant execute on function public.admin_cargo_set_promo_plan(text, integer, numeric, boolean) to authenticated;

-- 3) Orders -----------------------------------------------------------------
create table if not exists public.cargo_promo_orders (
  id uuid primary key default gen_random_uuid(),
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete restrict,
  kind text not null check (kind in ('bump', 'premium')),
  qty integer not null check (qty between 1 and 365),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists cargo_promo_orders_cargo_idx on public.cargo_promo_orders (cargo_id, created_at desc);
create index if not exists cargo_promo_orders_user_idx on public.cargo_promo_orders (user_id, created_at desc);
alter table public.cargo_promo_orders enable row level security;
revoke all on public.cargo_promo_orders from anon, authenticated;
grant select on public.cargo_promo_orders to authenticated;
drop policy if exists "cargo_promo_orders_read" on public.cargo_promo_orders;
create policy "cargo_promo_orders_read" on public.cargo_promo_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()) or (select public.is_finance_admin()));

-- "İrəli çək" / "Premium" on MY open load with the plan's price. An
-- unpaid order for the same load and plan is re-used (double tap = one).
create or replace function public.cargo_promo_order_create(p_cargo uuid, p_kind text, p_qty integer)
returns public.cargo_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_c public.cargo;
  v_plan public.cargo_promo_plans;
  v_ord public.cargo_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_c from cargo where id = p_cargo;
  if v_c.id is null or v_c.owner_id is distinct from v_uid then raise exception 'cargo_not_found' using errcode = 'P0002'; end if;
  if v_c.status <> 'new' or v_c.is_hidden then raise exception 'cargo_not_open' using errcode = '22023'; end if;
  select * into v_plan from cargo_promo_plans where kind = p_kind and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from cargo_promo_orders
   where cargo_id = p_cargo and user_id = v_uid and kind = p_kind and qty = p_qty and status = 'pending_payment'
     and amount = v_plan.price and currency = upper(v_plan.currency)
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into cargo_promo_orders (cargo_id, user_id, kind, qty, amount, currency)
  values (p_cargo, v_uid, v_plan.kind, v_plan.qty, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.cargo_promo_order_create(uuid, text, integer) from public, anon;
grant execute on function public.cargo_promo_order_create(uuid, text, integer) to authenticated;

-- 4) Card payments for these orders (same checkout as 0062 / 0066) -------
alter table public.ad_payments add column if not exists cargo_promo_order_id uuid
  references public.cargo_promo_orders(id) on delete restrict;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target5') then
    alter table public.ad_payments add constraint ad_payments_one_target5
      check (num_nonnulls(order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id) = 1);
  end if;
  if exists (select 1 from pg_constraint where conname = 'ad_payments_one_target4') then
    alter table public.ad_payments drop constraint ad_payments_one_target4;
  end if;
end $$;
create unique index if not exists ad_payments_one_open_per_cargo_promo on public.ad_payments (cargo_promo_order_id)
  where cargo_promo_order_id is not null and status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_cargo_promo on public.ad_payments (cargo_promo_order_id, mode)
  where cargo_promo_order_id is not null and status = 'succeeded';

create or replace function public.cargo_promo_payment_create(p_promo_order uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_ord public.cargo_promo_orders;
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

  select * into v_ord from cargo_promo_orders where id = p_promo_order for update;
  if v_ord.id is null or v_ord.user_id is distinct from v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_ord.status <> 'pending_payment' or coalesce(v_ord.amount, 0) <= 0 then
    raise exception 'order_not_payable' using errcode = '22023';
  end if;
  if exists (select 1 from ad_payments where cargo_promo_order_id = p_promo_order and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where cargo_promo_order_id = p_promo_order and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  insert into ad_payments (order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                           user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (null, null, null, null, p_promo_order, v_uid, v_ord.amount, upper(v_ord.currency), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode,
          round(v_ord.amount * s.commission_pct / 100, 2), p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('cargo_promo_order_id', p_promo_order, 'kind', v_ord.kind, 'amount', v_pay.amount,
                       'currency', v_pay.currency, 'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.cargo_promo_payment_create(uuid, text, text) from public, anon;
grant execute on function public.cargo_promo_payment_create(uuid, text, text) to authenticated;

-- A verified successful payment applies the order:
--   * İrəli çək: lifted at once; the lifts still left from a running pack
--     are kept and added;
--   * Premium: the days are added to a Premium still running, and the
--     load is VIP at least as long (an admin's VIP without an end stays so).
create or replace function public._cargo_promo_apply(p_promo_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ord public.cargo_promo_orders;
  v_c public.cargo;
  v_left integer;
  v_until timestamptz;
begin
  update cargo_promo_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_promo_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  select * into v_c from cargo where id = v_ord.cargo_id for update;
  if v_c.id is null then return; end if;
  perform set_config('app.cargo_trusted', '1', true);
  if v_ord.kind = 'bump' then
    v_left := case when coalesce(v_c.bump_total, 0) > 0 and v_c.bump_start is not null
                   then greatest(0, v_c.bump_total - (floor(extract(epoch from now() - v_c.bump_start) / 86400)::int + 1))
                   else 0 end;
    update cargo set bump_start = now(), bump_total = least(1000, v_left + v_ord.qty) where id = v_c.id;
  else
    v_until := greatest(coalesce(case when cargo_premium_active(v_c.premium_until) then v_c.premium_until end, now()), now())
               + make_interval(days => v_ord.qty);
    update cargo
       set premium_since = case when cargo_premium_active(premium_until) then premium_since else now() end,
           premium_until = v_until,
           is_featured = true,
           featured_until = case when is_featured and featured_until is null then null
                                 else greatest(coalesce(case when cargo_vip_active(is_featured, featured_until) then featured_until end, now()), v_until) end
     where id = v_c.id;
  end if;
  perform set_config('app.cargo_trusted', '', true);
end $$;
revoke all on function public._cargo_promo_apply(uuid) from public, anon, authenticated;

-- 5) 0066's function with ONE extra step: a load İrəli çək / Premium
-- payment applies its order (LIVE, or TEST success like VIP).
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
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id, 'vip_order_id', v_pay.market_vip_order_id,
                       'cargo_vip_order_id', v_pay.cargo_vip_order_id, 'market_promo_order_id', v_pay.market_promo_order_id,
                       'cargo_promo_order_id', v_pay.cargo_promo_order_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 6) The finance owner's payment list also names these payments.
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
                 'id', p.id,
                 'order_id', coalesce(p.order_id, p.market_vip_order_id, p.cargo_vip_order_id, p.market_promo_order_id, p.cargo_promo_order_id),
                 'order_no', o.order_no,
                 'order_title', case when p.market_vip_order_id is not null
                                     then 'VIP ' || v.days || ' · ' || coalesce(nullif(btrim(coalesce(ml.brand, '') || ' ' || coalesce(ml.model, '')), ''), '#' || ml.listing_no::text)
                                     when p.cargo_vip_order_id is not null
                                     then 'VIP ' || cv.days || ' · ' || coalesce(c.pickup_city, '') || ' → ' || coalesce(c.destination_city, '')
                                     when p.market_promo_order_id is not null
                                     then case mp.kind when 'bump' then 'İrəli çək ' else 'Premium ' end || mp.qty || ' · '
                                          || coalesce(nullif(btrim(coalesce(pl.brand, '') || ' ' || coalesce(pl.model, '')), ''), '#' || pl.listing_no::text)
                                     when p.cargo_promo_order_id is not null
                                     then case cp.kind when 'bump' then 'İrəli çək ' else 'Premium ' end || cp.qty || ' · '
                                          || coalesce(pc.pickup_city, '') || ' → ' || coalesce(pc.destination_city, '')
                                     else o.title end,
                 'order_status', coalesce(o.status, v.status, cv.status, mp.status, cp.status),
                 'order_payment_status', coalesce(o.payment_status, v.status, cv.status, mp.status, cp.status),
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
          left join market_promo_orders mp on mp.id = p.market_promo_order_id
          left join market_listings pl on pl.id = mp.listing_id
          left join cargo_promo_orders cp on cp.id = p.cargo_promo_order_id
          left join cargo pc on pc.id = cp.cargo_id
          left join users u on u.id = p.user_id
         where p.mode = p_mode
           and (p_status is null or p.status = p_status)
           and (p_from is null or p.created_at >= p_from)
           and (p_to is null or p.created_at < p_to + 1)
           and (q is null or p.id::text ilike q || '%' or coalesce(o.id, v.id, cv.id, mp.id, cp.id)::text ilike q || '%'
                or coalesce(o.order_no::text, '') = q or coalesce(o.title, '') ilike '%' || q || '%'
                or coalesce(u.full_name, '') ilike '%' || q || '%')
         order by p.created_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.finance_payments(text, text, date, date, text, integer, integer) from public, anon;
grant execute on function public.finance_payments(text, text, date, date, text, integer, integer) to authenticated;

-- 7) Final check: everything in place.
do $$
begin
  if to_regclass('public.cargo_promo_plans') is null
     or to_regclass('public.cargo_promo_orders') is null
     or to_regprocedure('public.cargo_promo_order_create(uuid, text, integer)') is null
     or to_regprocedure('public.cargo_promo_payment_create(uuid, text, text)') is null
     or to_regprocedure('public.cargo_lifted_at(public.cargo)') is null
     or not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target5')
     or not exists (select 1 from pg_trigger where tgname = 'zz_cargo_promo_guard')
     or not exists (select 1 from pg_trigger where tgname = 'zz_cargo_featured_since') then
    raise exception '0067: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

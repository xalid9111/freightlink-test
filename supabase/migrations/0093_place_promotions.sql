-- =====================================================================
-- 0093 — "Önə çıxar" for Servis and TIRPark (owner, 04.11.2026)
--
-- The same packs, durations, currency and card checkout as TIR Bazarı /
-- Loads (İrəli çək · VIP · Premium, 0066 / 0067), for a service (its
-- owner) and a TIR park (its approved manager). Where the ad shows is the
-- section's own place, never among the loads:
--   * Servis: the services list and map of the area being looked at — a
--     promoted service of that area stands first, with its mark; a tap
--     opens the service page (as before).
--   * TIRPark: the TIRPark map and list of the area — a promoted park
--     stands first, with its mark; a tap opens the park page.
-- The area is the service's / park's own place on the map (owner's
-- choice); a service without a map place cannot be promoted
-- ('no_area', the app explains it).
--
-- * Prices: place_promo_plans (target service | tirpark × kind × qty),
--   started from the CURRENT Loads prices (cargo_promo_plans for İrəli
--   çək / Premium, cargo_vip_plans for VIP, with their on / off); only an
--   admin changes them afterwards (admin_place_set_promo_plan, logged).
--   Nothing of the Loads / TIR Bazarı prices is changed.
-- * Orders: place_promo_orders; paid by the existing card checkout
--   (ad_payments.place_promo_order_id, Edge Function payments-checkout),
--   applied only after a verified successful payment (LIVE, or TEST
--   while the shop runs in test mode — as 0062 / 0066 / 0067).
-- * The state (VIP / Premium until, lifts) is in new nullable columns of
--   service_providers / tir_parks that only trusted server code sets;
--   the app reads it with place_promo_state(target, ids), so the existing
--   service / park queries stay exactly as they are.
-- * Expiry needs no job: everything is worked out from the time.
--
-- Safe: forward-only, re-runnable. New tables, new nullable columns, one
-- new nullable column on ad_payments, functions; no row is deleted; no
-- user data is rewritten. One transaction with a final check.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.cargo_promo_plans') is null or to_regclass('public.tir_parks') is null
     or to_regprocedure('public._tir_park_booking_paid(uuid, text)') is null then
    raise exception '0093: run 0067 and 0079 first — nothing changed';
  end if;
end $$;

-- 1) State columns (only trusted server code sets them) -------------------
alter table public.service_providers add column if not exists promo_vip_until timestamptz;
alter table public.service_providers add column if not exists promo_vip_since timestamptz;
alter table public.service_providers add column if not exists promo_premium_until timestamptz;
alter table public.service_providers add column if not exists promo_premium_since timestamptz;
alter table public.service_providers add column if not exists promo_bump_start timestamptz;
alter table public.service_providers add column if not exists promo_bump_total integer;
alter table public.tir_parks add column if not exists promo_vip_until timestamptz;
alter table public.tir_parks add column if not exists promo_vip_since timestamptz;
alter table public.tir_parks add column if not exists promo_premium_until timestamptz;
alter table public.tir_parks add column if not exists promo_premium_since timestamptz;
alter table public.tir_parks add column if not exists promo_bump_start timestamptz;
alter table public.tir_parks add column if not exists promo_bump_total integer;

-- An owner can never set his own promotion (any insert / update by the
-- app keeps the server's values).
create or replace function public.place_promo_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or public.is_admin() or current_setting('app.place_promo_trusted', true) = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.promo_vip_until := null; new.promo_vip_since := null;
    new.promo_premium_until := null; new.promo_premium_since := null;
    new.promo_bump_start := null; new.promo_bump_total := null;
  else
    new.promo_vip_until := old.promo_vip_until; new.promo_vip_since := old.promo_vip_since;
    new.promo_premium_until := old.promo_premium_until; new.promo_premium_since := old.promo_premium_since;
    new.promo_bump_start := old.promo_bump_start; new.promo_bump_total := old.promo_bump_total;
  end if;
  return new;
end $$;
drop trigger if exists zz_place_promo_guard on public.service_providers;
create trigger zz_place_promo_guard before insert or update on public.service_providers
  for each row execute function public.place_promo_guard();
drop trigger if exists zz_place_promo_guard on public.tir_parks;
create trigger zz_place_promo_guard before insert or update on public.tir_parks
  for each row execute function public.place_promo_guard();

-- The time a promoted place last came to the front (the same rule as
-- cargo_lifted_at, 0067): İrəli çək at once then every 24 h; VIP /
-- Premium once a day while active. Null = no promotion running.
create or replace function public._place_lifted_at(
  p_vip_until timestamptz, p_vip_since timestamptz, p_prem_until timestamptz, p_prem_since timestamptz,
  p_bump_start timestamptz, p_bump_total integer)
returns timestamptz language sql stable set search_path = public, pg_temp as $$
  select greatest(
    case when coalesce(p_bump_total, 0) > 0 and p_bump_start is not null and p_bump_start <= now()
              and now() < p_bump_start + make_interval(days => p_bump_total)
         then p_bump_start + make_interval(days => floor(extract(epoch from now() - p_bump_start) / 86400)::int) end,
    case when p_vip_until > now() and p_vip_since is not null and p_vip_since <= now()
         then p_vip_since + make_interval(days => floor(extract(epoch from now() - p_vip_since) / 86400)::int) end,
    case when p_prem_until > now() and p_prem_since is not null and p_prem_since <= now()
         then p_prem_since + make_interval(days => floor(extract(epoch from now() - p_prem_since) / 86400)::int) end);
$$;
revoke all on function public._place_lifted_at(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, integer) from public, anon;
grant execute on function public._place_lifted_at(timestamptz, timestamptz, timestamptz, timestamptz, timestamptz, integer) to authenticated;

-- The running promotions of the places on the screen (only those with
-- something active; ids the caller may see anyway).
create or replace function public.place_promo_state(p_target text, p_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_target not in ('service', 'tirpark') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if p_ids is null or cardinality(p_ids) = 0 then return '[]'::jsonb; end if;
  if cardinality(p_ids) > 1000 then raise exception 'invalid_argument' using errcode = '22023'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', x.id,
             'vip_until', case when x.vu > now() then x.vu end,
             'premium_until', case when x.pu > now() then x.pu end,
             'bump_left', case when coalesce(x.bt, 0) > 0 and x.bs is not null and now() < x.bs + make_interval(days => x.bt)
                               then x.bt - (floor(extract(epoch from now() - x.bs) / 86400)::int + 1) end,
             'lifted_at', public._place_lifted_at(x.vu, x.vs, x.pu, x.ps, x.bs, x.bt)))
      from (
        select s.id, s.promo_vip_until vu, s.promo_vip_since vs, s.promo_premium_until pu, s.promo_premium_since ps,
               s.promo_bump_start bs, s.promo_bump_total bt
          from service_providers s
         where p_target = 'service' and s.id = any (p_ids) and s.status = 'approved'
        union all
        select p.id, p.promo_vip_until, p.promo_vip_since, p.promo_premium_until, p.promo_premium_since,
               p.promo_bump_start, p.promo_bump_total
          from tir_parks p
         where p_target = 'tirpark' and p.id = any (p_ids) and p.status = 'approved'
      ) x
     where public._place_lifted_at(x.vu, x.vs, x.pu, x.ps, x.bs, x.bt) is not null), '[]'::jsonb);
end $$;
revoke all on function public.place_promo_state(text, uuid[]) from public, anon;
grant execute on function public.place_promo_state(text, uuid[]) to authenticated;

-- 2) Prices: started from the current Loads prices -------------------------
create table if not exists public.place_promo_plans (
  target text not null check (target in ('service', 'tirpark')),
  kind text not null check (kind in ('bump', 'vip', 'premium')),
  qty integer not null check (qty between 1 and 365),
  price numeric(12,2) not null check (price > 0),
  currency text not null default 'AZN' check (char_length(currency) between 3 and 4),
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (target, kind, qty)
);
insert into public.place_promo_plans (target, kind, qty, price, currency, is_active)
select t.target, c.kind, c.qty, c.price, c.currency, c.is_active
  from public.cargo_promo_plans c cross join (values ('service'), ('tirpark')) t(target)
on conflict (target, kind, qty) do nothing;
insert into public.place_promo_plans (target, kind, qty, price, currency, is_active)
select t.target, 'vip', v.days, v.price, v.currency, v.is_active
  from public.cargo_vip_plans v cross join (values ('service'), ('tirpark')) t(target)
on conflict (target, kind, qty) do nothing;
alter table public.place_promo_plans enable row level security;
revoke all on public.place_promo_plans from anon, authenticated;
grant select on public.place_promo_plans to authenticated;
drop policy if exists "place_promo_plans_read" on public.place_promo_plans;
create policy "place_promo_plans_read" on public.place_promo_plans for select to authenticated using (true);

create or replace function public.admin_place_set_promo_plan(p_target text, p_kind text, p_qty integer, p_price numeric, p_active boolean default true)
returns public.place_promo_plans language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.place_promo_plans; v_new public.place_promo_plans;
begin
  perform public._require_admin();
  if p_target is null or p_target not in ('service', 'tirpark') then raise exception 'invalid_target' using errcode = '22023'; end if;
  if p_kind is null or p_kind not in ('bump', 'vip', 'premium') then raise exception 'invalid_kind' using errcode = '22023'; end if;
  if p_qty is null or p_qty not between 1 and 365 then raise exception 'invalid_qty' using errcode = '22023'; end if;
  if p_price is null or p_price <= 0 or p_price > 100000 then raise exception 'invalid_price' using errcode = '22023'; end if;
  select * into v_old from place_promo_plans where target = p_target and kind = p_kind and qty = p_qty;
  insert into place_promo_plans (target, kind, qty, price, is_active, updated_at)
  values (p_target, p_kind, p_qty, round(p_price, 2), coalesce(p_active, true), now())
  on conflict (target, kind, qty) do update set price = excluded.price, is_active = excluded.is_active, updated_at = now()
  returning * into v_new;
  perform public._admin_log('place.promo_plan', 'place_promo_plan', p_target || ':' || p_kind || ':' || p_qty, to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end $$;
revoke all on function public.admin_place_set_promo_plan(text, text, integer, numeric, boolean) from public, anon;
grant execute on function public.admin_place_set_promo_plan(text, text, integer, numeric, boolean) to authenticated;

-- 3) Orders ------------------------------------------------------------------
create table if not exists public.place_promo_orders (
  id uuid primary key default gen_random_uuid(),
  target text not null check (target in ('service', 'tirpark')),
  service_id uuid references public.service_providers(id) on delete cascade,
  park_id uuid references public.tir_parks(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete restrict,
  kind text not null check (kind in ('bump', 'vip', 'premium')),
  qty integer not null check (qty between 1 and 365),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  check ((target = 'service') = (service_id is not null) and (target = 'tirpark') = (park_id is not null))
);
create index if not exists place_promo_orders_user_idx on public.place_promo_orders (user_id, created_at desc);
create index if not exists place_promo_orders_service_idx on public.place_promo_orders (service_id) where service_id is not null;
create index if not exists place_promo_orders_park_idx on public.place_promo_orders (park_id) where park_id is not null;
alter table public.place_promo_orders enable row level security;
revoke all on public.place_promo_orders from anon, authenticated;
grant select on public.place_promo_orders to authenticated;
drop policy if exists "place_promo_orders_read" on public.place_promo_orders;
create policy "place_promo_orders_read" on public.place_promo_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()) or (select public.is_finance_admin()));

-- İrəli çək / VIP / Premium on MY service (its owner) or MY park (its
-- approved manager) with the plan's price. An unpaid order for the same
-- place and plan is re-used (double tap = one).
create or replace function public.place_promo_order_create(p_target text, p_id uuid, p_kind text, p_qty integer)
returns public.place_promo_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_s public.service_providers;
  v_p public.tir_parks;
  v_plan public.place_promo_plans;
  v_ord public.place_promo_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'blocked' using errcode = '42501'; end if;
  if p_target = 'service' then
    select * into v_s from service_providers where id = p_id;
    if v_s.id is null or v_s.owner_id is distinct from v_uid then raise exception 'not_found' using errcode = 'P0002'; end if;
    if v_s.status <> 'approved' or not v_s.is_active then raise exception 'not_open' using errcode = '22023'; end if;
    if v_s.lat is null or v_s.lng is null or (abs(v_s.lat) < 1e-6 and abs(v_s.lng) < 1e-6) then raise exception 'no_area' using errcode = '22023'; end if;
  elsif p_target = 'tirpark' then
    select * into v_p from tir_parks where id = p_id;
    if v_p.id is null or v_p.manager_id is distinct from v_uid or v_p.manager_status is distinct from 'approved' then
      raise exception 'not_found' using errcode = 'P0002';
    end if;
    if v_p.status <> 'approved' then raise exception 'not_open' using errcode = '22023'; end if;
  else
    raise exception 'invalid_target' using errcode = '22023';
  end if;
  select * into v_plan from place_promo_plans where target = p_target and kind = p_kind and qty = p_qty and is_active;
  if v_plan.kind is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from place_promo_orders
   where target = p_target and coalesce(service_id, park_id) = p_id and user_id = v_uid and kind = p_kind and qty = p_qty
     and status = 'pending_payment' and amount = v_plan.price and currency = upper(v_plan.currency)
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into place_promo_orders (target, service_id, park_id, user_id, kind, qty, amount, currency)
  values (p_target, case when p_target = 'service' then p_id end, case when p_target = 'tirpark' then p_id end,
          v_uid, p_kind, p_qty, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.place_promo_order_create(text, uuid, text, integer) from public, anon;
grant execute on function public.place_promo_order_create(text, uuid, text, integer) to authenticated;

-- 4) Card payments for these orders (same checkout as 0062 / 0066 / 0067) --
alter table public.ad_payments add column if not exists place_promo_order_id uuid
  references public.place_promo_orders(id) on delete restrict;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target7') then
    alter table public.ad_payments add constraint ad_payments_one_target7
      check (num_nonnulls(order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                          tir_park_booking_id, place_promo_order_id) = 1);
  end if;
  if exists (select 1 from pg_constraint where conname = 'ad_payments_one_target6') then
    alter table public.ad_payments drop constraint ad_payments_one_target6;
  end if;
end $$;
create unique index if not exists ad_payments_one_open_per_place_promo on public.ad_payments (place_promo_order_id)
  where place_promo_order_id is not null and status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_place_promo on public.ad_payments (place_promo_order_id, mode)
  where place_promo_order_id is not null and status = 'succeeded';

create or replace function public.place_promo_payment_create(p_promo_order uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_ord public.place_promo_orders;
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

  select * into v_ord from place_promo_orders where id = p_promo_order for update;
  if v_ord.id is null or v_ord.user_id is distinct from v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_ord.status <> 'pending_payment' or coalesce(v_ord.amount, 0) <= 0 then
    raise exception 'order_not_payable' using errcode = '22023';
  end if;
  if exists (select 1 from ad_payments where place_promo_order_id = p_promo_order and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where place_promo_order_id = p_promo_order and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  insert into ad_payments (order_id, market_vip_order_id, cargo_vip_order_id, market_promo_order_id, cargo_promo_order_id,
                           tir_park_booking_id, place_promo_order_id,
                           user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (null, null, null, null, null, null, p_promo_order, v_uid, v_ord.amount, upper(v_ord.currency), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode,
          round(v_ord.amount * s.commission_pct / 100, 2), p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('place_promo_order_id', p_promo_order, 'target', v_ord.target, 'kind', v_ord.kind,
                       'amount', v_pay.amount, 'currency', v_pay.currency, 'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.place_promo_payment_create(uuid, text, text) from public, anon;
grant execute on function public.place_promo_payment_create(uuid, text, text) to authenticated;

-- A verified successful payment applies the order (like 0067):
--   * İrəli çək: lifted at once; lifts still left from a running pack are kept;
--   * VIP: the days are added to a VIP still running;
--   * Premium: the days are added to a Premium still running, and the place
--     is VIP at least as long.
create or replace function public._place_promo_apply(p_promo_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ord public.place_promo_orders;
  r record;
  v_left integer;
  v_vip_until timestamptz;
  v_vip_since timestamptz;
  v_prem_until timestamptz;
  v_prem_since timestamptz;
  v_bump_start timestamptz;
  v_bump_total integer;
begin
  update place_promo_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_promo_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  if v_ord.target = 'service' then
    select promo_vip_until vu, promo_vip_since vs, promo_premium_until pu, promo_premium_since ps,
           promo_bump_start bs, promo_bump_total bt into r
      from service_providers where id = v_ord.service_id for update;
  else
    select promo_vip_until vu, promo_vip_since vs, promo_premium_until pu, promo_premium_since ps,
           promo_bump_start bs, promo_bump_total bt into r
      from tir_parks where id = v_ord.park_id for update;
  end if;
  if not found then return; end if;
  v_vip_until := r.vu; v_vip_since := r.vs; v_prem_until := r.pu; v_prem_since := r.ps;
  v_bump_start := r.bs; v_bump_total := r.bt;

  if v_ord.kind = 'bump' then
    v_left := case when coalesce(r.bt, 0) > 0 and r.bs is not null
                   then greatest(0, r.bt - (floor(extract(epoch from now() - r.bs) / 86400)::int + 1)) else 0 end;
    v_bump_start := now();
    v_bump_total := least(1000, v_left + v_ord.qty);
  elsif v_ord.kind = 'vip' then
    v_vip_since := case when r.vu > now() then r.vs else now() end;
    v_vip_until := greatest(coalesce(case when r.vu > now() then r.vu end, now()), now()) + make_interval(days => v_ord.qty);
  else
    v_prem_since := case when r.pu > now() then r.ps else now() end;
    v_prem_until := greatest(coalesce(case when r.pu > now() then r.pu end, now()), now()) + make_interval(days => v_ord.qty);
    v_vip_since := case when r.vu > now() then r.vs else now() end;
    v_vip_until := greatest(coalesce(case when r.vu > now() then r.vu end, now()), v_prem_until);
  end if;

  perform set_config('app.place_promo_trusted', '1', true);
  if v_ord.target = 'service' then
    update service_providers
       set promo_vip_until = v_vip_until, promo_vip_since = v_vip_since,
           promo_premium_until = v_prem_until, promo_premium_since = v_prem_since,
           promo_bump_start = v_bump_start, promo_bump_total = v_bump_total
     where id = v_ord.service_id;
  else
    update tir_parks
       set promo_vip_until = v_vip_until, promo_vip_since = v_vip_since,
           promo_premium_until = v_prem_until, promo_premium_since = v_prem_since,
           promo_bump_start = v_bump_start, promo_bump_total = v_bump_total
     where id = v_ord.park_id;
  end if;
  perform set_config('app.place_promo_trusted', '', true);
end $$;
revoke all on function public._place_promo_apply(uuid) from public, anon, authenticated;

-- 5) 0079's function with ONE extra step: a service / park promotion
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
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id, 'vip_order_id', v_pay.market_vip_order_id,
                       'cargo_vip_order_id', v_pay.cargo_vip_order_id, 'market_promo_order_id', v_pay.market_promo_order_id,
                       'cargo_promo_order_id', v_pay.cargo_promo_order_id, 'tir_park_booking_id', v_pay.tir_park_booking_id,
                       'place_promo_order_id', v_pay.place_promo_order_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 6) The finance owner's payment list also names these payments (0067's
-- list + the place promotions).
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
                 'order_id', coalesce(p.order_id, p.market_vip_order_id, p.cargo_vip_order_id, p.market_promo_order_id, p.cargo_promo_order_id,
                                      p.place_promo_order_id),
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
                                     when p.place_promo_order_id is not null
                                     then case pp.kind when 'bump' then 'İrəli çək ' when 'vip' then 'VIP ' else 'Premium ' end || pp.qty || ' · '
                                          || case pp.target when 'service' then 'Servis: ' || coalesce(ps.name, '') else 'TIRPark: ' || coalesce(pk.name, '') end
                                     else o.title end,
                 'order_status', coalesce(o.status, v.status, cv.status, mp.status, cp.status, pp.status),
                 'order_payment_status', coalesce(o.payment_status, v.status, cv.status, mp.status, cp.status, pp.status),
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
          left join place_promo_orders pp on pp.id = p.place_promo_order_id
          left join service_providers ps on ps.id = pp.service_id
          left join tir_parks pk on pk.id = pp.park_id
          left join users u on u.id = p.user_id
         where p.mode = p_mode
           and (p_status is null or p.status = p_status)
           and (p_from is null or p.created_at >= p_from)
           and (p_to is null or p.created_at < p_to + 1)
           and (q is null or p.id::text ilike q || '%' or coalesce(o.id, v.id, cv.id, mp.id, cp.id, pp.id)::text ilike q || '%'
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
  if to_regclass('public.place_promo_plans') is null
     or to_regclass('public.place_promo_orders') is null
     or to_regprocedure('public.place_promo_order_create(text, uuid, text, integer)') is null
     or to_regprocedure('public.place_promo_payment_create(uuid, text, text)') is null
     or to_regprocedure('public.place_promo_state(text, uuid[])') is null
     or not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target7')
     or (select count(*) from pg_trigger where tgname = 'zz_place_promo_guard') <> 2 then
    raise exception '0093: final check failed — nothing changed';
  end if;
end $$;

commit;

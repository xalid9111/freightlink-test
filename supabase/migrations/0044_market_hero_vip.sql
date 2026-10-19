-- =====================================================================
-- 0044 — TIR Bazarı: top banner set by the admin + paid VIP
-- (owner, 19.10.2026)
--
-- * market_hero (one row): the picture and the texts of the banner at the
--   top of TIR Bazarı. Everybody reads it; only an admin changes it
--   (admin_market_set_hero, checked on the server, logged).
-- * market_vip_plans: VIP prices — 7 days 5 AZN, 14 days 9 AZN, 30 days
--   15 AZN. Everybody reads; only an admin changes them
--   (admin_market_set_vip_plan, logged).
-- * market_listings.vip_since: when the ad last became VIP — the page
--   shows the 6 newest VIP ads (market_vip_latest).
-- * market_vip_orders: "VIP et" on my own active ad → an order with the
--   plan's price (taken on the server, never from the app).
-- * Card payment for a VIP order goes through the existing checkout
--   (0037): ad_payments gets a market_vip_order_id; market_vip_payment_create
--   has the same rules as payment_create. The ad becomes VIP ONLY when a
--   verified provider event says the payment succeeded, and only in LIVE
--   mode (finance_apply_provider_event, one extra step). TEST payments
--   never change an ad.
--
-- Safe: forward-only, re-runnable. New tables / columns / functions;
-- ad_payments.order_id may now be empty for VIP payments (an ad payment
-- still needs it — checked). finance_apply_provider_event and
-- finance_payments are re-created with everything they did before plus
-- the VIP part. No row is changed or deleted.
-- =====================================================================

-- 1) Top banner ---------------------------------------------------------------
create table if not exists public.market_hero (
  id smallint primary key default 1 check (id = 1),
  image_url text check (image_url is null or char_length(image_url) <= 1000),
  title text check (title is null or char_length(title) <= 80),
  title_accent text check (title_accent is null or char_length(title_accent) <= 80),
  subtitle text check (subtitle is null or char_length(subtitle) <= 160),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
alter table public.market_hero enable row level security;
revoke all on public.market_hero from anon, authenticated;
grant select on public.market_hero to authenticated;
drop policy if exists "market_hero_read" on public.market_hero;
create policy "market_hero_read" on public.market_hero for select to authenticated using (true);

create or replace function public.admin_market_set_hero(
  p_image_url text, p_title text, p_title_accent text, p_subtitle text)
returns public.market_hero language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.market_hero; v_new public.market_hero;
begin
  perform public._require_admin();
  select * into v_old from market_hero where id = 1;
  insert into market_hero (id, image_url, title, title_accent, subtitle, updated_at, updated_by)
  values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_title), ''), nullif(btrim(p_title_accent), ''),
          nullif(btrim(p_subtitle), ''), now(), auth.uid())
  on conflict (id) do update
     set image_url = excluded.image_url, title = excluded.title, title_accent = excluded.title_accent,
         subtitle = excluded.subtitle, updated_at = now(), updated_by = auth.uid()
  returning * into v_new;
  perform public._admin_log('market.hero', 'market_hero', '1', to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end $$;
revoke all on function public.admin_market_set_hero(text, text, text, text) from public, anon;
grant execute on function public.admin_market_set_hero(text, text, text, text) to authenticated;

-- 2) VIP prices ---------------------------------------------------------------
create table if not exists public.market_vip_plans (
  days integer primary key check (days between 1 and 365),
  price numeric(12,2) not null check (price > 0),
  currency text not null default 'AZN' check (char_length(currency) between 3 and 4),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.market_vip_plans (days, price) values (7, 5), (14, 9), (30, 15)
on conflict (days) do nothing;
alter table public.market_vip_plans enable row level security;
revoke all on public.market_vip_plans from anon, authenticated;
grant select on public.market_vip_plans to authenticated;
drop policy if exists "market_vip_plans_read" on public.market_vip_plans;
create policy "market_vip_plans_read" on public.market_vip_plans for select to authenticated using (true);

create or replace function public.admin_market_set_vip_plan(p_days integer, p_price numeric, p_active boolean default true)
returns public.market_vip_plans language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.market_vip_plans; v_new public.market_vip_plans;
begin
  perform public._require_admin();
  if p_days is null or p_days not between 1 and 365 then raise exception 'invalid_days' using errcode = '22023'; end if;
  if p_price is null or p_price <= 0 or p_price > 100000 then raise exception 'invalid_price' using errcode = '22023'; end if;
  select * into v_old from market_vip_plans where days = p_days;
  insert into market_vip_plans (days, price, is_active, updated_at)
  values (p_days, round(p_price, 2), coalesce(p_active, true), now())
  on conflict (days) do update set price = excluded.price, is_active = excluded.is_active, updated_at = now()
  returning * into v_new;
  perform public._admin_log('market.vip_plan', 'market_vip_plan', p_days::text, to_jsonb(v_old), to_jsonb(v_new));
  return v_new;
end $$;
revoke all on function public.admin_market_set_vip_plan(integer, numeric, boolean) from public, anon;
grant execute on function public.admin_market_set_vip_plan(integer, numeric, boolean) to authenticated;

-- 3) Newest VIP ads -----------------------------------------------------------
alter table public.market_listings add column if not exists vip_since timestamptz;

-- When an ad becomes VIP (or its VIP is extended) it moves to the front.
-- Runs after market_listing_guard (triggers fire in name order), so an
-- owner can never set it: the guard already kept is_vip / vip_until.
create or replace function public.market_vip_since()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' then
    if new.is_vip and (not old.is_vip or new.vip_until is distinct from old.vip_until) then
      new.vip_since := clock_timestamp();
    elsif not new.is_vip then
      new.vip_since := null;
    else
      new.vip_since := old.vip_since;
    end if;
  else
    new.vip_since := case when new.is_vip then clock_timestamp() end;
  end if;
  return new;
end $$;
drop trigger if exists zz_market_vip_since on public.market_listings;
create trigger zz_market_vip_since
  before insert or update on public.market_listings
  for each row execute function public.market_vip_since();

-- The 6 newest VIP ads (caller's rights, RLS applies).
create or replace function public.market_vip_latest(p_category text default null, p_limit integer default 6)
returns setof public.market_listings
language sql stable security invoker set search_path = public, pg_temp as $$
  select l.* from public.market_listings l
  where l.status = 'active'
    and public.market_vip_active(l.is_vip, l.vip_until)
    and (p_category is null or l.category = p_category)
  order by l.vip_since desc nulls last, l.published_at desc nulls last, l.created_at desc
  limit greatest(1, least(coalesce(p_limit, 6), 24));
$$;
revoke all on function public.market_vip_latest(text, integer) from public, anon;
grant execute on function public.market_vip_latest(text, integer) to authenticated;

-- 4) VIP orders ---------------------------------------------------------------
create table if not exists public.market_vip_orders (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.market_listings(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete restrict,
  days integer not null check (days between 1 and 365),
  amount numeric(12,2) not null check (amount > 0),
  currency text not null,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'paid', 'cancelled')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index if not exists market_vip_orders_listing_idx on public.market_vip_orders (listing_id, created_at desc);
create index if not exists market_vip_orders_user_idx on public.market_vip_orders (user_id, created_at desc);
alter table public.market_vip_orders enable row level security;
revoke all on public.market_vip_orders from anon, authenticated;
grant select on public.market_vip_orders to authenticated;
drop policy if exists "market_vip_orders_read" on public.market_vip_orders;
create policy "market_vip_orders_read" on public.market_vip_orders for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()) or (select public.is_finance_admin()));

-- "VIP et": an order for MY active ad with the plan's price. An unpaid
-- order for the same ad and plan is re-used (double click = one order).
create or replace function public.market_vip_order_create(p_listing uuid, p_days integer)
returns public.market_vip_orders language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_l public.market_listings;
  v_plan public.market_vip_plans;
  v_ord public.market_vip_orders;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_l from market_listings where id = p_listing;
  if v_l.id is null or v_l.owner_id is distinct from v_uid then raise exception 'listing_not_found' using errcode = 'P0002'; end if;
  if v_l.status <> 'active' then raise exception 'listing_not_active' using errcode = '22023'; end if;
  select * into v_plan from market_vip_plans where days = p_days and is_active;
  if v_plan.days is null then raise exception 'invalid_plan' using errcode = '22023'; end if;

  select * into v_ord from market_vip_orders
   where listing_id = p_listing and user_id = v_uid and days = p_days and status = 'pending_payment'
     and amount = v_plan.price and currency = v_plan.currency
   order by created_at desc limit 1;
  if v_ord.id is not null then return v_ord; end if;

  insert into market_vip_orders (listing_id, user_id, days, amount, currency)
  values (p_listing, v_uid, v_plan.days, v_plan.price, upper(v_plan.currency))
  returning * into v_ord;
  return v_ord;
end $$;
revoke all on function public.market_vip_order_create(uuid, integer) from public, anon;
grant execute on function public.market_vip_order_create(uuid, integer) to authenticated;

-- 5) Card payments for VIP orders (same checkout as ad orders, 0037) --------
alter table public.ad_payments add column if not exists market_vip_order_id uuid
  references public.market_vip_orders(id) on delete restrict;
alter table public.ad_payments alter column order_id drop not null;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_payments_one_target') then
    alter table public.ad_payments add constraint ad_payments_one_target
      check ((order_id is not null) <> (market_vip_order_id is not null));
  end if;
end $$;
create unique index if not exists ad_payments_one_open_per_vip_order on public.ad_payments (market_vip_order_id)
  where market_vip_order_id is not null and status in ('created', 'pending');
create unique index if not exists ad_payments_one_success_per_vip_order on public.ad_payments (market_vip_order_id, mode)
  where market_vip_order_id is not null and status = 'succeeded';

-- Start (or re-use) a checkout for my VIP order. Amount = the order's price.
-- Same rules as payment_create (0037).
create or replace function public.market_vip_payment_create(p_vip_order uuid, p_method text, p_key text)
returns public.ad_payments language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.payment_settings := public._payment_settings();
  v_uid uuid := auth.uid();
  v_ord public.market_vip_orders;
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

  select * into v_ord from market_vip_orders where id = p_vip_order for update;
  if v_ord.id is null or v_ord.user_id is distinct from v_uid then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if v_ord.status <> 'pending_payment' or coalesce(v_ord.amount, 0) <= 0 then
    raise exception 'order_not_payable' using errcode = '22023';
  end if;
  if exists (select 1 from ad_payments where market_vip_order_id = p_vip_order and mode = s.mode and status = 'succeeded') then
    raise exception 'already_paid' using errcode = '22023';
  end if;

  select * into v_pay from ad_payments where market_vip_order_id = p_vip_order and status in ('created', 'pending');
  if v_pay.id is not null then return v_pay; end if;

  insert into ad_payments (order_id, market_vip_order_id, user_id, amount, currency, method, provider, mode, commission, idempotency_key)
  values (null, p_vip_order, v_uid, v_ord.amount, upper(v_ord.currency), p_method,
          case when s.mode = 'test' then 'test' else s.provider end, s.mode,
          round(v_ord.amount * s.commission_pct / 100, 2), p_key)
  returning * into v_pay;
  perform public._finance_log('payment.create', 'payment', v_pay.id::text,
    jsonb_build_object('vip_order_id', p_vip_order, 'amount', v_pay.amount, 'currency', v_pay.currency, 'method', p_method, 'mode', s.mode));
  return v_pay;
end $$;
revoke all on function public.market_vip_payment_create(uuid, text, text) from public, anon;
grant execute on function public.market_vip_payment_create(uuid, text, text) to authenticated;

-- A LIVE VIP payment succeeded: the order is paid and the ad is VIP for the
-- plan's days (added to a VIP that is still running). Called only from
-- finance_apply_provider_event.
create or replace function public._market_vip_apply(p_vip_order uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_ord public.market_vip_orders;
begin
  update market_vip_orders set status = 'paid', paid_at = coalesce(paid_at, now())
   where id = p_vip_order and status = 'pending_payment'
  returning * into v_ord;
  if v_ord.id is null then return; end if;
  perform set_config('app.market_trusted', '1', true);
  update market_listings
     set is_vip = true,
         -- An admin's VIP without an end date stays without one.
         vip_until = case when is_vip and vip_until is null then null
                          else greatest(coalesce(case when market_vip_active(is_vip, vip_until) then vip_until end, now()), now())
                               + make_interval(days => v_ord.days) end
   where id = v_ord.listing_id;
  perform set_config('app.market_trusted', '', true);
end $$;
revoke all on function public._market_vip_apply(uuid) from public, anon, authenticated;

-- 0037's function with ONE extra step at the end: a VIP payment marks its
-- VIP order paid and makes the ad VIP (LIVE only, like ad orders).
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
    if v_pay.market_vip_order_id is not null then
      perform public._market_vip_apply(v_pay.market_vip_order_id);
    end if;
  end if;
  perform public._finance_log('payment.' || v_new, 'payment', v_pay.id::text,
    jsonb_build_object('provider', p_provider, 'event_id', p_event_id, 'amount', v_pay.amount, 'currency', v_pay.currency,
                       'mode', v_pay.mode, 'order_id', v_pay.order_id, 'vip_order_id', v_pay.market_vip_order_id));
  return 'applied';
end $$;
revoke all on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finance_apply_provider_event(text, text, uuid, text, numeric, text, text, jsonb) to service_role;

-- 0037's payment list for the finance owner, now also with VIP payments
-- (left join; ad payments are listed exactly as before).
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
                 'id', p.id, 'order_id', coalesce(p.order_id, p.market_vip_order_id), 'order_no', o.order_no,
                 'order_title', case when p.market_vip_order_id is not null
                                     then 'VIP ' || v.days || ' · ' || coalesce(nullif(btrim(coalesce(ml.brand, '') || ' ' || coalesce(ml.model, '')), ''), '#' || ml.listing_no::text)
                                     else o.title end,
                 'order_status', coalesce(o.status, v.status), 'order_payment_status', coalesce(o.payment_status, v.status),
                 'customer', coalesce(u.full_name, u.email), 'amount', p.amount, 'currency', p.currency,
                 'commission', p.commission, 'method', p.method, 'provider', p.provider, 'mode', p.mode,
                 'status', p.status, 'failure_reason', p.failure_reason,
                 'created_at', p.created_at, 'confirmed_at', p.confirmed_at) r
          from ad_payments p
          left join ad_orders o on o.id = p.order_id
          left join market_vip_orders v on v.id = p.market_vip_order_id
          left join market_listings ml on ml.id = v.listing_id
          left join users u on u.id = p.user_id
         where p.mode = p_mode
           and (p_status is null or p.status = p_status)
           and (p_from is null or p.created_at >= p_from)
           and (p_to is null or p.created_at < p_to + 1)
           and (q is null or p.id::text ilike q || '%' or coalesce(o.id, v.id)::text ilike q || '%'
                or coalesce(o.order_no::text, '') = q or coalesce(o.title, '') ilike '%' || q || '%'
                or coalesce(u.full_name, '') ilike '%' || q || '%')
         order by p.created_at desc
         limit least(greatest(coalesce(p_limit, 50), 1), 200) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.finance_payments(text, text, date, date, text, integer, integer) from public, anon;
grant execute on function public.finance_payments(text, text, date, date, text, integer, integer) to authenticated;

notify pgrst, 'reload schema';

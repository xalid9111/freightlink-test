-- =====================================================================
-- 0015 — Advertising, phase 1.
-- SAFE FORWARD MIGRATION: only ADDs tables, functions, policies and a
-- storage bucket. No existing table, policy or row is changed. Idempotent.
--
-- Flow:  Reklam ver → order (pending_payment) → customer reports payment
--        (awaiting_approval) → admin sees it → admin confirms payment and
--        approves → admin uploads the banner and sets dates → ad active.
-- A paid order NEVER goes live by itself: only an admin creates the ad.
-- =====================================================================

-- 1) Packages (admin-editable; prices are set by the admin) --------------
create table if not exists public.ad_packages (
  id text primary key,
  name text not null,
  days integer not null check (days > 0),
  price numeric(10,2) not null check (price >= 0),
  currency text not null default 'USD',
  is_active boolean not null default true,
  sort integer not null default 0,
  updated_at timestamptz not null default now()
);
-- Seeded INACTIVE with price 0: the admin sets real prices and switches
-- them on in Admin → Reklamlar → Paketlər (no invented prices).
insert into public.ad_packages (id, name, days, price, sort, is_active) values
  ('week',   '1 həftə', 7,  0, 1, false),
  ('month',  '1 ay',    30, 0, 2, false),
  ('quarter','3 ay',    90, 0, 3, false)
on conflict (id) do nothing;

-- 2) Orders ---------------------------------------------------------------
create table if not exists public.ad_orders (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  package_id text references public.ad_packages(id) on delete set null,
  package_name text not null,
  days integer not null,
  price numeric(10,2) not null,
  currency text not null default 'USD',
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','submitted','paid','refunded')),
  status text not null default 'pending_payment'
    check (status in ('pending_payment','awaiting_approval','approved','rejected','active','expired','cancelled')),
  customer_note text,
  payment_reference text,
  admin_note text,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_ad_orders_status on public.ad_orders(status, created_at desc);
create index if not exists idx_ad_orders_advertiser on public.ad_orders(advertiser_id);

-- 3) Ads (what the home feed shows) -------------------------------------
create table if not exists public.ads (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.ad_orders(id) on delete set null,
  advertiser_id uuid not null references public.users(id) on delete cascade,
  title text,
  image_url text not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index if not exists idx_ads_live on public.ads(is_active, starts_at, ends_at);

alter table public.ad_packages enable row level security;
alter table public.ad_orders enable row level security;
alter table public.ads enable row level security;

drop policy if exists "ad_packages_read" on public.ad_packages;
create policy "ad_packages_read" on public.ad_packages
  for select to authenticated using (is_active or public.is_admin());

drop policy if exists "ad_orders_own_or_admin_read" on public.ad_orders;
create policy "ad_orders_own_or_admin_read" on public.ad_orders
  for select to authenticated using (advertiser_id = auth.uid() or public.is_admin());

-- live ads for everyone; the advertiser and admins also see the rest
drop policy if exists "ads_read" on public.ads;
create policy "ads_read" on public.ads
  for select to authenticated using (
    (is_active and now() >= starts_at and now() < ends_at)
    or advertiser_id = auth.uid()
    or public.is_admin()
  );
-- No insert/update/delete policies: all writes go through the functions below.

-- 4) Customer functions ---------------------------------------------------
-- Price and duration come from the package on the server (the app can't
-- choose its own price).
create or replace function public.create_ad_order(p_package text, p_note text default null)
returns public.ad_orders
language plpgsql security definer set search_path = public as $$
declare v_pkg public.ad_packages; v_order public.ad_orders; v_company uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'account_blocked' using errcode = '42501'; end if;
  select * into v_pkg from ad_packages where id = p_package and is_active;
  if v_pkg.id is null then raise exception 'package_not_found' using errcode = 'P0002'; end if;
  select id into v_company from companies where owner_user_id = auth.uid() order by created_at limit 1;
  insert into ad_orders (advertiser_id, company_id, package_id, package_name, days, price, currency, customer_note)
  values (auth.uid(), v_company, v_pkg.id, v_pkg.name, v_pkg.days, v_pkg.price, v_pkg.currency, nullif(btrim(p_note), ''))
  returning * into v_order;
  return v_order;
end;
$$;

-- "I have paid": goes to the admin for checking — never live by itself.
create or replace function public.submit_ad_payment(p_order uuid, p_reference text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update ad_orders
     set payment_status = 'submitted',
         status = 'awaiting_approval',
         payment_reference = nullif(btrim(p_reference), ''),
         updated_at = now()
   where id = p_order and advertiser_id = auth.uid() and status = 'pending_payment';
  if not found then raise exception 'order_not_payable' using errcode = '22023'; end if;
end;
$$;

create or replace function public.cancel_ad_order(p_order uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update ad_orders set status = 'cancelled', updated_at = now()
   where id = p_order and advertiser_id = auth.uid()
     and status in ('pending_payment','awaiting_approval') and payment_status <> 'paid';
  if not found then raise exception 'order_not_cancellable' using errcode = '22023'; end if;
end;
$$;

grant execute on function public.create_ad_order(text, text) to authenticated;
grant execute on function public.submit_ad_payment(uuid, text) to authenticated;
grant execute on function public.cancel_ad_order(uuid) to authenticated;

-- 5) Admin functions (is_admin() checked on the server, audit-logged) ----
create or replace function public.admin_update_ad_order(
  p_order uuid, p_status text default null, p_payment_status text default null, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare v_old jsonb; v_new jsonb;
begin
  perform public._require_admin();
  select to_jsonb(o) into v_old from ad_orders o where id = p_order;
  if v_old is null then raise exception 'not_found'; end if;
  if p_status is not null and p_status not in ('pending_payment','awaiting_approval','approved','rejected','active','expired','cancelled') then
    raise exception 'invalid_status';
  end if;
  if p_payment_status is not null and p_payment_status not in ('unpaid','submitted','paid','refunded') then
    raise exception 'invalid_status';
  end if;
  update ad_orders set
    status = coalesce(p_status, status),
    payment_status = coalesce(p_payment_status, payment_status),
    paid_at = case when p_payment_status = 'paid' and paid_at is null then now() else paid_at end,
    admin_note = coalesce(nullif(btrim(p_note), ''), admin_note),
    updated_at = now()
  where id = p_order;
  select to_jsonb(o) into v_new from ad_orders o where id = p_order;
  perform public._admin_log('ad_order.update', 'ad_order', p_order::text, v_old, v_new, p_note);
end;
$$;

-- Create (p_ad null) or edit an ad. Creating one from an order marks the
-- order 'active' (the order must be paid and approved first).
create or replace function public.admin_save_ad(
  p_ad uuid, p_order uuid, p_advertiser uuid, p_title text, p_image_url text,
  p_starts timestamptz, p_ends timestamptz, p_active boolean)
returns public.ads
language plpgsql security definer set search_path = public as $$
declare v_old jsonb; v_ad public.ads; v_ord public.ad_orders;
begin
  perform public._require_admin();
  if p_image_url is null or btrim(p_image_url) = '' then raise exception 'invalid_image'; end if;
  if p_ends <= p_starts then raise exception 'invalid_dates'; end if;
  if p_order is not null then
    select * into v_ord from ad_orders where id = p_order;
    if v_ord.id is null then raise exception 'not_found'; end if;
    if v_ord.payment_status <> 'paid' or v_ord.status not in ('approved','active') then
      raise exception 'invalid_order_state';
    end if;
  end if;
  if p_ad is null then
    insert into ads (order_id, advertiser_id, title, image_url, starts_at, ends_at, is_active)
    values (p_order, coalesce(p_advertiser, v_ord.advertiser_id), nullif(btrim(p_title), ''), p_image_url, p_starts, p_ends, coalesce(p_active, false))
    returning * into v_ad;
    if p_order is not null then
      update ad_orders set status = 'active', updated_at = now() where id = p_order;
    end if;
    perform public._admin_log('ad.create', 'ad', v_ad.id::text, null, to_jsonb(v_ad));
  else
    select to_jsonb(a) into v_old from ads a where id = p_ad;
    if v_old is null then raise exception 'not_found'; end if;
    update ads set
      title = nullif(btrim(p_title), ''),
      image_url = p_image_url,
      starts_at = p_starts,
      ends_at = p_ends,
      is_active = coalesce(p_active, is_active),
      updated_at = now()
    where id = p_ad
    returning * into v_ad;
    perform public._admin_log('ad.update', 'ad', p_ad::text, v_old, to_jsonb(v_ad));
  end if;
  return v_ad;
end;
$$;

create or replace function public.admin_set_ad_active(p_ad uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_old boolean;
begin
  perform public._require_admin();
  select is_active into v_old from ads where id = p_ad;
  if not found then raise exception 'not_found'; end if;
  update ads set is_active = p_active, updated_at = now() where id = p_ad;
  perform public._admin_log(case when p_active then 'ad.activate' else 'ad.deactivate' end, 'ad', p_ad::text,
    jsonb_build_object('is_active', v_old), jsonb_build_object('is_active', p_active));
end;
$$;

create or replace function public.admin_save_ad_package(p_id text, p_name text, p_days integer, p_price numeric, p_active boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  if p_days is null or p_days <= 0 or p_price is null or p_price < 0 then raise exception 'invalid_value'; end if;
  select to_jsonb(p) into v_old from ad_packages p where id = p_id;
  insert into ad_packages (id, name, days, price, is_active)
  values (p_id, p_name, p_days, p_price, coalesce(p_active, true))
  on conflict (id) do update set name = excluded.name, days = excluded.days, price = excluded.price,
    is_active = excluded.is_active, updated_at = now();
  perform public._admin_log('ad_package.save', 'ad_package', p_id, v_old,
    jsonb_build_object('name', p_name, 'days', p_days, 'price', p_price, 'is_active', p_active));
end;
$$;

grant execute on function public.admin_update_ad_order(uuid, text, text, text) to authenticated;
grant execute on function public.admin_save_ad(uuid, uuid, uuid, text, text, timestamptz, timestamptz, boolean) to authenticated;
grant execute on function public.admin_set_ad_active(uuid, boolean) to authenticated;
grant execute on function public.admin_save_ad_package(text, text, integer, numeric, boolean) to authenticated;

-- Payment instructions shown to customers (admin edits; anyone signed in reads).
create or replace function public.get_ad_payment_info()
returns text language sql stable security definer set search_path = public as $$
  select value->>'text' from platform_settings where key = 'ads_payment_info';
$$;
create or replace function public.admin_set_ad_payment_info(p_text text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  insert into platform_settings (key, value) values ('ads_payment_info', jsonb_build_object('text', p_text))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  perform public._admin_log('ad_payment_info.save', 'setting', 'ads_payment_info', null, jsonb_build_object('text', p_text));
end;
$$;
grant execute on function public.get_ad_payment_info() to authenticated;
grant execute on function public.admin_set_ad_payment_info(text) to authenticated;

-- 6) Banner images: public bucket "ads", only admins upload -------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('ads', 'ads', true, 5242880)
on conflict (id) do nothing;

drop policy if exists "ads_images_admin_insert" on storage.objects;
create policy "ads_images_admin_insert" on storage.objects
  for insert to authenticated with check (bucket_id = 'ads' and public.is_admin());
drop policy if exists "ads_images_admin_update" on storage.objects;
create policy "ads_images_admin_update" on storage.objects
  for update to authenticated using (bucket_id = 'ads' and public.is_admin());
drop policy if exists "ads_images_admin_delete" on storage.objects;
create policy "ads_images_admin_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'ads' and public.is_admin());
drop policy if exists "ads_images_read" on storage.objects;
create policy "ads_images_read" on storage.objects
  for select using (bucket_id = 'ads');

-- 7) Dashboard counter for the admin bell -------------------------------
create or replace function public.admin_ad_counts()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'orders_waiting', (select count(*) from ad_orders where status = 'awaiting_approval'),
    'orders_to_publish', (select count(*) from ad_orders where status = 'approved'),
    'ads_live', (select count(*) from ads where is_active and now() >= starts_at and now() < ends_at)
  ) else '{}'::jsonb end;
$$;
grant execute on function public.admin_ad_counts() to authenticated;

-- 8) Realtime ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['ad_orders','ads'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

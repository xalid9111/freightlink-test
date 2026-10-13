-- =====================================================================
-- 0021 — Ad templates, customer-built banners, receipt payments and the
--        home-feed ads switch.
--
-- SAFE FORWARD MIGRATION (apply after 0020): only adds tables, columns,
-- functions, policies and a private storage bucket. No existing order,
-- ad or payment is changed or deleted. Re-runnable.
--
-- Flow:
--   admin: templates (1350×300 background + editable text fields + colours)
--   customer: Reklam ver → Reklam yarat → template, texts, colour,
--             destination, targeting, 5/15/30 days, start date
--             → order (pending_payment, price from the admin's package)
--             → bank / card details → receipt photo → "Yoxlanılır"
--   admin: sees order + receipt, checks the bank → approve (ad is created,
--          starts on the chosen date, stops by itself after N days) or
--          reject with a reason.
--   A receipt NEVER approves anything by itself; nothing is published
--   without the admin's approval.
--   Home feed shows ads only while the admin switch is ON (default OFF).
-- =====================================================================

-- 1) Templates ------------------------------------------------------------
create table if not exists public.ad_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 80),
  image_url text not null,
  fields jsonb not null default '[]'::jsonb,
  colors text[] not null default array['#FFFFFF'],
  is_active boolean not null default false,
  sort integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.ad_templates enable row level security;
drop policy if exists "ad_templates_read" on public.ad_templates;
create policy "ad_templates_read" on public.ad_templates
  for select to authenticated using (is_active or public.is_admin());
-- Writes only through admin_save_ad_template().

-- Template field list: 1–6 fields, each
--   {key, label, default, x, y, w (0..1 of the banner), size (px at 1350 wide),
--    max (characters), align left|center|right, bold}
create or replace function public._ad_template_fields_ok(p jsonb)
returns boolean language plpgsql immutable set search_path = public, pg_temp as $$
declare f jsonb; keys text[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'array' or jsonb_array_length(p) < 1 or jsonb_array_length(p) > 6 then
    return false;
  end if;
  for f in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(f) <> 'object' then return false; end if;
    if coalesce(f->>'key', '') !~ '^[a-z0-9_]{1,20}$' or (f->>'key') = any(keys) then return false; end if;
    keys := keys || (f->>'key');
    if char_length(coalesce(f->>'label', '')) not between 1 and 40 then return false; end if;
    if char_length(coalesce(f->>'default', '')) > 120 then return false; end if;
    if coalesce((f->>'x')::numeric, -1) not between 0 and 1
       or coalesce((f->>'y')::numeric, -1) not between 0 and 1
       or coalesce((f->>'w')::numeric, -1) not between 0.05 and 1 then return false; end if;
    if coalesce((f->>'size')::numeric, 0) not between 10 and 200 then return false; end if;
    if coalesce((f->>'max')::integer, 0) not between 1 and 120 then return false; end if;
    if coalesce(f->>'align', 'left') not in ('left','center','right') then return false; end if;
  end loop;
  return true;
exception when others then
  return false;
end;
$$;

-- 2) New order / ad columns (all nullable or defaulted: old rows stay valid)
create sequence if not exists public.ad_order_no_seq start 1001;
alter table public.ad_orders
  add column if not exists order_no bigint,
  add column if not exists template_id uuid references public.ad_templates(id) on delete set null,
  add column if not exists creative jsonb,
  add column if not exists starts_on date,
  add column if not exists receipt_path text,
  add column if not exists receipt_uploaded_at timestamptz,
  add column if not exists reviewed_at timestamptz,
  add column if not exists ad_starts_at timestamptz,
  add column if not exists ad_ends_at timestamptz;
alter table public.ad_orders alter column order_no set default nextval('public.ad_order_no_seq');
update public.ad_orders set order_no = nextval('public.ad_order_no_seq') where order_no is null;
create unique index if not exists uq_ad_orders_order_no on public.ad_orders(order_no);

alter table public.ads add column if not exists creative jsonb;

-- 3) Duration packages: 5 / 15 / 30 days. Seeded HIDDEN with price 0 —
--    the admin sets the prices and switches them on (no invented prices).
insert into public.ad_packages (id, name, days, price, sort, is_active) values
  ('d5',  '5 gün',  5,  0, 10, false),
  ('d15', '15 gün', 15, 0, 11, false),
  ('d30', '30 gün', 30, 0, 12, false)
on conflict (id) do nothing;

-- 4) Customer: create an order from a template ---------------------------
create or replace function public.create_ad_order_from_template(
  p_template uuid,
  p_texts jsonb,
  p_color text,
  p_days integer,
  p_starts_on date,
  p_destination_type text default 'profile',
  p_destination_url text default null,
  p_target_countries text[] default '{}',
  p_route_from text default null,
  p_route_to text default null,
  p_note text default null
)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_tpl public.ad_templates;
  v_pkg public.ad_packages;
  v_order public.ad_orders;
  v_company uuid;
  v_texts jsonb := '{}'::jsonb;
  v_any boolean := false;
  f jsonb;
  v_val text;
  v_title text;
  v_destination text := nullif(btrim(p_destination_url), '');
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'account_blocked' using errcode = '42501'; end if;

  select * into v_tpl from ad_templates where id = p_template and is_active;
  if v_tpl.id is null then raise exception 'template_not_found' using errcode = 'P0002'; end if;

  -- Texts: only the template's own fields, trimmed, within each field's limit.
  for f in select * from jsonb_array_elements(v_tpl.fields) loop
    v_val := btrim(coalesce(p_texts->>(f->>'key'), ''));
    if char_length(v_val) > coalesce((f->>'max')::integer, 60) then
      raise exception 'text_too_long' using errcode = '22023';
    end if;
    if v_val <> '' then
      v_any := true;
      if v_title is null then v_title := v_val; end if;
    end if;
    v_texts := v_texts || jsonb_build_object(f->>'key', v_val);
  end loop;
  if not v_any then raise exception 'text_required' using errcode = '22023'; end if;

  if p_color is null or not (upper(p_color) = any(select upper(c) from unnest(v_tpl.colors) c)) then
    raise exception 'invalid_color' using errcode = '22023';
  end if;

  if p_days not in (5, 15, 30) then raise exception 'invalid_duration' using errcode = '22023'; end if;
  select * into v_pkg from ad_packages
   where days = p_days and is_active and price > 0
   order by sort, id limit 1;
  if v_pkg.id is null then raise exception 'package_not_found' using errcode = 'P0002'; end if;

  if p_starts_on is null or p_starts_on < (now() at time zone 'Asia/Baku')::date
     or p_starts_on > (now() at time zone 'Asia/Baku')::date + 90 then
    raise exception 'invalid_start_date' using errcode = '22023';
  end if;

  if coalesce(p_destination_type, '') not in ('profile','external') then
    raise exception 'invalid_destination' using errcode = '22023';
  end if;
  if p_destination_type = 'external' and
     (v_destination is null or v_destination !~* '^https://([a-z0-9-]+\.)+[a-z0-9-]+(:[0-9]{1,5})?([/?#][^[:space:]]*)?$') then
    raise exception 'invalid_external_url' using errcode = '22023';
  end if;
  if p_destination_type = 'profile' then v_destination := null; end if;
  if exists (select 1 from unnest(coalesce(p_target_countries, '{}')) c where c !~ '^[A-Z]{2}$') then
    raise exception 'invalid_target_country' using errcode = '22023';
  end if;
  if char_length(coalesce(p_route_from, '')) > 100 or char_length(coalesce(p_route_to, '')) > 100 then
    raise exception 'invalid_route' using errcode = '22023';
  end if;

  select id into v_company from companies where owner_user_id = auth.uid() order by created_at limit 1;

  insert into ad_orders (
    advertiser_id, company_id, package_id, package_name, days, price, currency,
    status, payment_status, title, image_url, destination_type, destination_url,
    target_countries, route_from, route_to, customer_note,
    template_id, creative, starts_on
  ) values (
    auth.uid(), v_company, v_pkg.id, v_pkg.name, v_pkg.days, v_pkg.price, v_pkg.currency,
    'pending_payment', 'unpaid', left(v_title, 100), v_tpl.image_url, p_destination_type, v_destination,
    coalesce(p_target_countries, '{}'), nullif(btrim(p_route_from), ''), nullif(btrim(p_route_to), ''),
    nullif(btrim(p_note), ''),
    v_tpl.id,
    -- Snapshot: later template edits never change an ordered banner.
    jsonb_build_object('template_id', v_tpl.id, 'image_url', v_tpl.image_url,
                       'fields', v_tpl.fields, 'texts', v_texts, 'color', upper(p_color)),
    p_starts_on
  ) returning * into v_order;
  return v_order;
end;
$$;

-- 5) Receipts: private bucket, folder = <user id>/<order id>/ ---------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('ad-receipts', 'ad-receipts', false, 10485760)
on conflict (id) do nothing;

create or replace function public.is_own_ad_order(p_order text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.ad_orders where id::text = p_order and advertiser_id = auth.uid());
$$;

drop policy if exists "ad_receipts_insert_own" on storage.objects;
create policy "ad_receipts_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'ad-receipts'
              and (storage.foldername(name))[1] = auth.uid()::text
              and public.is_own_ad_order((storage.foldername(name))[2]));
drop policy if exists "ad_receipts_read_own_or_admin" on storage.objects;
create policy "ad_receipts_read_own_or_admin" on storage.objects
  for select to authenticated
  using (bucket_id = 'ad-receipts'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- Customer attaches the receipt → "Yoxlanılır". Does NOT mark anything paid.
create or replace function public.submit_ad_receipt(p_order uuid, p_path text)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_order public.ad_orders;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_path is null or p_path not like auth.uid()::text || '/' || p_order::text || '/%' or p_path like '%..%' then
    raise exception 'invalid_receipt' using errcode = '22023';
  end if;
  update ad_orders
     set receipt_path = p_path,
         receipt_uploaded_at = now(),
         payment_status = 'submitted',
         status = 'awaiting_approval',
         updated_at = now()
   where id = p_order and advertiser_id = auth.uid()
     and status in ('pending_payment','awaiting_approval')
     and payment_status in ('unpaid','submitted')
  returning * into v_order;
  if v_order.id is null then raise exception 'order_not_payable' using errcode = '22023'; end if;
  return v_order;
end;
$$;

-- 6) Admin: approve (creates the scheduled ad) or reject with a reason -----
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

  -- Approve = "the money is on our account". Only template orders with a
  -- receipt that are waiting for review can be approved here.
  if v_old.creative is null then raise exception 'not_template_order' using errcode = '22023'; end if;
  if v_old.status <> 'awaiting_approval' or v_old.receipt_path is null then
    raise exception 'invalid_order_state' using errcode = '22023';
  end if;

  -- Starts at 00:00 (Baku) of the chosen day; if that moment has passed,
  -- it starts now and still runs the full number of days.
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
    status = 'active',            -- "ad created"; scheduled / live / ended follow from the dates
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

-- Templates CRUD (admin only) --------------------------------------------
create or replace function public.admin_save_ad_template(p_id uuid, p_data jsonb)
returns public.ad_templates
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.ad_templates; v_row public.ad_templates; v_colors text[];
begin
  perform public._require_admin();
  if not public._ad_template_fields_ok(p_data->'fields') then raise exception 'invalid_fields' using errcode = '22023'; end if;
  v_colors := array(select upper(c) from jsonb_array_elements_text(coalesce(p_data->'colors', '[]'::jsonb)) c);
  if cardinality(v_colors) < 1 or cardinality(v_colors) > 12
     or exists (select 1 from unnest(v_colors) c where c !~ '^#[0-9A-F]{6}$') then
    raise exception 'invalid_colors' using errcode = '22023';
  end if;
  if nullif(btrim(p_data->>'image_url'), '') is null then raise exception 'invalid_image' using errcode = '22023'; end if;
  if p_id is null then
    insert into ad_templates (name, image_url, fields, colors, is_active, sort)
    values (btrim(p_data->>'name'), btrim(p_data->>'image_url'), p_data->'fields', v_colors,
            coalesce((p_data->>'is_active')::boolean, false), coalesce((p_data->>'sort')::integer, 100))
    returning * into v_row;
    perform public._admin_log('ad_template.create', 'ad_template', v_row.id::text, null, to_jsonb(v_row));
  else
    select * into v_old from ad_templates where id = p_id for update;
    if v_old.id is null then raise exception 'not_found'; end if;
    update ad_templates set
      name = btrim(p_data->>'name'),
      image_url = btrim(p_data->>'image_url'),
      fields = p_data->'fields',
      colors = v_colors,
      is_active = coalesce((p_data->>'is_active')::boolean, is_active),
      sort = coalesce((p_data->>'sort')::integer, sort),
      updated_at = now()
    where id = p_id returning * into v_row;
    perform public._admin_log('ad_template.update', 'ad_template', p_id::text, to_jsonb(v_old), to_jsonb(v_row));
  end if;
  return v_row;
end;
$$;

create or replace function public.admin_set_ad_template_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  update ad_templates set is_active = p_active, updated_at = now() where id = p_id;
  if not found then raise exception 'not_found'; end if;
  perform public._admin_log(case when p_active then 'ad_template.activate' else 'ad_template.deactivate' end,
    'ad_template', p_id::text, null, jsonb_build_object('is_active', p_active));
end;
$$;

-- 7) Home-feed ads switch (default OFF) -----------------------------------
create or replace function public.home_ads_enabled()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select (value->>'enabled')::boolean from platform_settings where key = 'home_ads'), false);
$$;

create or replace function public.admin_set_home_ads_enabled(p_enabled boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  insert into platform_settings (key, value) values ('home_ads', jsonb_build_object('enabled', coalesce(p_enabled, false)))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  -- Orders, payments and ads are NOT touched by this switch.
  perform public._admin_log('home_ads.' || case when p_enabled then 'enable' else 'disable' end,
    'setting', 'home_ads', null, jsonb_build_object('enabled', p_enabled));
end;
$$;

-- Ads for the home feed: empty while the switch is OFF; otherwise only ads
-- that are on, inside their dates, and either paid (order approved by the
-- admin) or created by an admin without an order.
create or replace function public.home_feed_ads()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select case when not public.home_ads_enabled() or auth.uid() is null then '[]'::jsonb else
    coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at)
      from ads a
      left join ad_orders o on o.id = a.order_id
      where a.is_active and now() >= a.starts_at and now() < a.ends_at
        and (a.order_id is null or o.payment_status = 'paid')
        and not public.is_blocked(a.advertiser_id)
    ), '[]'::jsonb)
  end;
$$;

-- 8) Privileges -------------------------------------------------------------
revoke all on function public.create_ad_order_from_template(uuid,jsonb,text,integer,date,text,text,text[],text,text,text) from public, anon;
revoke all on function public.submit_ad_receipt(uuid,text) from public, anon;
revoke all on function public.admin_review_ad_order(uuid,boolean,text) from public, anon;
revoke all on function public.admin_save_ad_template(uuid,jsonb) from public, anon;
revoke all on function public.admin_set_ad_template_active(uuid,boolean) from public, anon;
revoke all on function public.admin_set_home_ads_enabled(boolean) from public, anon;
revoke all on function public.home_feed_ads() from public, anon;
revoke all on function public.home_ads_enabled() from public, anon;
grant execute on function public.create_ad_order_from_template(uuid,jsonb,text,integer,date,text,text,text[],text,text,text) to authenticated;
grant execute on function public.submit_ad_receipt(uuid,text) to authenticated;
grant execute on function public.admin_review_ad_order(uuid,boolean,text) to authenticated;
grant execute on function public.admin_save_ad_template(uuid,jsonb) to authenticated;
grant execute on function public.admin_set_ad_template_active(uuid,boolean) to authenticated;
grant execute on function public.admin_set_home_ads_enabled(boolean) to authenticated;
grant execute on function public.home_feed_ads() to authenticated;
grant execute on function public.home_ads_enabled() to authenticated;
-- is_own_ad_order is used inside a storage policy: signed-in users need it.
revoke all on function public.is_own_ad_order(text) from public, anon;
grant execute on function public.is_own_ad_order(text) to authenticated;
grant select on public.ad_templates to authenticated;

-- 9) Realtime for templates (admin + customer lists refresh) ----------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ad_templates') then
    alter publication supabase_realtime add table public.ad_templates;
  end if;
end $$;

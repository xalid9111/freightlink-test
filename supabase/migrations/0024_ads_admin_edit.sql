-- =====================================================================
-- 0024 — ADS: admin edit, cleaner input, no start date
--
-- 1) Texts are cleaned on the server: invisible characters that iPhone
--    adds when a number is pasted / autofilled (U+202A, U+200E, …) are
--    removed, odd spaces become normal spaces. "+994…" pasted from
--    Contacts is no longer rejected as an invalid phone.
-- 2) Target route = countries only (ISO code, e.g. AZ → GE). Free text
--    like "baki" could never match a load, so the ad was never shown.
--    Existing rows are NOT changed — the admin fixes them in the editor.
-- 3) No start date for the customer: p_starts_on may be null → the ad
--    starts when the admin approves and runs the chosen 5 / 15 / 30 days.
-- 4) admin_update_ad_order_v2: the admin edits an order or a published ad
--    (background, texts, fonts, logo, link, countries, route, dates).
--
-- Safe: forward-only, re-runnable, deletes and rewrites no data.
-- =====================================================================

-- 1) Text cleaning --------------------------------------------------------------
create or replace function public._ad_clean_text(p text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select btrim(regexp_replace(
           regexp_replace(coalesce(p, ''), '[​-‏‪-‮⁠-⁩﻿­]', '', 'g'),
           '[   \t]', ' ', 'g'));
$$;
revoke all on function public._ad_clean_text(text) from public, anon;
grant execute on function public._ad_clean_text(text) to authenticated;

-- Route value: null / '' → null; otherwise a 2-letter country code.
create or replace function public._ad_route_code(p text)
returns text language plpgsql immutable set search_path = public, pg_temp as $$
declare v text := upper(public._ad_clean_text(p));
begin
  if v = '' then return null; end if;
  if v !~ '^[A-Z]{2}$' then raise exception 'invalid_route' using errcode = '22023'; end if;
  return v;
end;
$$;
revoke all on function public._ad_route_code(text) from public, anon, authenticated;

-- 2) Creative validation with an explicit owner (admin edits someone's ad) --
--    p_owner      = whose folder the logo may come from (the advertiser)
--    p_extra_owner = a second allowed folder (the editing admin), or null
create or replace function public._ad_v2_creative_for(
  p_owner uuid, p_extra_owner uuid,
  p_template public.ad_templates, p_texts jsonb, p_style jsonb, p_logo_url text, p_logo_bg text
) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  k text;
  v_company text := public._ad_clean_text(p_texts->>'company');
  v_activity text := public._ad_clean_text(p_texts->>'activity');
  v_phone text := public._ad_clean_text(p_texts->>'phone');
  v_style jsonb := '{}'::jsonb;
  s jsonb;
  v_font text;
  v_size numeric;
  v_color text;
  v_logo text := nullif(btrim(p_logo_url), '');
  v_ok_folder text;
begin
  if v_company = '' then raise exception 'text_required' using errcode = '22023'; end if;
  if char_length(v_company) > 40 or char_length(v_activity) > 60 or char_length(v_phone) > 25 then
    raise exception 'text_too_long' using errcode = '22023';
  end if;
  if v_phone <> '' and v_phone !~ '^[+0-9 ()\-]{5,25}$' then
    raise exception 'invalid_phone' using errcode = '22023';
  end if;
  foreach k in array array['company','activity','phone'] loop
    s := coalesce(p_style->k, '{}'::jsonb);
    v_font := coalesce(s->>'font', 'Montserrat');
    if v_font not in ('Montserrat','Inter','Roboto Condensed','Noto Sans','Noto Serif') then
      raise exception 'invalid_font' using errcode = '22023';
    end if;
    begin
      v_size := coalesce((s->>'size')::numeric, 1);
    exception when others then
      raise exception 'invalid_size' using errcode = '22023';
    end;
    if v_size < 0.6 or v_size > 1 then raise exception 'invalid_size' using errcode = '22023'; end if;
    v_color := upper(coalesce(s->>'color', case k when 'activity' then '#FFCC00' else '#FFFFFF' end));
    if v_color !~ '^#[0-9A-F]{6}$' then raise exception 'invalid_color' using errcode = '22023'; end if;
    v_style := v_style || jsonb_build_object(k, jsonb_build_object('font', v_font, 'size', round(v_size, 2), 'color', v_color));
  end loop;
  if v_logo is not null then
    v_ok_folder := p_owner::text || coalesce('|' || p_extra_owner::text, '');
    if p_owner is null or v_logo !~ ('/ads/requests/(' || v_ok_folder || ')/[^/]+\.(png|jpg|jpeg|webp)$') then
      raise exception 'invalid_logo' using errcode = '22023';
    end if;
  end if;
  if coalesce(p_logo_bg, 'dark') not in ('dark','light','none') then
    raise exception 'invalid_logo' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'version', 2,
    'template_id', p_template.id,
    'image_url', p_template.image_url,
    'texts', jsonb_build_object('company', v_company, 'activity', v_activity, 'phone', v_phone),
    'style', v_style,
    'logo_url', v_logo,
    'logo_bg', coalesce(p_logo_bg, 'dark'));
end;
$$;
revoke all on function public._ad_v2_creative_for(uuid, uuid, public.ad_templates, jsonb, jsonb, text, text) from public, anon, authenticated;

-- The customer version (used by create / update_my_ad_order_v2) now goes
-- through the same code → text cleaning everywhere.
create or replace function public._ad_v2_creative(
  p_template public.ad_templates, p_texts jsonb, p_style jsonb, p_logo_url text, p_logo_bg text
) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select public._ad_v2_creative_for(auth.uid(), null, p_template, p_texts, p_style, p_logo_url, p_logo_bg);
$$;
revoke all on function public._ad_v2_creative(public.ad_templates, jsonb, jsonb, text, text) from public, anon, authenticated;

-- 3) Customer order: no start date, route = countries -------------------------
create or replace function public.create_ad_order_v2(
  p_template uuid,
  p_texts jsonb,
  p_style jsonb,
  p_logo_url text,
  p_logo_bg text,
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
  v_creative jsonb;
  v_destination text := nullif(btrim(p_destination_url), '');
  v_today date := (now() at time zone 'Asia/Baku')::date;
  v_start date;
  v_from text;
  v_to text;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'account_blocked' using errcode = '42501'; end if;
  if not public.ads_ordering_enabled() then raise exception 'ordering_disabled' using errcode = '42501'; end if;

  select * into v_tpl from ad_templates where id = p_template and is_active and layout = 'standard_v2';
  if v_tpl.id is null then raise exception 'template_not_found' using errcode = 'P0002'; end if;
  v_creative := public._ad_v2_creative(v_tpl, p_texts, p_style, p_logo_url, p_logo_bg);

  if p_days not in (5, 15, 30) then raise exception 'invalid_duration' using errcode = '22023'; end if;
  select * into v_pkg from ad_packages where days = p_days and is_active and price > 0 order by sort, id limit 1;
  if v_pkg.id is null then raise exception 'package_not_found' using errcode = 'P0002'; end if;

  -- No date from the customer (new app) → today: the ad starts when the
  -- admin approves. An older cached app may still send a date — checked.
  v_start := coalesce(p_starts_on, v_today);
  if v_start < v_today or v_start > v_today + 90 then
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
  v_from := public._ad_route_code(p_route_from);
  v_to := public._ad_route_code(p_route_to);

  select id into v_company from companies where owner_user_id = auth.uid() order by created_at limit 1;
  insert into ad_orders (
    advertiser_id, company_id, package_id, package_name, days, price, currency,
    status, payment_status, title, image_url, destination_type, destination_url,
    target_countries, route_from, route_to, customer_note, template_id, creative, starts_on
  ) values (
    auth.uid(), v_company, v_pkg.id, v_pkg.name, v_pkg.days, v_pkg.price, v_pkg.currency,
    'pending_payment', 'unpaid', left(v_creative->'texts'->>'company', 100), v_tpl.image_url,
    p_destination_type, v_destination,
    coalesce(p_target_countries, '{}'), v_from, v_to,
    nullif(btrim(p_note), ''), v_tpl.id, v_creative, v_start
  ) returning * into v_order;
  return v_order;
end;
$$;

-- 4) Admin: edit an order or a published ad -----------------------------------
-- Changes the banner (background / texts / styles / logo), link, target
-- countries and route on the order AND on its ad(s); the run dates only
-- when the ad exists and both dates are given. Status and payment are
-- never touched. Every change is written to the admin log.
create or replace function public.admin_update_ad_order_v2(
  p_order uuid,
  p_template uuid,
  p_texts jsonb,
  p_style jsonb,
  p_logo_url text,
  p_logo_bg text,
  p_destination_type text,
  p_destination_url text,
  p_target_countries text[],
  p_route_from text,
  p_route_to text,
  p_starts timestamptz default null,
  p_ends timestamptz default null
)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old public.ad_orders;
  v_new public.ad_orders;
  v_tpl public.ad_templates;
  v_creative jsonb;
  v_destination text := nullif(btrim(p_destination_url), '');
  v_from text;
  v_to text;
  v_ads_before jsonb;
  v_tpl_found boolean;
begin
  perform public._require_admin();
  select * into v_old from ad_orders where id = p_order for update;
  if v_old.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if coalesce(v_old.creative->>'version', '') <> '2' then raise exception 'old_format' using errcode = '22023'; end if;

  -- background: an active standard template, or keep the current one
  -- (even if that template was switched off or deleted since).
  select * into v_tpl from ad_templates where id = p_template and is_active and layout = 'standard_v2';
  v_tpl_found := v_tpl.id is not null;
  if not v_tpl_found then
    if p_template is not null and p_template::text is distinct from v_old.creative->>'template_id' then
      raise exception 'template_not_found' using errcode = 'P0002';
    end if;
    v_tpl.id := nullif(v_old.creative->>'template_id', '')::uuid;
    v_tpl.image_url := v_old.creative->>'image_url';
  end if;
  v_creative := public._ad_v2_creative_for(v_old.advertiser_id, auth.uid(), v_tpl, p_texts, p_style, p_logo_url, p_logo_bg);

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
  v_from := public._ad_route_code(p_route_from);
  v_to := public._ad_route_code(p_route_to);
  if (p_starts is null) <> (p_ends is null) or (p_starts is not null and p_ends <= p_starts) then
    raise exception 'invalid_dates' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) into v_ads_before from ads a where a.order_id = p_order;

  update ad_orders set
    template_id = case when v_tpl_found then v_tpl.id else template_id end,
    creative = v_creative,
    image_url = v_creative->>'image_url',
    title = left(v_creative->'texts'->>'company', 100),
    destination_type = p_destination_type,
    destination_url = v_destination,
    target_countries = coalesce(p_target_countries, '{}'),
    route_from = v_from,
    route_to = v_to,
    updated_at = now()
  where id = p_order returning * into v_new;

  update ads set
    creative = v_creative,
    image_url = v_creative->>'image_url',
    title = left(v_creative->'texts'->>'company', 100),
    destination_type = p_destination_type,
    destination_url = v_destination,
    target_countries = coalesce(p_target_countries, '{}'),
    route_from = v_from,
    route_to = v_to,
    starts_at = coalesce(p_starts, starts_at),
    ends_at = coalesce(p_ends, ends_at),
    updated_at = now()
  where order_id = p_order;

  if p_starts is not null and exists (select 1 from ads where order_id = p_order) then
    update ad_orders set ad_starts_at = p_starts, ad_ends_at = p_ends where id = p_order returning * into v_new;
  end if;

  perform public._admin_log('ad_order.admin_edit', 'ad_order', p_order::text,
    jsonb_build_object('order', to_jsonb(v_old), 'ads', v_ads_before),
    jsonb_build_object('order', to_jsonb(v_new),
                       'ads', (select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from ads a where a.order_id = p_order)));
  return v_new;
end;
$$;

revoke all on function public.admin_update_ad_order_v2(uuid,uuid,jsonb,jsonb,text,text,text,text,text[],text,text,timestamptz,timestamptz) from public, anon;
grant execute on function public.admin_update_ad_order_v2(uuid,uuid,jsonb,jsonb,text,text,text,text,text[],text,text,timestamptz,timestamptz) to authenticated;
revoke all on function public.create_ad_order_v2(uuid,jsonb,jsonb,text,text,integer,date,text,text,text[],text,text,text) from public, anon;
grant execute on function public.create_ad_order_v2(uuid,jsonb,jsonb,text,text,integer,date,text,text,text[],text,text,text) to authenticated;

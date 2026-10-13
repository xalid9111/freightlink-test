-- =====================================================================
-- 0023 — Standard 1200×400 ad layout, customer fonts / sizes / colours,
--        order editing, "Reklam ver" switch, admin link / date control.
--
-- SAFE FORWARD MIGRATION (apply after 0022). Nothing is deleted:
--   * old 1350×300 templates are switched OFF (kept);
--   * old ads that are not in the new standard format are switched OFF
--     (kept, with their orders, payments and statistics);
--   * everything else only ADDS columns / functions / settings.
-- Re-runnable.
--
-- Fixed coordinates (1200×400) for EVERY template — drawn by the app:
--   logo circle (30,120) 160×160 · company (220,45) 440×85 ·
--   activity (220,150) 440×75 · phone (220,250) 440×70 · visual zone
--   (690,20) 490×360 stays free of text.
-- The creative stores only texts, styles and the logo — never positions.
-- =====================================================================

-- 1) Template / order / ad markers -----------------------------------------
alter table public.ad_templates add column if not exists layout text not null default 'custom';
alter table public.ad_orders add column if not exists edited_after_receipt_at timestamptz;

-- Old free-layout templates (made for 1350×300) are not offered any more.
update public.ad_templates set is_active = false, updated_at = now()
 where layout <> 'standard_v2' and is_active;

-- Ads that are not in the new standard format are not published any more.
update public.ads set is_active = false, updated_at = now()
 where is_active and coalesce(creative->>'version', '') <> '2';

-- 2) Images in the public "ads" bucket: only PNG / JPEG / WEBP --------------
update storage.buckets
   set allowed_mime_types = array['image/png','image/jpeg','image/webp']
 where id = 'ads';

-- 3) Second switch: show "Reklam ver" to customers (default OFF) -----------
create or replace function public.ads_ordering_enabled()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select (value->>'enabled')::boolean from platform_settings where key = 'ads_ordering'), false);
$$;

create or replace function public.admin_set_ads_ordering_enabled(p_enabled boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  insert into platform_settings (key, value) values ('ads_ordering', jsonb_build_object('enabled', coalesce(p_enabled, false)))
  on conflict (key) do update set value = excluded.value, updated_at = now();
  perform public._admin_log('ads_ordering.' || case when p_enabled then 'enable' else 'disable' end,
    'setting', 'ads_ordering', null, jsonb_build_object('enabled', p_enabled));
end;
$$;

-- 4) Creative validation (texts, styles, logo) -------------------------------
-- p_texts : {"company": "...", "activity": "...", "phone": "..."}
-- p_style : {"company": {"font": "...", "size": 0.6–1, "color": "#RRGGBB"}, "activity": {...}, "phone": {...}}
create or replace function public._ad_v2_creative(
  p_template public.ad_templates, p_texts jsonb, p_style jsonb, p_logo_url text, p_logo_bg text
) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  k text;
  v_company text := btrim(coalesce(p_texts->>'company', ''));
  v_activity text := btrim(coalesce(p_texts->>'activity', ''));
  v_phone text := btrim(coalesce(p_texts->>'phone', ''));
  v_style jsonb := '{}'::jsonb;
  s jsonb;
  v_font text;
  v_size numeric;
  v_color text;
  v_logo text := nullif(btrim(p_logo_url), '');
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
  if v_logo is not null and v_logo !~ ('/ads/requests/' || auth.uid()::text || '/[^/]+\.(png|jpg|jpeg|webp)$') then
    raise exception 'invalid_logo' using errcode = '22023';
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
revoke all on function public._ad_v2_creative(public.ad_templates, jsonb, jsonb, text, text) from public, anon, authenticated;

-- 5) Customer: create an order (standard layout) ------------------------------
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
    target_countries, route_from, route_to, customer_note, template_id, creative, starts_on
  ) values (
    auth.uid(), v_company, v_pkg.id, v_pkg.name, v_pkg.days, v_pkg.price, v_pkg.currency,
    'pending_payment', 'unpaid', left(v_creative->'texts'->>'company', 100), v_tpl.image_url,
    p_destination_type, v_destination,
    coalesce(p_target_countries, '{}'), nullif(btrim(p_route_from), ''), nullif(btrim(p_route_to), ''),
    nullif(btrim(p_note), ''), v_tpl.id, v_creative, p_starts_on
  ) returning * into v_order;
  return v_order;
end;
$$;

-- 6) Customer: edit own order until the admin approves it --------------------
-- Before the receipt: just saved. After the receipt: saved and flagged, the
-- order stays / goes back to "Yoxlanılır" for the admin. Approved or live
-- orders cannot be changed by the customer.
create or replace function public.update_my_ad_order_v2(
  p_order uuid, p_template uuid, p_texts jsonb, p_style jsonb, p_logo_url text, p_logo_bg text
)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.ad_orders; v_tpl public.ad_templates; v_creative jsonb; v_new public.ad_orders;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'account_blocked' using errcode = '42501'; end if;
  select * into v_old from ad_orders where id = p_order and advertiser_id = auth.uid() for update;
  if v_old.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_old.status not in ('pending_payment','awaiting_approval') or v_old.payment_status = 'paid' then
    raise exception 'order_locked' using errcode = '42501';
  end if;
  select * into v_tpl from ad_templates where id = p_template and is_active and layout = 'standard_v2';
  if v_tpl.id is null then raise exception 'template_not_found' using errcode = 'P0002'; end if;
  v_creative := public._ad_v2_creative(v_tpl, p_texts, p_style, p_logo_url, p_logo_bg);
  update ad_orders set
    template_id = v_tpl.id,
    creative = v_creative,
    image_url = v_tpl.image_url,
    title = left(v_creative->'texts'->>'company', 100),
    edited_after_receipt_at = case when receipt_path is not null then now() else edited_after_receipt_at end,
    status = case when receipt_path is not null then 'awaiting_approval' else status end,
    updated_at = now()
  where id = p_order returning * into v_new;
  return v_new;
end;
$$;

-- 7) Admin: standard templates, delete, ads link / dates ---------------------
create or replace function public.admin_save_ad_template_v2(
  p_id uuid, p_name text, p_image_url text, p_active boolean, p_sort integer default 100
)
returns public.ad_templates
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.ad_templates; v_row public.ad_templates;
begin
  perform public._require_admin();
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 80 then raise exception 'invalid_name' using errcode = '22023'; end if;
  if nullif(btrim(p_image_url), '') is null then raise exception 'invalid_image' using errcode = '22023'; end if;
  if p_id is null then
    -- fields / colours are kept only for older app versions; the layout is fixed.
    insert into ad_templates (name, image_url, fields, colors, logo, layout, is_active, sort)
    values (btrim(p_name), btrim(p_image_url),
            '[{"key":"company","label":"Şirkət adı","x":0.1833,"y":0.1125,"w":0.3667,"size":56,"max":40,"bold":true},
              {"key":"activity","label":"Fəaliyyət sahəsi","x":0.1833,"y":0.375,"w":0.3667,"size":40,"max":60},
              {"key":"phone","label":"Telefon","x":0.1833,"y":0.625,"w":0.3667,"size":40,"max":25}]'::jsonb,
            array['#FFFFFF'], '{"x":0.025,"y":0.3,"w":0.1333,"h":0.4}'::jsonb, 'standard_v2',
            coalesce(p_active, false), coalesce(p_sort, 100))
    returning * into v_row;
    perform public._admin_log('ad_template.create', 'ad_template', v_row.id::text, null, to_jsonb(v_row));
  else
    select * into v_old from ad_templates where id = p_id for update;
    if v_old.id is null then raise exception 'not_found'; end if;
    update ad_templates set name = btrim(p_name), image_url = btrim(p_image_url), layout = 'standard_v2',
           is_active = coalesce(p_active, is_active), sort = coalesce(p_sort, sort), updated_at = now()
     where id = p_id returning * into v_row;
    perform public._admin_log('ad_template.update', 'ad_template', p_id::text, to_jsonb(v_old), to_jsonb(v_row));
  end if;
  return v_row;
end;
$$;

-- Orders keep their own copy of the banner, so deleting a template never
-- changes an ordered or live ad.
create or replace function public.admin_delete_ad_template(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.ad_templates;
begin
  perform public._require_admin();
  select * into v_old from ad_templates where id = p_id;
  if v_old.id is null then raise exception 'not_found'; end if;
  delete from ad_templates where id = p_id;
  perform public._admin_log('ad_template.delete', 'ad_template', p_id::text, to_jsonb(v_old), null);
end;
$$;

create or replace function public.admin_update_ad_link_dates(
  p_ad uuid, p_destination_type text, p_destination_url text, p_starts timestamptz, p_ends timestamptz
)
returns public.ads
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.ads; v_row public.ads; v_url text := nullif(btrim(p_destination_url), '');
begin
  perform public._require_admin();
  select * into v_old from ads where id = p_ad for update;
  if v_old.id is null then raise exception 'not_found'; end if;
  if coalesce(p_destination_type, '') not in ('profile','external') then raise exception 'invalid_destination'; end if;
  if p_destination_type = 'external' and
     (v_url is null or v_url !~* '^https://([a-z0-9-]+\.)+[a-z0-9-]+(:[0-9]{1,5})?([/?#][^[:space:]]*)?$') then
    raise exception 'invalid_external_url';
  end if;
  if p_starts is null or p_ends is null or p_ends <= p_starts then raise exception 'invalid_dates'; end if;
  update ads set destination_type = p_destination_type,
                 destination_url = case when p_destination_type = 'external' then v_url else null end,
                 starts_at = p_starts, ends_at = p_ends, updated_at = now()
   where id = p_ad returning * into v_row;
  if v_row.order_id is not null then
    update ad_orders set ad_starts_at = p_starts, ad_ends_at = p_ends,
           destination_type = p_destination_type,
           destination_url = case when p_destination_type = 'external' then v_url else null end,
           updated_at = now()
     where id = v_row.order_id;
  end if;
  perform public._admin_log('ad.update_link_dates', 'ad', p_ad::text, to_jsonb(v_old), to_jsonb(v_row));
  return v_row;
end;
$$;

-- Re-activating an ad: only standard-format ads may go live again.
create or replace function public.admin_set_ad_active(p_ad uuid, p_active boolean)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old public.ads;
begin
  perform public._require_admin();
  select * into v_old from ads where id = p_ad;
  if v_old.id is null then raise exception 'not_found'; end if;
  if p_active and coalesce(v_old.creative->>'version', '') <> '2' then
    raise exception 'old_format' using errcode = '22023';
  end if;
  update ads set is_active = p_active, updated_at = now() where id = p_ad;
  perform public._admin_log(case when p_active then 'ad.activate' else 'ad.deactivate' end, 'ad', p_ad::text,
    jsonb_build_object('is_active', v_old.is_active), jsonb_build_object('is_active', p_active));
end;
$$;

-- 8) Home feed: only standard-format, paid, started ads ----------------------
create or replace function public.home_feed_ads()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select case when not public.home_ads_enabled() or auth.uid() is null then '[]'::jsonb else
    coalesce((
      select jsonb_agg(to_jsonb(a) order by a.created_at)
      from ads a
      join ad_orders o on o.id = a.order_id
      where a.is_active and now() >= a.starts_at and now() < a.ends_at
        and o.payment_status = 'paid'
        and a.creative->>'version' = '2'
        and not public.is_blocked(a.advertiser_id)
    ), '[]'::jsonb)
  end;
$$;

-- 9) Privileges ----------------------------------------------------------------
revoke all on function public.ads_ordering_enabled() from public, anon;
revoke all on function public.admin_set_ads_ordering_enabled(boolean) from public, anon;
revoke all on function public.create_ad_order_v2(uuid,jsonb,jsonb,text,text,integer,date,text,text,text[],text,text,text) from public, anon;
revoke all on function public.update_my_ad_order_v2(uuid,uuid,jsonb,jsonb,text,text) from public, anon;
revoke all on function public.admin_save_ad_template_v2(uuid,text,text,boolean,integer) from public, anon;
revoke all on function public.admin_delete_ad_template(uuid) from public, anon;
revoke all on function public.admin_update_ad_link_dates(uuid,text,text,timestamptz,timestamptz) from public, anon;
revoke all on function public.admin_set_ad_active(uuid,boolean) from public, anon;
revoke all on function public.home_feed_ads() from public, anon;
grant execute on function public.ads_ordering_enabled() to authenticated;
grant execute on function public.admin_set_ads_ordering_enabled(boolean) to authenticated;
grant execute on function public.create_ad_order_v2(uuid,jsonb,jsonb,text,text,integer,date,text,text,text[],text,text,text) to authenticated;
grant execute on function public.update_my_ad_order_v2(uuid,uuid,jsonb,jsonb,text,text) to authenticated;
grant execute on function public.admin_save_ad_template_v2(uuid,text,text,boolean,integer) to authenticated;
grant execute on function public.admin_delete_ad_template(uuid) to authenticated;
grant execute on function public.admin_update_ad_link_dates(uuid,text,text,timestamptz,timestamptz) to authenticated;
grant execute on function public.admin_set_ad_active(uuid,boolean) to authenticated;
grant execute on function public.home_feed_ads() to authenticated;

-- 10) The 0021/0022 free-layout order function is retired: new orders must use
--     the standard layout (create_ad_order_v2). Kept as a stub so an old
--     cached app gets a clear error instead of creating an unpublishable ad.
create or replace function public.create_ad_order_from_template(
  p_template uuid, p_texts jsonb, p_color text, p_days integer, p_starts_on date,
  p_destination_type text default 'profile', p_destination_url text default null,
  p_target_countries text[] default '{}', p_route_from text default null, p_route_to text default null,
  p_note text default null, p_logo_url text default null
) returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  raise exception 'use_new_editor' using errcode = '22023';
end;
$$;

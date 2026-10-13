-- =====================================================================
-- 0022 — Customer logo on ad templates.
-- SAFE FORWARD MIGRATION (apply after 0021): adds one nullable column and
-- replaces three functions. No order, ad or payment is changed. Re-runnable.
--
-- The admin can give a template a logo place (x, y, w, h as parts of the
-- 1350×300 banner). The customer then uploads a logo (their own folder in
-- the public "ads" bucket, allowed since 0020) and it is drawn there.
-- =====================================================================

alter table public.ad_templates add column if not exists logo jsonb;

create or replace function public._ad_template_logo_ok(p jsonb)
returns boolean language plpgsql immutable set search_path = public, pg_temp as $$
begin
  if p is null or jsonb_typeof(p) = 'null' then return true; end if;
  if jsonb_typeof(p) <> 'object' then return false; end if;
  return coalesce((p->>'x')::numeric, -1) between 0 and 1
     and coalesce((p->>'y')::numeric, -1) between 0 and 1
     and coalesce((p->>'w')::numeric, -1) between 0.03 and 1
     and coalesce((p->>'h')::numeric, -1) between 0.05 and 1;
exception when others then
  return false;
end;
$$;

-- Old 11-parameter version is replaced by one with an optional logo.
drop function if exists public.create_ad_order_from_template(uuid,jsonb,text,integer,date,text,text,text[],text,text,text);

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
  p_note text default null,
  p_logo_url text default null
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
  v_logo text := nullif(btrim(p_logo_url), '');
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

  -- Logo: only for templates with a logo place, only an image the customer
  -- uploaded into their own folder (ads/requests/<user id>/…).
  if v_tpl.logo is null then
    v_logo := null;
  elsif v_logo is not null and v_logo !~ ('/ads/requests/' || auth.uid()::text || '/[^/]+$') then
    raise exception 'invalid_logo' using errcode = '22023';
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
                       'fields', v_tpl.fields, 'texts', v_texts, 'color', upper(p_color),
                       'logo', v_tpl.logo, 'logo_url', v_logo),
    p_starts_on
  ) returning * into v_order;
  return v_order;
end;
$$;


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
  if not public._ad_template_logo_ok(p_data->'logo') then raise exception 'invalid_logo' using errcode = '22023'; end if;
  if p_id is null then
    insert into ad_templates (name, image_url, fields, colors, logo, is_active, sort)
    values (btrim(p_data->>'name'), btrim(p_data->>'image_url'), p_data->'fields', v_colors,
            nullif(p_data->'logo', 'null'::jsonb),
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
      logo = nullif(p_data->'logo', 'null'::jsonb),
      is_active = coalesce((p_data->>'is_active')::boolean, is_active),
      sort = coalesce((p_data->>'sort')::integer, sort),
      updated_at = now()
    where id = p_id returning * into v_row;
    perform public._admin_log('ad_template.update', 'ad_template', p_id::text, to_jsonb(v_old), to_jsonb(v_row));
  end if;
  return v_row;
end;
$$;


revoke all on function public.create_ad_order_from_template(uuid,jsonb,text,integer,date,text,text,text[],text,text,text,text) from public, anon;
grant execute on function public.create_ad_order_from_template(uuid,jsonb,text,integer,date,text,text,text[],text,text,text,text) to authenticated;
revoke all on function public.admin_save_ad_template(uuid,jsonb) from public, anon;
grant execute on function public.admin_save_ad_template(uuid,jsonb) to authenticated;

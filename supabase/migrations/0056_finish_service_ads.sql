-- =====================================================================
-- 0056 — Finish 0029 (service ads) on the live database (owner, 21.10.2026)
--
-- The owner's check showed 0029 had only partly applied on the live
-- database (0038 already restored admin_set_ad_template_audience; 0032
-- re-created create_service_ad_order). Still missing: ad_orders.service_id,
-- 'service' as an allowed destination_type, and the 0029 version of
-- admin_update_ad_order_v2 (a service ad keeps leading to its service).
-- Re-running the whole 0029 would put back older versions of functions
-- that later migrations replaced, so this file contains ONLY those parts,
-- copied unchanged from 0029.
--
-- Safe: forward-only, re-runnable. A new nullable column, two checks
-- widened (old values stay valid), one function re-created with the same
-- signature. No row is changed or deleted.
-- =====================================================================

alter table public.ad_orders add column if not exists service_id uuid references public.service_providers(id) on delete set null;

-- destination_type: + 'service'
alter table public.ad_orders drop constraint if exists ad_orders_destination_type_check;
alter table public.ad_orders add constraint ad_orders_destination_type_check
  check (destination_type in ('profile','external','service'));
alter table public.ads drop constraint if exists ads_destination_type_check;
alter table public.ads add constraint ads_destination_type_check
  check (destination_type in ('profile','external','service'));

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

  -- 0029: a service ad always leads to its service page — keep it.
  if v_old.destination_type = 'service' then
    p_destination_type := 'service';
    v_destination := v_old.destination_url;
  elsif coalesce(p_destination_type, '') not in ('profile','external') then
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

notify pgrst, 'reload schema';

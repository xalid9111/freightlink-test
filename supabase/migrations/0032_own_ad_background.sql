-- =====================================================================
-- 0032 — Service ads: the customer's own picture as the ad background
--
-- * ad_templates.owner_id: NULL = admin template (as before). A value =
--   a private background uploaded by that user; only he (and admins) can
--   see it, it is never shown in the admin's template list or to others.
-- * create_own_ad_background(p_image_url): the picture must already be in
--   the user's own upload folder of the "ads" bucket
--   (ads/requests/<user id>/…, the same folder used for logos). It becomes
--   a private, active 1200×400 template for service ads, so the whole
--   existing order flow (prices, receipt, admin check) stays the same.
-- * create_service_ad_order: also refuses another user's private
--   background.
--
-- Safe: forward-only, re-runnable. One new nullable column; the read
-- policy is replaced with the same rule plus "private ones only for their
-- owner". No row is changed or deleted.
-- =====================================================================

alter table public.ad_templates
  add column if not exists owner_id uuid references public.users (id) on delete cascade;
create index if not exists ad_templates_owner_idx on public.ad_templates (owner_id) where owner_id is not null;

drop policy if exists "ad_templates_read" on public.ad_templates;
create policy "ad_templates_read" on public.ad_templates
  for select to authenticated
  using (public.is_admin() or (is_active and (owner_id is null or owner_id = auth.uid())));

create or replace function public.create_own_ad_background(p_image_url text)
returns public.ad_templates
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_url text := btrim(coalesce(p_image_url, ''));
  v_row public.ad_templates;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(v_uid) then raise exception 'account_blocked' using errcode = '42501'; end if;
  if not public.ads_ordering_enabled() then raise exception 'ordering_disabled' using errcode = '42501'; end if;
  if v_url !~ ('^https://[^[:space:]]+/storage/v1/object/public/ads/requests/' || v_uid::text || '/[^/[:space:]]+\.(png|jpg|jpeg|webp)$') then
    raise exception 'invalid_image' using errcode = '22023';
  end if;
  -- Keep it tidy: at most 20 own backgrounds per user.
  if (select count(*) from ad_templates where owner_id = v_uid) >= 20 then
    raise exception 'too_many_backgrounds' using errcode = '54000';
  end if;
  insert into ad_templates (name, image_url, fields, colors, is_active, sort, layout, audience, owner_id)
  values ('Öz şəklim', v_url, '[]'::jsonb, array['#FFFFFF'], true, 1000, 'standard_v2', 'service', v_uid)
  returning * into v_row;
  return v_row;
end;
$$;

revoke all on function public.create_own_ad_background(text) from public, anon;
grant execute on function public.create_own_ad_background(text) to authenticated;

-- Same as 0029, plus: a private background may only be used by its owner.
create or replace function public.create_service_ad_order(
  p_service uuid,
  p_template uuid,
  p_texts jsonb,
  p_style jsonb,
  p_logo_url text,
  p_logo_bg text,
  p_days integer,
  p_target_countries text[] default '{}',
  p_note text default null
)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_svc public.service_providers; v_order public.ad_orders;
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_svc from service_providers where id = p_service;
  if v_svc.id is null or v_svc.owner_id is distinct from auth.uid() then
    raise exception 'service_not_found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from ad_templates where id = p_template and is_active and layout = 'standard_v2'
                   and audience in ('service','all')
                   and (owner_id is null or owner_id = auth.uid())) then
    raise exception 'template_not_found' using errcode = 'P0002';
  end if;
  v_order := public.create_ad_order_v2(p_template, p_texts, p_style, p_logo_url, p_logo_bg, p_days, null,
                                       'profile', null, p_target_countries, null, null, p_note);
  update ad_orders set destination_type = 'service', destination_url = p_service::text, service_id = p_service
   where id = v_order.id returning * into v_order;
  return v_order;
end;
$$;

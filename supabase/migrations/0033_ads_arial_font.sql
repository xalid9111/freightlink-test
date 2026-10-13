-- =====================================================================
-- 0033 — Ads: accept the "Arial" font
--
-- The app now uses only Arial and sends font "Arial" for every ad text,
-- but the server still allowed only the old five fonts, so every new ad
-- order (and ad edit) failed with "invalid_font" ("Olmadı. Tekrar
-- deneyin."). Same function as 0024, with 'Arial' added to the allowed
-- list and used as the default. Old values stay valid.
--
-- Safe: forward-only, re-runnable, no table or row is changed.
-- =====================================================================

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
    v_font := coalesce(s->>'font', 'Arial');
    -- 'Arial' = the app's only font now (older ads keep their font name).
    if v_font not in ('Arial','Montserrat','Inter','Roboto Condensed','Noto Sans','Noto Serif') then
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

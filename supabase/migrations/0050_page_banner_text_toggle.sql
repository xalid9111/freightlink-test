-- =====================================================================
-- 0050 — Banner: show the texts or only the picture (owner, 21.10.2026)
--
-- A banner picture can already carry its own writing. show_text = false
-- shows only the picture (no app title / subtitle on top of it). Default
-- true = as before.
--
-- admin_set_page_hero gets a 7th parameter p_show_text (a new overload;
-- the 0049 six-parameter version stays and keeps the current setting).
--
-- Safe: forward-only, re-runnable. Two new columns (default true), one
-- new function; nothing is changed or deleted.
-- =====================================================================

alter table public.market_hero add column if not exists show_text boolean not null default true;
alter table public.services_hero add column if not exists show_text boolean not null default true;

create or replace function public.admin_set_page_hero(
  p_page text, p_image_url text, p_image_url_day text, p_title text, p_title_accent text, p_subtitle text,
  p_show_text boolean)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb; v_new jsonb;
begin
  perform public._require_admin();
  if p_page = 'market' then
    select to_jsonb(h) into v_old from market_hero h where id = 1;
    insert into market_hero (id, image_url, image_url_day, title, title_accent, subtitle, show_text, updated_at, updated_by)
    values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_image_url_day), ''), nullif(btrim(p_title), ''),
            nullif(btrim(p_title_accent), ''), nullif(btrim(p_subtitle), ''), coalesce(p_show_text, true), now(), auth.uid())
    on conflict (id) do update
       set image_url = excluded.image_url, image_url_day = excluded.image_url_day, title = excluded.title,
           title_accent = excluded.title_accent, subtitle = excluded.subtitle, show_text = excluded.show_text,
           updated_at = now(), updated_by = auth.uid();
    select to_jsonb(h) into v_new from market_hero h where id = 1;
  elsif p_page = 'services' then
    select to_jsonb(h) into v_old from services_hero h where id = 1;
    insert into services_hero (id, image_url, image_url_day, title, title_accent, subtitle, show_text, updated_at, updated_by)
    values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_image_url_day), ''), nullif(btrim(p_title), ''),
            nullif(btrim(p_title_accent), ''), nullif(btrim(p_subtitle), ''), coalesce(p_show_text, true), now(), auth.uid())
    on conflict (id) do update
       set image_url = excluded.image_url, image_url_day = excluded.image_url_day, title = excluded.title,
           title_accent = excluded.title_accent, subtitle = excluded.subtitle, show_text = excluded.show_text,
           updated_at = now(), updated_by = auth.uid();
    select to_jsonb(h) into v_new from services_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
  return v_new;
end $$;
revoke all on function public.admin_set_page_hero(text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.admin_set_page_hero(text, text, text, text, text, text, boolean) to authenticated;

notify pgrst, 'reload schema';

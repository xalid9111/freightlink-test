-- =====================================================================
-- 0052 — Banner: zoom into the picture (owner, 21.10.2026)
--
-- A picture as wide as the banner cannot be moved left / right. With a
-- zoom (1 = whole width, up to 3) the admin enlarges it and then drags it
-- to the part to show (0051). Stored per picture (night / day).
--
-- admin_set_page_hero_zoom(page, night zoom, day zoom): admins only,
-- logged. Other banner functions stay as they are.
--
-- Safe: forward-only, re-runnable. Two new columns per banner table
-- (default 1 = as now), one new function; nothing is deleted.
-- =====================================================================

alter table public.market_hero add column if not exists zoom real not null default 1 check (zoom between 1 and 3);
alter table public.market_hero add column if not exists zoom_day real not null default 1 check (zoom_day between 1 and 3);
alter table public.services_hero add column if not exists zoom real not null default 1 check (zoom between 1 and 3);
alter table public.services_hero add column if not exists zoom_day real not null default 1 check (zoom_day between 1 and 3);

create or replace function public.admin_set_page_hero_zoom(p_page text, p_zoom real, p_zoom_day real)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb; v_new jsonb;
  z real := greatest(1, least(3, coalesce(p_zoom, 1)));
  zd real := greatest(1, least(3, coalesce(p_zoom_day, 1)));
begin
  perform public._require_admin();
  if p_page = 'market' then
    insert into market_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from market_hero h where id = 1;
    update market_hero set zoom = z, zoom_day = zd, updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from market_hero h where id = 1;
  elsif p_page = 'services' then
    insert into services_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from services_hero h where id = 1;
    update services_hero set zoom = z, zoom_day = zd, updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from services_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
end $$;
revoke all on function public.admin_set_page_hero_zoom(text, real, real) from public, anon;
grant execute on function public.admin_set_page_hero_zoom(text, real, real) to authenticated;

notify pgrst, 'reload schema';

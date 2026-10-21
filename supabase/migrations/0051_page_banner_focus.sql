-- =====================================================================
-- 0051 — Banner: which part of the picture is in front (owner, 21.10.2026)
--
-- A banner is wider than most pictures, so a part is cut off. The admin
-- taps the part to keep in view; it is stored per picture (night / day)
-- as a point from -1 (left / top) to 1 (right / bottom); 0,0 = middle.
--
-- admin_set_page_hero_focus(page, night x, night y, day x, day y): admins
-- only, logged. The other banner functions stay as they are.
--
-- Safe: forward-only, re-runnable. Four new columns per banner table
-- (default 0 = middle, as now), one new function; nothing is deleted.
-- =====================================================================

alter table public.market_hero add column if not exists focus_x real not null default 0 check (focus_x between -1 and 1);
alter table public.market_hero add column if not exists focus_y real not null default 0 check (focus_y between -1 and 1);
alter table public.market_hero add column if not exists focus_day_x real not null default 0 check (focus_day_x between -1 and 1);
alter table public.market_hero add column if not exists focus_day_y real not null default 0 check (focus_day_y between -1 and 1);
alter table public.services_hero add column if not exists focus_x real not null default 0 check (focus_x between -1 and 1);
alter table public.services_hero add column if not exists focus_y real not null default 0 check (focus_y between -1 and 1);
alter table public.services_hero add column if not exists focus_day_x real not null default 0 check (focus_day_x between -1 and 1);
alter table public.services_hero add column if not exists focus_day_y real not null default 0 check (focus_day_y between -1 and 1);

create or replace function public.admin_set_page_hero_focus(
  p_page text, p_x real, p_y real, p_day_x real, p_day_y real)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb; v_new jsonb;
  c real[] := array[
    greatest(-1, least(1, coalesce(p_x, 0))), greatest(-1, least(1, coalesce(p_y, 0))),
    greatest(-1, least(1, coalesce(p_day_x, 0))), greatest(-1, least(1, coalesce(p_day_y, 0)))];
begin
  perform public._require_admin();
  if p_page = 'market' then
    insert into market_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from market_hero h where id = 1;
    update market_hero set focus_x = c[1], focus_y = c[2], focus_day_x = c[3], focus_day_y = c[4],
           updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from market_hero h where id = 1;
  elsif p_page = 'services' then
    insert into services_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from services_hero h where id = 1;
    update services_hero set focus_x = c[1], focus_y = c[2], focus_day_x = c[3], focus_day_y = c[4],
           updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from services_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
end $$;
revoke all on function public.admin_set_page_hero_focus(text, real, real, real, real) from public, anon;
grant execute on function public.admin_set_page_hero_focus(text, real, real, real, real) to authenticated;

notify pgrst, 'reload schema';

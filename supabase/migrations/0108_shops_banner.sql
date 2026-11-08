-- =====================================================================
-- 0108 — Mağazalar gets its own map banner (owner, 08.11.2026)
--
-- Servislər and Mağazalar are the same map screen (Mağazalar = the shops
-- filter, /services?shops=1) and both showed the Servislər banner
-- (services_hero). Now Mağazalar has its own banner: shops_hero, the same
-- columns as services_hero / tirpark_hero (night / day picture, texts,
-- show text, place, zoom). The banner functions of 0078 also accept
-- 'shops'; their 'market', 'services' and 'tirpark' parts are unchanged
-- (admins only, every change in the Audit Log). Read like the other
-- banners: signed-in users and visitors (0107).
--
-- Safe: forward-only, re-runnable. One new table (empty until the admin
-- saves a banner; the app shows a shop picture meanwhile) and three
-- functions replaced with one more branch. Nothing is deleted; the
-- Servislər and TIRPark banners stay as they are.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.services_hero') is null or to_regclass('public.tirpark_hero') is null then
    raise exception '0108: run 0049–0052 and 0078 first — nothing changed';
  end if;
end $$;

create table if not exists public.shops_hero (
  id smallint primary key default 1 check (id = 1),
  image_url text check (image_url is null or char_length(image_url) <= 1000),
  image_url_day text check (image_url_day is null or char_length(image_url_day) <= 1000),
  title text check (title is null or char_length(title) <= 80),
  title_accent text check (title_accent is null or char_length(title_accent) <= 80),
  subtitle text check (subtitle is null or char_length(subtitle) <= 160),
  show_text boolean not null default true,
  focus_x real not null default 0 check (focus_x between -1 and 1),
  focus_y real not null default 0 check (focus_y between -1 and 1),
  focus_day_x real not null default 0 check (focus_day_x between -1 and 1),
  focus_day_y real not null default 0 check (focus_day_y between -1 and 1),
  zoom real not null default 1 check (zoom between 1 and 3),
  zoom_day real not null default 1 check (zoom_day between 1 and 3),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
alter table public.shops_hero enable row level security;
revoke all on public.shops_hero from anon, authenticated;
grant select on public.shops_hero to authenticated, anon;
drop policy if exists "shops_hero_read" on public.shops_hero;
create policy "shops_hero_read" on public.shops_hero for select to authenticated using (true);
drop policy if exists "shops_hero_read_guest" on public.shops_hero;
create policy "shops_hero_read_guest" on public.shops_hero for select to anon using (true);

-- The banner functions of 0078, now also for 'shops'.
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
  elsif p_page = 'tirpark' then
    select to_jsonb(h) into v_old from tirpark_hero h where id = 1;
    insert into tirpark_hero (id, image_url, image_url_day, title, title_accent, subtitle, show_text, updated_at, updated_by)
    values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_image_url_day), ''), nullif(btrim(p_title), ''),
            nullif(btrim(p_title_accent), ''), nullif(btrim(p_subtitle), ''), coalesce(p_show_text, true), now(), auth.uid())
    on conflict (id) do update
       set image_url = excluded.image_url, image_url_day = excluded.image_url_day, title = excluded.title,
           title_accent = excluded.title_accent, subtitle = excluded.subtitle, show_text = excluded.show_text,
           updated_at = now(), updated_by = auth.uid();
    select to_jsonb(h) into v_new from tirpark_hero h where id = 1;
  elsif p_page = 'shops' then
    select to_jsonb(h) into v_old from shops_hero h where id = 1;
    insert into shops_hero (id, image_url, image_url_day, title, title_accent, subtitle, show_text, updated_at, updated_by)
    values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_image_url_day), ''), nullif(btrim(p_title), ''),
            nullif(btrim(p_title_accent), ''), nullif(btrim(p_subtitle), ''), coalesce(p_show_text, true), now(), auth.uid())
    on conflict (id) do update
       set image_url = excluded.image_url, image_url_day = excluded.image_url_day, title = excluded.title,
           title_accent = excluded.title_accent, subtitle = excluded.subtitle, show_text = excluded.show_text,
           updated_at = now(), updated_by = auth.uid();
    select to_jsonb(h) into v_new from shops_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
  return v_new;
end $$;
revoke all on function public.admin_set_page_hero(text, text, text, text, text, text, boolean) from public, anon;
grant execute on function public.admin_set_page_hero(text, text, text, text, text, text, boolean) to authenticated;

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
  elsif p_page = 'tirpark' then
    insert into tirpark_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from tirpark_hero h where id = 1;
    update tirpark_hero set focus_x = c[1], focus_y = c[2], focus_day_x = c[3], focus_day_y = c[4],
           updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from tirpark_hero h where id = 1;
  elsif p_page = 'shops' then
    insert into shops_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from shops_hero h where id = 1;
    update shops_hero set focus_x = c[1], focus_y = c[2], focus_day_x = c[3], focus_day_y = c[4],
           updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from shops_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
end $$;
revoke all on function public.admin_set_page_hero_focus(text, real, real, real, real) from public, anon;
grant execute on function public.admin_set_page_hero_focus(text, real, real, real, real) to authenticated;

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
  elsif p_page = 'tirpark' then
    insert into tirpark_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from tirpark_hero h where id = 1;
    update tirpark_hero set zoom = z, zoom_day = zd, updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from tirpark_hero h where id = 1;
  elsif p_page = 'shops' then
    insert into shops_hero (id) values (1) on conflict (id) do nothing;
    select to_jsonb(h) into v_old from shops_hero h where id = 1;
    update shops_hero set zoom = z, zoom_day = zd, updated_at = now(), updated_by = auth.uid() where id = 1;
    select to_jsonb(h) into v_new from shops_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
end $$;
revoke all on function public.admin_set_page_hero_zoom(text, real, real) from public, anon;
grant execute on function public.admin_set_page_hero_zoom(text, real, real) to authenticated;

notify pgrst, 'reload schema';

commit;

-- =====================================================================
-- 0049 — Page banners with a night and a day picture (owner, 21.10.2026)
--
-- * TIR Bazarı banner (market_hero, 0044) gets a second picture for the
--   day theme: image_url_day. The current picture stays the night one.
-- * New banner on the Services page: services_hero (one row), same texts,
--   a night and a day picture.
-- * admin_set_page_hero('market' | 'services', night, day, title, accent,
--   subtitle): admins only (checked on the server), logged. The 0044
--   function admin_market_set_hero stays as it was (it keeps the day
--   picture when it saves).
--
-- Safe: forward-only, re-runnable. One new column, one new table, one new
-- function; no row is deleted; existing pictures and texts stay.
-- =====================================================================

alter table public.market_hero add column if not exists image_url_day text
  constraint market_hero_image_url_day_len check (image_url_day is null or char_length(image_url_day) <= 1000);

create table if not exists public.services_hero (
  id smallint primary key default 1 check (id = 1),
  image_url text check (image_url is null or char_length(image_url) <= 1000),
  image_url_day text check (image_url_day is null or char_length(image_url_day) <= 1000),
  title text check (title is null or char_length(title) <= 80),
  title_accent text check (title_accent is null or char_length(title_accent) <= 80),
  subtitle text check (subtitle is null or char_length(subtitle) <= 160),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
alter table public.services_hero enable row level security;
revoke all on public.services_hero from anon, authenticated;
grant select on public.services_hero to authenticated;
drop policy if exists "services_hero_read" on public.services_hero;
create policy "services_hero_read" on public.services_hero for select to authenticated using (true);

create or replace function public.admin_set_page_hero(
  p_page text, p_image_url text, p_image_url_day text, p_title text, p_title_accent text, p_subtitle text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb; v_new jsonb;
begin
  perform public._require_admin();
  if p_page = 'market' then
    select to_jsonb(h) into v_old from market_hero h where id = 1;
    insert into market_hero (id, image_url, image_url_day, title, title_accent, subtitle, updated_at, updated_by)
    values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_image_url_day), ''), nullif(btrim(p_title), ''),
            nullif(btrim(p_title_accent), ''), nullif(btrim(p_subtitle), ''), now(), auth.uid())
    on conflict (id) do update
       set image_url = excluded.image_url, image_url_day = excluded.image_url_day, title = excluded.title,
           title_accent = excluded.title_accent, subtitle = excluded.subtitle, updated_at = now(), updated_by = auth.uid();
    select to_jsonb(h) into v_new from market_hero h where id = 1;
  elsif p_page = 'services' then
    select to_jsonb(h) into v_old from services_hero h where id = 1;
    insert into services_hero (id, image_url, image_url_day, title, title_accent, subtitle, updated_at, updated_by)
    values (1, nullif(btrim(p_image_url), ''), nullif(btrim(p_image_url_day), ''), nullif(btrim(p_title), ''),
            nullif(btrim(p_title_accent), ''), nullif(btrim(p_subtitle), ''), now(), auth.uid())
    on conflict (id) do update
       set image_url = excluded.image_url, image_url_day = excluded.image_url_day, title = excluded.title,
           title_accent = excluded.title_accent, subtitle = excluded.subtitle, updated_at = now(), updated_by = auth.uid();
    select to_jsonb(h) into v_new from services_hero h where id = 1;
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
  return v_new;
end $$;
revoke all on function public.admin_set_page_hero(text, text, text, text, text, text) from public, anon;
grant execute on function public.admin_set_page_hero(text, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';

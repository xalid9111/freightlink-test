-- =====================================================================
-- 0078 — TIRPark PR 2: comments (rating) and pictures (owner, 31.10.2026)
--
-- * tir_park_reviews: one comment per user and park — 1…5 stars and a
--   text (optional); the author changes or deletes it, an admin deletes
--   any. Only on approved parks. Readable by everybody signed in who sees
--   the park. The park's rating_avg / rating_count are recalculated by the
--   server after every change (the only way they change, see 0077 guard).
-- * Pictures: tir_park_set_photos(park, urls) — admins only (owner,
--   31.10.2026: "düzəlişləri sadəcə adminlər edəcək") set the list (add /
--   replace / delete / order, at most 10), logged.
-- * TIRPark page banner (tirpark_hero): the admin changes its night / day
--   picture (a GIF too), place, zoom and texts with the existing banner
--   editor — admin_set_page_hero / _focus / _zoom also take 'tirpark'
--   ('market' and 'services' work exactly as before).
--   Files are stored in the existing public bucket profile-media, in the
--   uploader's own folder (policies of 0031); only links from that bucket
--   are accepted.
--
-- Safe: forward-only, re-runnable. One new table, new functions. No
-- existing row is changed or deleted (tir_parks rows only get their
-- rating / pictures through these functions).
-- =====================================================================

begin;

create table if not exists public.tir_park_reviews (
  id uuid primary key default gen_random_uuid(),
  park_id uuid not null references public.tir_parks(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (park_id, user_id)
);
create index if not exists tir_park_reviews_park_idx on public.tir_park_reviews (park_id, created_at desc);

alter table public.tir_park_reviews enable row level security;
revoke all on public.tir_park_reviews from anon, authenticated;
grant select, insert, update, delete on public.tir_park_reviews to authenticated;

-- Seen with the park (approved parks; one's own; admins all).
drop policy if exists "tir_park_reviews_select" on public.tir_park_reviews;
create policy "tir_park_reviews_select" on public.tir_park_reviews
  for select to authenticated
  using (exists (select 1 from public.tir_parks p where p.id = park_id
                  and (p.status = 'approved' or p.created_by = auth.uid() or public.is_admin())));

-- Writing: one's own comment, on an approved park, not while blocked.
drop policy if exists "tir_park_reviews_insert" on public.tir_park_reviews;
create policy "tir_park_reviews_insert" on public.tir_park_reviews
  for insert to authenticated
  with check (user_id = auth.uid() and not public.is_blocked(auth.uid())
              and exists (select 1 from public.tir_parks p where p.id = park_id and p.status = 'approved'));
drop policy if exists "tir_park_reviews_update" on public.tir_park_reviews;
create policy "tir_park_reviews_update" on public.tir_park_reviews
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
drop policy if exists "tir_park_reviews_delete" on public.tir_park_reviews;
create policy "tir_park_reviews_delete" on public.tir_park_reviews
  for delete to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- The park and the author of a comment never change; the time moves.
create or replace function public.tir_park_reviews_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.park_id := old.park_id;
  new.user_id := old.user_id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists tir_park_reviews_guard on public.tir_park_reviews;
create trigger tir_park_reviews_guard before update on public.tir_park_reviews
  for each row execute function public.tir_park_reviews_guard();

-- rating_avg / rating_count of the park after any change of its comments.
create or replace function public.tir_park_recalc_rating()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_park uuid := coalesce(new.park_id, old.park_id);
begin
  perform set_config('app.tir_park_rating', 'on', true);
  update tir_parks p
     set rating_avg = coalesce((select round(avg(r.rating)::numeric, 2) from tir_park_reviews r where r.park_id = v_park), 0),
         rating_count = (select count(*) from tir_park_reviews r where r.park_id = v_park)
   where p.id = v_park;
  perform set_config('app.tir_park_rating', 'off', true);
  return null;
end $$;
drop trigger if exists tir_park_reviews_rating on public.tir_park_reviews;
create trigger tir_park_reviews_rating after insert or update or delete on public.tir_park_reviews
  for each row execute function public.tir_park_recalc_rating();

-- Comments of a park with the writer's public name and picture.
create or replace function public.tir_park_reviews_list(p_park uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not exists (select 1 from tir_parks p where p.id = p_park
                  and (p.status = 'approved' or p.created_by = auth.uid() or public.is_admin())) then
    return '[]'::jsonb;
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', r.id, 'user_id', r.user_id, 'rating', r.rating, 'comment', r.comment,
             'created_at', r.created_at, 'updated_at', r.updated_at,
             'name', u.full_name, 'avatar_url', u.avatar_url) order by r.created_at desc)
      from tir_park_reviews r
      left join users u on u.id = r.user_id
     where r.park_id = p_park), '[]'::jsonb);
end $$;
revoke all on function public.tir_park_reviews_list(uuid) from public, anon;
grant execute on function public.tir_park_reviews_list(uuid) to authenticated;

-- Pictures: admins only set the list (≤ 10 links from the profile-media
-- bucket), logged.
create or replace function public.tir_park_set_photos(p_park uuid, p_urls text[])
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_park tir_parks;
  v_url text;
begin
  perform public._require_admin();
  select * into v_park from tir_parks where id = p_park;
  if v_park.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  if cardinality(coalesce(p_urls, '{}')) > 10 then raise exception 'too_many' using errcode = '54000'; end if;
  foreach v_url in array coalesce(p_urls, '{}') loop
    if v_url is null or char_length(v_url) > 1000 or v_url !~ '^https://[^ ]+/storage/v1/object/public/profile-media/' then
      raise exception 'invalid_url' using errcode = '22023';
    end if;
  end loop;
  update tir_parks set photo_urls = coalesce(p_urls, '{}') where id = p_park;
  perform public._admin_log('tir_park.photos', 'tir_parks', p_park::text,
    jsonb_build_object('photo_urls', v_park.photo_urls), jsonb_build_object('photo_urls', p_urls));
end $$;
revoke all on function public.tir_park_set_photos(uuid, text[]) from public, anon;
grant execute on function public.tir_park_set_photos(uuid, text[]) to authenticated;


-- ---------------------------------------------------------------------
-- TIRPark page banner (same columns as services_hero after 0049–0052).
-- ---------------------------------------------------------------------
create table if not exists public.tirpark_hero (
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
alter table public.tirpark_hero enable row level security;
revoke all on public.tirpark_hero from anon, authenticated;
grant select on public.tirpark_hero to authenticated;
drop policy if exists "tirpark_hero_read" on public.tirpark_hero;
create policy "tirpark_hero_read" on public.tirpark_hero for select to authenticated using (true);

-- The banner functions of 0050 / 0051 / 0052, now also for 'tirpark'
-- (the 'market' and 'services' parts are unchanged, admins only, logged).
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
  else
    raise exception 'invalid_argument';
  end if;
  perform public._admin_log(p_page || '.hero', p_page || '_hero', '1', v_old, v_new);
end $$;
revoke all on function public.admin_set_page_hero_zoom(text, real, real) from public, anon;
grant execute on function public.admin_set_page_hero_zoom(text, real, real) to authenticated;


-- Final check: everything in place.
do $$
begin
  if to_regclass('public.tir_park_reviews') is null
     or to_regprocedure('public.tir_park_reviews_list(uuid)') is null
     or to_regprocedure('public.tir_park_set_photos(uuid, text[])') is null
     or to_regclass('public.tirpark_hero') is null then
    raise exception '0078: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

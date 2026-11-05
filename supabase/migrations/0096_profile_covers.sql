-- =====================================================================
-- 0096 — Profile backgrounds ("Fon şəklini dəyiş") for Park, Servis and
-- Mağaza (owner, 05.11.2026).
--
-- Run AFTER 0093.
--
-- * cover_templates: background pictures an admin adds (name, picture,
--   for which sections — park / service / shop — active or not). Everyone
--   signed in sees only the active ones; only admins add / edit / delete
--   (server-checked, written to the Audit Log). The pictures live in the
--   existing profile-media bucket (the admin's own folder, 0031 rules).
-- * tir_parks.cover_url + tir_parks.logo_url (the round park picture) and
--   service_providers.cover_url: set only through the functions below by
--   the park's approved manager / the service's owner (or an admin), to an
--   active template of that section or a picture from the caller's own
--   profile-media folder. The "Mağaza" (the seller's page) keeps its
--   existing profile_details.cover_url (0031).
-- * Gallery pictures, booking, contact and route are not touched.
--
-- Safe: forward-only, re-runnable. One table, three columns (null by
-- default) and functions added; nothing dropped, deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.tir_parks') is null or to_regclass('public.service_providers') is null
     or to_regprocedure('public._admin_log(text, text, text, jsonb, jsonb, text)') is null then
    raise exception '0096: run 0017, 0077 and 0012 first — nothing changed';
  end if;
end $$;

-- 1) Templates ------------------------------------------------------------
create table if not exists public.cover_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 60),
  image_url text not null check (char_length(image_url) <= 1000
    and image_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/'),
  sections text[] not null check (cardinality(sections) between 1 and 3 and sections <@ array['park', 'service', 'shop']),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null
);
create index if not exists cover_templates_order_idx on public.cover_templates (sort_order, created_at);
alter table public.cover_templates enable row level security;
revoke all on public.cover_templates from anon, authenticated;
grant select on public.cover_templates to authenticated;
drop policy if exists "cover_templates_read" on public.cover_templates;
create policy "cover_templates_read" on public.cover_templates for select to authenticated
  using (is_active or (select public.is_admin()));

-- Admin: add (p_id null) or change one template.
create or replace function public.admin_cover_template_save(
  p_id uuid, p_name text, p_image_url text, p_sections text[], p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old cover_templates; v_new cover_templates; v_secs text[];
begin
  perform public._require_admin();
  if p_name is null or char_length(btrim(p_name)) not between 1 and 60 then raise exception 'invalid_name' using errcode = '22023'; end if;
  if p_image_url is null or char_length(p_image_url) > 1000
     or p_image_url !~ '^https://[^ ]+/storage/v1/object/public/profile-media/' then
    raise exception 'invalid_url' using errcode = '22023';
  end if;
  select array_agg(distinct x order by x) into v_secs from unnest(coalesce(p_sections, '{}')) x;
  if v_secs is null or not (v_secs <@ array['park', 'service', 'shop']) then
    raise exception 'invalid_sections' using errcode = '22023';
  end if;
  if p_id is null then
    insert into cover_templates (name, image_url, sections, is_active, sort_order, created_by)
    values (btrim(p_name), btrim(p_image_url), v_secs, coalesce(p_active, true),
            coalesce((select max(sort_order) + 1 from cover_templates), 0), auth.uid())
    returning * into v_new;
    perform public._admin_log('cover.template_add', 'cover_template', v_new.id::text, null, to_jsonb(v_new));
  else
    select * into v_old from cover_templates where id = p_id for update;
    if v_old.id is null then raise exception 'not_found' using errcode = 'P0002'; end if;
    update cover_templates
       set name = btrim(p_name), image_url = btrim(p_image_url), sections = v_secs,
           is_active = coalesce(p_active, v_old.is_active), updated_at = now()
     where id = p_id
    returning * into v_new;
    perform public._admin_log('cover.template_edit', 'cover_template', p_id::text, to_jsonb(v_old), to_jsonb(v_new));
  end if;
  return to_jsonb(v_new);
end $$;
revoke all on function public.admin_cover_template_save(uuid, text, text, text[], boolean) from public, anon;
grant execute on function public.admin_cover_template_save(uuid, text, text, text[], boolean) to authenticated;

-- Admin: remove one template. Profiles that already use it keep it.
create or replace function public.admin_cover_template_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  select to_jsonb(t) into v_old from cover_templates t where id = p_id;
  if v_old is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  delete from cover_templates where id = p_id;
  perform public._admin_log('cover.template_delete', 'cover_template', p_id::text, v_old, null);
end $$;
revoke all on function public.admin_cover_template_delete(uuid) from public, anon;
grant execute on function public.admin_cover_template_delete(uuid) to authenticated;

-- 2) The pictures on the park / service ----------------------------------
alter table public.tir_parks add column if not exists cover_url text;
alter table public.tir_parks add column if not exists logo_url text;
alter table public.service_providers add column if not exists cover_url text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'tir_parks_cover_url_check') then
    alter table public.tir_parks add constraint tir_parks_cover_url_check check (cover_url is null or
      (char_length(cover_url) <= 1000 and cover_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'tir_parks_logo_url_check') then
    alter table public.tir_parks add constraint tir_parks_logo_url_check check (logo_url is null or
      (char_length(logo_url) <= 1000 and logo_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'service_providers_cover_url_check') then
    alter table public.service_providers add constraint service_providers_cover_url_check check (cover_url is null or
      (char_length(cover_url) <= 1000 and cover_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/'));
  end if;
end $$;

-- The service table is readable column by column (0018 / 0028).
grant select (cover_url) on table public.service_providers to authenticated;

-- Only the functions below (or an admin / the server) change them.
create or replace function public.place_cover_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or public.is_admin() or current_setting('app.place_cover_trusted', true) = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.cover_url := null;
    if tg_table_name = 'tir_parks' then new.logo_url := null; end if;
  else
    new.cover_url := old.cover_url;
    if tg_table_name = 'tir_parks' then new.logo_url := old.logo_url; end if;
  end if;
  return new;
end $$;
revoke all on function public.place_cover_guard() from public, anon, authenticated;
drop trigger if exists zz_place_cover_guard on public.tir_parks;
create trigger zz_place_cover_guard before insert or update on public.tir_parks
  for each row execute function public.place_cover_guard();
drop trigger if exists zz_place_cover_guard on public.service_providers;
create trigger zz_place_cover_guard before insert or update on public.service_providers
  for each row execute function public.place_cover_guard();

-- A picture the caller may put: from his own profile-media folder, or an
-- active template of that section (the place / zoom part may differ).
create or replace function public._place_cover_ok(p_url text, p_section text, p_templates boolean)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select p_url is not null and char_length(p_url) <= 1000
     and p_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/'
     and (
       split_part(regexp_replace(p_url, '^https://[^ ]+/storage/v1/object/public/profile-media/', ''), '/', 1) = auth.uid()::text
       or (p_templates and exists (
             select 1 from cover_templates t
              where t.is_active and p_section = any (t.sections)
                and regexp_replace(t.image_url, '[?#].*$', '') = regexp_replace(p_url, '[?#].*$', '')))
     );
$$;
revoke all on function public._place_cover_ok(text, text, boolean) from public, anon, authenticated;

-- The park's background (p_url null = back to the default picture).
create or replace function public.tir_park_set_cover(p_park uuid, p_url text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if p_url is not null and not public._place_cover_ok(p_url, 'park', true) then
    raise exception 'invalid_url' using errcode = '22023';
  end if;
  perform set_config('app.place_cover_trusted', '1', true);
  update tir_parks set cover_url = p_url where id = p_park;
  perform set_config('app.place_cover_trusted', '0', true);
end $$;
revoke all on function public.tir_park_set_cover(uuid, text) from public, anon;
grant execute on function public.tir_park_set_cover(uuid, text) to authenticated;

-- The park's round picture: the manager's own picture only.
create or replace function public.tir_park_set_logo(p_park uuid, p_url text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.is_tir_park_manager(p_park) then raise exception 'not_allowed' using errcode = '42501'; end if;
  if p_url is not null and not public._place_cover_ok(p_url, 'park', false) then
    raise exception 'invalid_url' using errcode = '22023';
  end if;
  perform set_config('app.place_cover_trusted', '1', true);
  update tir_parks set logo_url = p_url where id = p_park;
  perform set_config('app.place_cover_trusted', '0', true);
end $$;
revoke all on function public.tir_park_set_logo(uuid, text) from public, anon;
grant execute on function public.tir_park_set_logo(uuid, text) to authenticated;

-- The service's background: its owner (or an admin).
create or replace function public.service_set_cover(p_service uuid, p_url text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not (public.is_admin() or exists (select 1 from service_providers where id = p_service and owner_id = auth.uid())) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_url is not null and not public._place_cover_ok(p_url, 'service', true) then
    raise exception 'invalid_url' using errcode = '22023';
  end if;
  perform set_config('app.place_cover_trusted', '1', true);
  update service_providers set cover_url = p_url where id = p_service;
  perform set_config('app.place_cover_trusted', '0', true);
end $$;
revoke all on function public.service_set_cover(uuid, text) from public, anon;
grant execute on function public.service_set_cover(uuid, text) to authenticated;

-- Final check.
do $$
begin
  if to_regclass('public.cover_templates') is null
     or to_regprocedure('public.tir_park_set_cover(uuid, text)') is null
     or to_regprocedure('public.service_set_cover(uuid, text)') is null then
    raise exception '0096: final check failed — nothing changed';
  end if;
end $$;

commit;

notify pgrst, 'reload schema';

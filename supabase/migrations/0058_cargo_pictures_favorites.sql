-- =====================================================================
-- 0058 — Load pictures and favourite loads (owner, 22.10.2026)
--
-- * cargo.image_url: the picture on a load's card. Not required. The load
--   owner picks one of the admin's templates for the load type or uploads
--   his own, and can change or remove it later (cargo_owner_write, 0002).
--   Only pictures from our own bucket "cargo-photos" are accepted. Loads
--   posted before 0058 stay without a picture (the app shows the load
--   type icon) — no picture is guessed.
-- * cargo_image_templates: up to 10 pictures per load type (tent, ref,
--   container, dump, groupage, open, tanker). Everybody reads them; only
--   an admin adds, removes or reorders them (checked here, logged).
-- * admin_clear_cargo_image: an admin takes an unsuitable picture off a
--   load (logged). Nothing else on the load changes.
-- * cargo_favorites: "Seçilmiş yüklər" — every user sees and changes only
--   his own rows. A deleted load leaves the list on its own (cascade).
-- * storage bucket cargo-photos (public read, 5 MB): own folder = user
--   id; admins also write the templates folder.
--
-- Safe: forward-only, re-runnable. One new nullable column, new tables,
-- functions and policies. No existing row is changed or deleted.
-- =====================================================================

alter table public.cargo add column if not exists image_url text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cargo_image_url_check') then
    alter table public.cargo add constraint cargo_image_url_check check (
      image_url is null
      or (char_length(image_url) <= 1000 and image_url ~ '^https://[^/]+/storage/v1/object/public/cargo-photos/'));
  end if;
end $$;

-- Templates -------------------------------------------------------------
create table if not exists public.cargo_image_templates (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker')),
  image_url text not null check (char_length(image_url) <= 1000
    and image_url ~ '^https://[^/]+/storage/v1/object/public/cargo-photos/'),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references public.users(id) on delete set null
);
create index if not exists idx_cargo_image_templates_cat on public.cargo_image_templates (category, sort_order, created_at);

alter table public.cargo_image_templates enable row level security;
revoke all on public.cargo_image_templates from anon, authenticated;
grant select on public.cargo_image_templates to anon, authenticated;
drop policy if exists "cargo_image_templates_read" on public.cargo_image_templates;
create policy "cargo_image_templates_read" on public.cargo_image_templates for select using (true);

-- Admins only: add one picture (at most 10 per load type).
create or replace function public.admin_add_cargo_image_template(p_category text, p_image_url text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_row cargo_image_templates; v_n integer;
begin
  perform public._require_admin();
  if p_category is null or p_category not in ('tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker') then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  -- One admin at a time per load type, so the limit holds.
  perform pg_advisory_xact_lock(hashtext('cargo_image_templates:' || p_category));
  select count(*) into v_n from cargo_image_templates where category = p_category;
  if v_n >= 10 then raise exception 'template_limit' using errcode = '22023'; end if;
  insert into cargo_image_templates (category, image_url, sort_order, created_by)
  values (p_category, btrim(p_image_url), v_n, auth.uid())
  returning * into v_row;
  perform public._admin_log('cargo.template_add', 'cargo_image_template', v_row.id::text, null, to_jsonb(v_row));
  return to_jsonb(v_row);
end $$;

-- Admins only: remove one picture. Loads that already use it keep it.
create or replace function public.admin_delete_cargo_image_template(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  select to_jsonb(t) into v_old from cargo_image_templates t where id = p_id;
  if v_old is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  delete from cargo_image_templates where id = p_id;
  perform public._admin_log('cargo.template_delete', 'cargo_image_template', p_id::text, v_old, null);
end $$;

-- Admins only: new order of one load type's pictures (all its ids).
create or replace function public.admin_reorder_cargo_image_templates(p_category text, p_ids uuid[])
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  if p_ids is null
     or (select count(*) from cargo_image_templates where category = p_category)
        <> cardinality(p_ids)
     or exists (select 1 from unnest(p_ids) i where not exists (
          select 1 from cargo_image_templates t where t.id = i and t.category = p_category)) then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  update cargo_image_templates t set sort_order = o.ord - 1
    from unnest(p_ids) with ordinality as o(id, ord)
   where t.id = o.id;
  perform public._admin_log('cargo.template_order', 'cargo_image_template', p_category, null, to_jsonb(p_ids));
end $$;

-- Admins only: take the picture off one load.
create or replace function public.admin_clear_cargo_image(p_cargo uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old text;
begin
  perform public._require_admin();
  select image_url into v_old from cargo where id = p_cargo;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update cargo set image_url = null where id = p_cargo;
  perform public._admin_log('cargo.image_clear', 'cargo', p_cargo::text,
    jsonb_build_object('image_url', v_old), jsonb_build_object('image_url', null));
end $$;

revoke all on function public.admin_add_cargo_image_template(text, text) from public, anon;
revoke all on function public.admin_delete_cargo_image_template(uuid) from public, anon;
revoke all on function public.admin_reorder_cargo_image_templates(text, uuid[]) from public, anon;
revoke all on function public.admin_clear_cargo_image(uuid) from public, anon;
grant execute on function public.admin_add_cargo_image_template(text, text) to authenticated;
grant execute on function public.admin_delete_cargo_image_template(uuid) to authenticated;
grant execute on function public.admin_reorder_cargo_image_templates(text, uuid[]) to authenticated;
grant execute on function public.admin_clear_cargo_image(uuid) to authenticated;

-- Favourite loads ("Seçilmiş yüklər") ------------------------------------
create table if not exists public.cargo_favorites (
  user_id uuid not null references public.users(id) on delete cascade,
  cargo_id uuid not null references public.cargo(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, cargo_id)
);
create index if not exists idx_cargo_favorites_cargo on public.cargo_favorites (cargo_id);

alter table public.cargo_favorites enable row level security;
revoke all on public.cargo_favorites from anon, authenticated;
grant select, insert, delete on public.cargo_favorites to authenticated;
drop policy if exists "cargo_fav_own" on public.cargo_favorites;
create policy "cargo_fav_own" on public.cargo_favorites
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Pictures: public bucket "cargo-photos", folder = the owner's user id;
-- admins also write "templates/". ----------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('cargo-photos', 'cargo-photos', true, 5242880)
on conflict (id) do nothing;

drop policy if exists "cargo_photos_insert" on storage.objects;
create policy "cargo_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'cargo-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
drop policy if exists "cargo_photos_update" on storage.objects;
create policy "cargo_photos_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'cargo-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
drop policy if exists "cargo_photos_delete" on storage.objects;
create policy "cargo_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'cargo-photos' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
drop policy if exists "cargo_photos_read" on storage.objects;
create policy "cargo_photos_read" on storage.objects
  for select using (bucket_id = 'cargo-photos');

notify pgrst, 'reload schema';

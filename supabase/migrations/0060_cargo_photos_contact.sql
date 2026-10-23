-- =====================================================================
-- 0060 — Up to 6 load pictures and an optional contact number
-- (owner, 23.10.2026). Needs 0058 (cargo.image_url, cargo-photos).
--
-- * cargo.image_urls: up to 6 pictures, the first is the main picture.
--   Only pictures from our own bucket "cargo-photos" are accepted.
--   cargo.image_url (0058) stays and is kept equal to the first picture
--   by a trigger, so older apps and the Loads list keep working:
--     - a new app writes image_urls  -> image_url = image_urls[1];
--     - an older app writes image_url -> it becomes the first picture.
--   Loads posted before 0060 are NOT rewritten: the app shows their
--   image_url as a one-picture gallery.
-- * cargo_contacts: an optional contact number for one load
--   (international format, +994…). Kept OUT of public.cargo on purpose:
--   loads are readable by everybody, this number must not be. Only the
--   load owner (and admins) read / write the row; others get it only
--   through get_cargo_contact(), with the same rules as the owner's
--   registered phone (0019).
-- * get_cargo_contact(): same signature, same access rules as 0019;
--   it only adds "contact_phone" to its answer.
-- * admin_clear_cargo_image() (0058): now takes ALL pictures off the
--   load (not only the first one).
--
-- Safe: forward-only, re-runnable. One new column with a default, one
-- new table, functions and a trigger. No existing row is changed or
-- deleted; no grant is widened.
-- =====================================================================

-- Pictures -------------------------------------------------------------
create or replace function public.cargo_photo_urls_ok(p_urls text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select coalesce(cardinality(p_urls), 0) <= 6
     and not exists (
       select 1 from unnest(coalesce(p_urls, '{}'::text[])) u
        where u is null or char_length(u) > 1000
           or u !~ '^https://[^/]+/storage/v1/object/public/cargo-photos/');
$$;

alter table public.cargo add column if not exists image_urls text[] not null default '{}'::text[];

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cargo_image_urls_check') then
    alter table public.cargo add constraint cargo_image_urls_check check (public.cargo_photo_urls_ok(image_urls));
  end if;
end $$;

-- image_url always = the first picture (both ways, see above).
create or replace function public.zz_cargo_image_urls_sync()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare v_rest text[];
begin
  if tg_op = 'INSERT' then
    if cardinality(new.image_urls) > 0 then
      new.image_url := new.image_urls[1];
    elsif new.image_url is not null then
      new.image_urls := array[new.image_url];
    end if;
    return new;
  end if;
  if new.image_urls is distinct from old.image_urls then
    new.image_url := new.image_urls[1];                 -- null when empty
  elsif new.image_url is distinct from old.image_url then
    -- An older app changed / removed the main picture only.
    v_rest := coalesce(old.image_urls[2:cardinality(old.image_urls)], '{}'::text[]);
    new.image_urls := case when new.image_url is null then v_rest else array[new.image_url] || v_rest end;
    new.image_url := new.image_urls[1];
  end if;
  return new;
end $$;
drop trigger if exists zz_cargo_image_urls_sync on public.cargo;
create trigger zz_cargo_image_urls_sync before insert or update on public.cargo
  for each row execute function public.zz_cargo_image_urls_sync();

-- Admins: take every picture off one load (0058 took only image_url).
create or replace function public.admin_clear_cargo_image(p_cargo uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  select jsonb_build_object('image_url', image_url, 'image_urls', image_urls) into v_old from cargo where id = p_cargo;
  if v_old is null then raise exception 'not_found' using errcode = 'P0002'; end if;
  update cargo set image_urls = '{}'::text[], image_url = null where id = p_cargo;
  perform public._admin_log('cargo.image_clear', 'cargo', p_cargo::text, v_old,
    jsonb_build_object('image_url', null, 'image_urls', '[]'::jsonb));
end $$;
revoke all on function public.admin_clear_cargo_image(uuid) from public, anon;
grant execute on function public.admin_clear_cargo_image(uuid) to authenticated;

-- Optional contact number of a load ------------------------------------
create table if not exists public.cargo_contacts (
  cargo_id uuid primary key references public.cargo(id) on delete cascade,
  phone text not null check (phone ~ '^\+[1-9][0-9]{6,14}$'),
  updated_at timestamptz not null default now()
);
alter table public.cargo_contacts enable row level security;
revoke all on public.cargo_contacts from anon, authenticated;
grant select, insert, update, delete on public.cargo_contacts to authenticated;
drop policy if exists "cargo_contacts_owner" on public.cargo_contacts;
create policy "cargo_contacts_owner" on public.cargo_contacts
  for all to authenticated
  using (exists (select 1 from public.cargo c where c.id = cargo_id and c.owner_id = auth.uid()) or public.is_admin())
  with check (exists (select 1 from public.cargo c where c.id = cargo_id and c.owner_id = auth.uid()));

-- get_cargo_contact (0019): same rules, + contact_phone ------------------
create or replace function public.get_cargo_contact(p_cargo uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_c public.cargo;
  v_u public.users;
begin
  if v_me is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select * into v_c from public.cargo where id = p_cargo;
  if not found then
    return null;
  end if;
  if not (not v_c.is_hidden or v_c.owner_id = v_me or public.is_admin()
          or public.can_see_hidden_cargo(p_cargo)) then
    return null;                               -- caller cannot see this load
  end if;
  if v_c.owner_id <> v_me and not public.is_admin() and public.is_blocked(v_me) then
    return null;
  end if;
  select * into v_u from public.users where id = v_c.owner_id;
  return jsonb_build_object(
    'owner_id',      v_c.owner_id,
    'full_name',     v_u.full_name,
    'phone',         v_u.phone,
    'email',         v_u.email,
    'contact_phone', (select k.phone from public.cargo_contacts k where k.cargo_id = p_cargo));
end;
$$;
revoke execute on function public.get_cargo_contact(uuid) from public, anon;
grant execute on function public.get_cargo_contact(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';

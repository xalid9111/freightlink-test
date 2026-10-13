-- =====================================================================
-- 0009 — profile photos, "last seen", early-member badge, and two
-- security fixes found while preparing them. SAFE FORWARD MIGRATION:
-- only ADDs columns/policies/a trigger/a storage bucket; drops and
-- re-creates exactly one policy (users_select_all) with a narrower
-- audience. No data is deleted. Re-running it is harmless
-- (every statement is idempotent).
--
-- Run once in Supabase → SQL Editor → New query → paste → Run.
-- =====================================================================

-- 1) New profile columns ------------------------------------------------
alter table public.users add column if not exists avatar_url text;
alter table public.users add column if not exists last_seen_at timestamptz;
-- "Erkən üzv" (early member): true for everyone who joins during the
-- launch period. To end the launch period later, run:
--   alter table public.users alter column is_early_member set default false;
alter table public.users add column if not exists is_early_member boolean not null default true;

-- 2) SECURITY FIX: protect role / is_verified / is_early_member --------
-- Policy users_update_self (0002) lets a user update their own row and
-- only checks that `role` is unchanged — so a user could set
-- is_verified = true on themselves. This trigger keeps those columns
-- unchanged for normal users. Admins (public.is_admin()) and the
-- dashboard / service role (no auth.uid()) can still change them —
-- that is how you verify a user: Table Editor → users → is_verified.
create or replace function public.guard_user_protected_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  new.role := old.role;
  new.is_verified := old.is_verified;
  new.is_early_member := old.is_early_member;
  return new;
end;
$$;

drop trigger if exists guard_user_protected on public.users;
create trigger guard_user_protected
  before update on public.users
  for each row execute function public.guard_user_protected_columns();

-- 3) PRIVACY FIX: profiles readable by signed-in users only -----------
-- users_select_all (0002) used `using (true)` with no role, so even an
-- anonymous visitor holding the public API key could list every
-- user's name, e-mail and phone. Same rule, limited to signed-in users
-- (the app only reads profiles after login).
drop policy if exists "users_select_all" on public.users;
create policy "users_select_all" on public.users
  for select to authenticated using (true);

-- 4) Avatar storage ----------------------------------------------------
-- Public-read bucket; each user may write only inside their own folder
-- "<user id>/...".
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

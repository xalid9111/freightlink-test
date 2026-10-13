-- ============================================================
-- FreightLink · Migration 0005 — Fix registration (found during
-- Phase 3 verification, before any Phase 4 work)
--
-- TWO REAL BUGS, related, fixed together:
--
-- Bug A: public.users has RLS enabled (migration 0002) but there was
-- NO insert policy for a plain authenticated user. Only
-- "users_admin_full" (admin-only) covered inserts. A newly-registered
-- user's own client calling `.from('users').insert(...)` — which is
-- exactly what auth_repository_impl.dart did — would be rejected by
-- Postgres with a permission-denied/RLS error on every single
-- registration. This was never caught earlier because it can only be
-- observed against a real Postgres instance with RLS actually
-- evaluated; this sandbox has never had one available (see every
-- prior phase report).
--
-- Bug B (the "email confirmation edge case"): most Supabase projects
-- have "Confirm email" ON by default. With it on, auth.signUp()
-- returns with `session == null` until the user clicks the emailed
-- confirmation link — so even with a fix for Bug A (e.g. a policy
-- like `with check (auth.uid() = id)`), the client has no session yet
-- and `auth.uid()` evaluates to null under the anon role. The insert
-- would still fail, just for a different reason, in that (common)
-- project configuration.
--
-- The fix used by essentially every real Supabase app for this exact
-- problem: a SECURITY DEFINER trigger on auth.users that creates the
-- public.users row itself, server-side, in the same transaction as
-- the signup — independent of RLS and independent of whether a
-- client session exists yet. The Flutter client no longer inserts
-- into public.users at all; it passes profile fields as auth user
-- metadata (`data: {...}` in signUp()) and the trigger reads them
-- back out of `raw_user_meta_data`.
-- ============================================================

create or replace function public.handle_new_auth_user()
returns trigger as $$
begin
  insert into public.users (id, email, full_name, role, phone)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'role', 'cargo_owner'),
    new.raw_user_meta_data->>'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

comment on function public.handle_new_auth_user() is
  'Creates the public.users profile row the instant a row appears in '
  'auth.users, using signup metadata (full_name/role/phone). Runs as '
  'SECURITY DEFINER so it works regardless of RLS or whether the '
  'client has an active session yet (see migration 0005 header).';

-- The client no longer needs — and, per Bug A/B above, could never
-- safely rely on — an insert policy for its own signup. This narrow
-- admin-only insert policy is kept only so admin tooling can create a
-- user row directly if ever needed (e.g. provisioning a support account);
-- it grants nothing to a plain authenticated user.
create policy "users_admin_insert" on public.users
  for insert with check (public.is_admin());

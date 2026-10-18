-- =====================================================================
-- 0039 — One account, several activities (Profil: Daşıyıcı · Yük verən ·
-- Usta / Servis · Satış)
--
-- * users.activities text[]: any combination of 'carrier', 'shipper',
--   'service', 'seller'. users.role is NOT changed (old role, offers,
--   chats and carrier profiles stay as they are).
-- * Existing accounts are filled ONCE from what they already are:
--   role carrier / driver → carrier, role cargo_owner → shipper, owner of
--   a service profile → service. Rows a user has already set (not null)
--   are never touched again, so re-running this file keeps their choice.
-- * set_my_activities(): the signed-in user turns activities on / off.
--   Turning "carrier" on creates the carrier profile the offer rules need
--   (carriers row, same as signing up as a carrier). Turning anything off
--   deletes NOTHING: carrier profile, offers, shipments and chats stay,
--   and chats stay open (they depend on participation, not on a role).
-- * user_activities view (id, activities) for public profiles;
--   user_profiles (0019) is not changed.
--
-- Safe: forward-only, re-runnable. Only a new column is filled; no row
-- is deleted, no other column changes.
-- =====================================================================

alter table public.users add column if not exists activities text[];

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'users_activities_check') then
    alter table public.users add constraint users_activities_check
      check (activities is null or activities <@ array['carrier','shipper','service','seller']::text[]);
  end if;
end $$;

-- Existing accounts: once, from the old role + service profile.
update public.users u
   set activities = array_remove(array[
         case when u.role in ('carrier', 'driver') then 'carrier' end,
         case when u.role = 'cargo_owner' then 'shipper' end,
         case when exists (select 1 from public.service_providers s where s.owner_id = u.id) then 'service' end
       ]::text[], null)
 where u.activities is null;

-- New accounts start with nothing selected (chosen in Profil).
alter table public.users alter column activities set default '{}';

-- ---------------------------------------------------------------------
-- The signed-in user's activities (any combination).
-- ---------------------------------------------------------------------
create or replace function public.set_my_activities(p_activities text[])
returns text[]
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_me uuid := auth.uid();
  v text[];
begin
  if v_me is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select coalesce(array_agg(distinct a order by a), '{}'::text[]) into v
    from unnest(coalesce(p_activities, '{}'::text[])) a
   where a is not null;
  if not (v <@ array['carrier','shipper','service','seller']::text[]) then
    raise exception 'invalid_activity' using errcode = '22023';
  end if;
  update public.users set activities = v where id = v_me;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  -- Carrier on: the carrier profile that offers / shipments use.
  if 'carrier' = any(v) then
    insert into public.carriers (user_id) values (v_me) on conflict (user_id) do nothing;
  end if;
  return v;
end;
$$;
revoke all on function public.set_my_activities(text[]) from public, anon;
grant execute on function public.set_my_activities(text[]) to authenticated;

-- ---------------------------------------------------------------------
-- Public: who does what (shown on public profiles). A separate view so
-- user_profiles (0019) stays exactly as it is.
-- ---------------------------------------------------------------------
create or replace view public.user_activities
with (security_barrier = true) as
  select u.id, coalesce(u.activities, '{}'::text[]) as activities
  from public.users u;

revoke all on public.user_activities from public, anon, authenticated;
grant select on public.user_activities to authenticated;
grant select on public.user_activities to service_role;

notify pgrst, 'reload schema';

-- ============================================================
-- FreightLink · Migration 0007 — Auto-create carrier profile
--
-- BUG FOUND (before starting the marketplace/offers UI): migration
-- 0005's trigger creates a public.users row on signup, but nothing
-- ever created the matching public.carriers row for a carrier-role
-- user. Every RLS policy and helper that scopes data to "the current
-- carrier" (current_carrier_id(), used by offers, trucks, credit
-- wallets, etc. — migrations 0002/0004/0006) depends on that row
-- existing. Without this, a real carrier account could register and
-- log in, but every offer submission would fail (current_carrier_id()
-- returns null), and the signup credit-bonus trigger from migration
-- 0006 would never fire either, since it only fires on an INSERT into
-- public.carriers.
--
-- This is exactly the kind of thing the two-phone acceptance test
-- would have caught immediately on Carrier B's very first action.
-- ============================================================

create or replace function public.handle_new_carrier_profile()
returns trigger as $$
begin
  if new.role = 'carrier' then
    insert into public.carriers (user_id) values (new.id)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_user_created_carrier_profile on public.users;
create trigger on_user_created_carrier_profile
  after insert on public.users
  for each row execute function public.handle_new_carrier_profile();

comment on function public.handle_new_carrier_profile() is
  'Creates the public.carriers row the instant a public.users row with '
  'role=''carrier'' is created (itself created by the migration 0005 '
  'trigger on auth.users) — chains correctly into migration 0006''s '
  'signup credit-bonus trigger, which fires on the carriers insert.';

-- NOTE for anyone running this against a project that already has real
-- carrier accounts created before this migration existed: those
-- accounts will NOT retroactively get a carriers row from this
-- trigger (triggers only fire on new inserts). Run once, manually, if
-- needed:
--   insert into public.carriers (user_id)
--   select id from public.users
--   where role = 'carrier'
--     and id not in (select user_id from public.carriers)
--   on conflict (user_id) do nothing;

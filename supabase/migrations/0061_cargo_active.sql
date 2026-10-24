-- =====================================================================
-- 0061 — The load owner turns a load on / off (owner, 24.10.2026).
--
-- * cargo.is_paused: the owner switched the load off in "Yüklərim".
--   A paused load is not shown on the Loads page, in search, on the map
--   or on the owner's public profile; it is NOT deleted — chats, offers
--   and pictures stay, and "Aktiv et" (with a new loading date) brings it
--   back.
-- * A load whose loading date has passed leaves the Loads page by itself
--   (checked by the app with the date, no job): nothing is deleted.
-- * Who may change it: the load owner (existing RLS "cargo_owner_write",
--   0002) and admins — no new grant.
--
-- Safe: forward-only, re-runnable. One new column with a default; no
-- existing row, policy, trigger or function is changed or deleted.
-- =====================================================================

alter table public.cargo add column if not exists is_paused boolean not null default false;

notify pgrst, 'reload schema';

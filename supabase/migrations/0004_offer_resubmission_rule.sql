-- ============================================================
-- FreightLink · Migration 0004 — Offer resubmission rule
--
-- Rule (from product spec):
--   • Carrier + Cargo → maximum 1 PENDING offer at a time.
--   • Rejected / cancelled / expired offers do not block a new one.
--   • History is preserved — offers are never overwritten or deleted.
--   • Enforced at the database level, safe under concurrent inserts.
--
-- Why a new migration instead of editing 0001/0002: migrations are a
-- log of what happened to the schema, applied in order. Editing
-- 0001_schema.sql after it has already run in any environment (even
-- just this dev project) would desync anyone who already applied it —
-- their database wouldn't match the file anymore. A new, additive
-- migration is the only safe way to change a schema that's live.
-- ============================================================

-- 1) Add 'expired' to the offers status vocabulary. Postgres has no
--    ALTER CHECK ... ADD VALUE, so the inline check constraint is
--    dropped and recreated with the wider list. The default name for
--    an unnamed inline CHECK on offers.status is offers_status_check
--    (Postgres' standard <table>_<column>_check convention, confirmed
--    against how it was declared in 0001_schema.sql).
alter table public.offers
  drop constraint offers_status_check;

alter table public.offers
  add constraint offers_status_check
  check (status in ('pending','accepted','rejected','countered','cancelled','expired'));

-- 2) The actual rule: a PARTIAL unique index only over rows where
--    status = 'pending'. Non-pending rows (however many, from however
--    many past rejected/cancelled/expired offers) are invisible to
--    this index, so history is untouched and unlimited. The instant a
--    second 'pending' row for the same (cargo_id, carrier_id) would be
--    inserted, Postgres itself raises a unique_violation (23505) —
--    this holds even for two requests arriving in the same millisecond
--    from two devices, because the index update is part of Postgres'
--    normal transactional/locking machinery, not application code.
create unique index idx_offers_one_pending_per_carrier_cargo
  on public.offers (cargo_id, carrier_id)
  where status = 'pending';

comment on index idx_offers_one_pending_per_carrier_cargo is
  'Enforces: a carrier may have at most one PENDING offer per cargo. '
  'Rejected/cancelled/expired/countered offers are excluded from this '
  'index by the WHERE clause, so they never block a resubmission and '
  'are kept forever as history.';

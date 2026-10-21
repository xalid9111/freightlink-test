-- =====================================================================
-- 0053 — TIR Bazarı: the seller marks the exact place (owner, 21.10.2026)
--
-- On the sale form the seller can tap the map (or use GPS) to mark where
-- the truck stands; buyers then get directions to that place.
-- location_exact = true: lat / lng is the point the seller marked;
-- false (default, all existing ads): lat / lng is the city centre, and the
-- ad says so.
--
-- Safe: forward-only, re-runnable. One new column (default false);
-- nothing is changed or deleted. The existing owner-only RLS and the
-- listing guard (0040) cover it.
-- =====================================================================

alter table public.market_listings add column if not exists location_exact boolean not null default false;

notify pgrst, 'reload schema';

-- =====================================================================
-- 0047 — Payment ways as simple choices (owner, 21.10.2026)
--
-- On the load form only "Avans ödənişi" keeps an amount (pay_advance,
-- 0046). Cash, payment after delivery and bank transfer are just ticked:
--   pay_cash_on       — Nağd ödəniş
--   pay_on_delivery   — Təhvil sonrası ödəniş
--   pay_bank_on       — Bank köçürməsi
-- The price is already given on the load (offered_price).
--
-- Safe: forward-only, re-runnable. Three new boolean columns (false =
-- not ticked); nothing is changed or deleted. Loads saved with a cash /
-- bank amount (0046) keep it; the app shows those as ticked.
-- =====================================================================

alter table public.cargo add column if not exists pay_cash_on boolean not null default false;
alter table public.cargo add column if not exists pay_on_delivery boolean not null default false;
alter table public.cargo add column if not exists pay_bank_on boolean not null default false;

notify pgrst, 'reload schema';

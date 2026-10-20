-- =====================================================================
-- 0046 — Load payment terms and free waiting time (owner, 20.10.2026)
--
-- "Ödəniş və gözləmə şərtləri" on the load form:
--   pay_advance / pay_cash / pay_bank — amounts the load owner types
--     (in the load's own currency, public.cargo.currency); empty = not
--     offered, so it is not shown on the load. Only positive amounts.
--   free_wait_hours — "Prostoy": free waiting time, 24 / 36 / 48 hours.
--     New loads get 48 from the app; existing loads stay empty (nothing
--     is invented for them) until the owner edits the load.
--
-- Safe: forward-only, re-runnable. Only four new nullable columns; no
-- existing row, policy, trigger or function is changed or deleted. The
-- existing RLS on public.cargo (owner writes his own load) covers them.
-- =====================================================================

alter table public.cargo add column if not exists pay_advance numeric(12,2)
  constraint cargo_pay_advance_positive check (pay_advance is null or pay_advance > 0);
alter table public.cargo add column if not exists pay_cash numeric(12,2)
  constraint cargo_pay_cash_positive check (pay_cash is null or pay_cash > 0);
alter table public.cargo add column if not exists pay_bank numeric(12,2)
  constraint cargo_pay_bank_positive check (pay_bank is null or pay_bank > 0);
alter table public.cargo add column if not exists free_wait_hours smallint
  constraint cargo_free_wait_hours_choice check (free_wait_hours is null or free_wait_hours in (24, 36, 48));

notify pgrst, 'reload schema';

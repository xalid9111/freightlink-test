-- =====================================================================
-- 0090 — TIR park: a new price applies to the trucks in the park
-- (owner, 03.11.2026).
--
-- Run AFTER 0086.
--
-- Before: a truck kept the price of the day it came in (tir_park_stays
-- .rate). Now, when the park's price changes (Ayarlar → Fiyat / gün, by
-- any path), every truck STILL IN the park — old or new entry — is
-- counted at the new price for its whole stay. Trucks that already left
-- keep the amount that was taken (nothing is rewritten for them). The
-- money is still counted on the server at the exit (tir_park_stay_exit).
--
-- Safe: forward-only, re-runnable. One function and one trigger; the
-- only rows touched are open stays of the park whose price changed.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.tir_park_stays') is null then
    raise exception '0090: run 0086 first — nothing changed';
  end if;
end $$;

create or replace function public._tir_park_stays_follow_price()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare v_rate numeric;
begin
  if new.price is not distinct from old.price and new.price_unit is not distinct from old.price_unit then
    return new;
  end if;
  if new.price is null or new.price <= 0 then
    return new;
  end if;
  -- Price per 24 h, as at the entry (0086).
  v_rate := round(case when new.price_unit = 'hour' then new.price * 24 else new.price end, 2);
  update tir_park_stays set rate = v_rate
   where park_id = new.id and exited_at is null and rate is distinct from v_rate;
  return new;
end $$;
revoke all on function public._tir_park_stays_follow_price() from public, anon, authenticated;

drop trigger if exists tir_park_stays_follow_price on public.tir_parks;
create trigger tir_park_stays_follow_price
  after update of price, price_unit on public.tir_parks
  for each row execute function public._tir_park_stays_follow_price();

-- Final check.
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'tir_park_stays_follow_price') then
    raise exception '0090: final check failed — nothing changed';
  end if;
end $$;

commit;

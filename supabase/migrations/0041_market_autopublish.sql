-- =====================================================================
-- 0041 — TIR Bazarı: ads are published at once (owner decision, 18.10.2026)
--
-- * "Elanı dərc et" makes the ad visible to everyone immediately — no
--   admin approval. Editing a published ad keeps it published.
-- * The admin still moderates afterwards: deactivate (inactive), reject,
--   VIP, delete (admin_market_* from 0040, unchanged). An ad the admin
--   deactivated can NOT be re-published by its owner; the owner can only
--   send it back to the admin (pending), as before.
-- * Ads that were waiting for approval and were never moderated
--   (status pending, no admin note) are published once.
-- * Moderation / VIP / views stay protected exactly as in 0040.
--
-- Safe: forward-only, re-runnable. Replaces only market_listing_guard();
-- no table, policy or other function changes; no row is deleted.
-- =====================================================================

create or replace function public.market_listing_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or public.is_admin() or current_setting('app.market_trusted', true) = '1' then
    new.updated_at := now();
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    if new.status not in ('draft', 'pending', 'active') then new.status := 'draft'; end if;
    if new.status = 'pending' then new.status := 'active'; end if;
    new.is_vip := false;
    new.vip_until := null;
    new.views := 0;
    new.admin_note := null;
    new.published_at := case when new.status = 'active' then now() end;
    new.sold_at := null;
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  -- UPDATE by the owner: moderation, VIP and counters stay as they are.
  new.id := old.id;
  new.listing_no := old.listing_no;
  new.owner_id := old.owner_id;
  new.is_vip := old.is_vip;
  new.vip_until := old.vip_until;
  new.views := old.views;
  new.admin_note := old.admin_note;
  new.created_at := old.created_at;
  new.published_at := old.published_at;
  new.sold_at := old.sold_at;

  if new.status is distinct from old.status then
    if not (
         (new.status = 'active' and old.status in ('draft', 'pending', 'rejected'))
      or (new.status = 'pending' and old.status in ('draft', 'rejected', 'inactive'))
      or (new.status = 'draft' and old.status in ('pending', 'rejected'))
      or (new.status = 'sold' and old.status = 'active')
    ) then
      raise exception 'invalid_status_change' using errcode = '22023';
    end if;
  end if;

  -- Published by the owner: visible at once, the old rejection note goes.
  if new.status = 'active' and old.status is distinct from 'active' then
    new.published_at := coalesce(old.published_at, now());
    new.admin_note := null;
  end if;

  if new.status = 'sold' and old.status is distinct from 'sold' then new.sold_at := now(); end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Waiting ads that no admin has looked at: publish them once.
update public.market_listings
   set status = 'active', published_at = coalesce(published_at, now()), updated_at = now()
 where status = 'pending' and admin_note is null;

notify pgrst, 'reload schema';

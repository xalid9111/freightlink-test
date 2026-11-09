-- =====================================================================
-- 0109 — Yüklər page by page from the server (owner, 09.11.2026,
-- "Turbo.az kimi"; approved by the owner the same day).
--
-- The app no longer has to download every open load (up to 1000) to put
-- the Loads page in order. Three read-only functions give it the parts:
--   * cargo_feed_promoted() — the loads with a running VIP or Premium
--     (few; the chessboard needs all of them, as before),
--   * cargo_feed_page(...)  — the other loads, a page at a time, in the
--     order the app always used: latest lift first (cargo_lifted_at, 0067:
--     posted, İrəli çək, VIP / Premium daily lift), then newest;
--     the next page starts after the last load of the previous one,
--   * cargo_feed_count()    — how many loads are listed (the counter).
-- "Listed" = the app's own rule: status new, not hidden, not switched off,
-- loading day not over (by Baku date).
--
-- Safe: the functions only READ and run with the caller's rights
-- (security invoker), so the existing rules (RLS, 0012 / 0107) still
-- decide which loads a user or a visitor may see. Nothing is changed or
-- deleted; forward-only and re-runnable. The pure helpers of 0067 may now
-- also be called by visitors (they only compute a time / a yes-no).
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.cargo_lifted_at(public.cargo)') is null
     or to_regprocedure('public.cargo_vip_active(boolean, timestamp with time zone)') is null
     or to_regprocedure('public.cargo_premium_active(timestamp with time zone)') is null then
    raise exception '0109: run 0067 (cargo promotions) first — nothing changed';
  end if;
end $$;

-- The app's "shown to others" rule (CargoModel.isListedOn).
create or replace function public.cargo_feed_listed(c public.cargo)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select c.status = 'new'
     and not coalesce(c.is_hidden, false)
     and not coalesce(c.is_paused, false)
     and c.pickup_date >= (now() at time zone 'Asia/Baku')::date;
$$;

-- Loads with a running VIP or Premium (newest first, as the app gets them).
create or replace function public.cargo_feed_promoted()
returns setof public.cargo language sql stable security invoker set search_path = public, pg_temp as $$
  select c.* from public.cargo c
   where public.cargo_feed_listed(c)
     and (public.cargo_vip_active(c.is_featured, c.featured_until) or public.cargo_premium_active(c.premium_until))
   order by c.created_at desc, c.id desc
   limit 1000;
$$;

-- One page of the other loads: latest lift first, then newest, then id.
-- The next page starts after [p_after_id] (the last load of the previous
-- page; its lift time is worked out here, so the app's clock does not
-- matter). Should that load be gone meanwhile, the app's own values
-- [p_after_lifted] / [p_after_created] are used.
create or replace function public.cargo_feed_page(
  p_limit integer default 20,
  p_after_id uuid default null,
  p_after_lifted timestamptz default null,
  p_after_created timestamptz default null)
returns setof public.cargo language sql stable security invoker set search_path = public, pg_temp as $$
  with anchor as (
    select coalesce((select public.cargo_lifted_at(a) from public.cargo a where a.id = p_after_id), p_after_lifted) as lifted,
           coalesce((select a.created_at from public.cargo a where a.id = p_after_id), p_after_created) as created
  )
  select (x.c).* from (
    select c, public.cargo_lifted_at(c) as lifted
      from public.cargo c
     where public.cargo_feed_listed(c)
       and not public.cargo_vip_active(c.is_featured, c.featured_until)
       and not public.cargo_premium_active(c.premium_until)
  ) x, anchor
  where p_after_id is null
     or (x.lifted, (x.c).created_at, (x.c).id) < (anchor.lifted, anchor.created, p_after_id)
  order by x.lifted desc, (x.c).created_at desc, (x.c).id desc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
$$;

-- How many loads are listed (the Loads page counter).
create or replace function public.cargo_feed_count()
returns integer language sql stable security invoker set search_path = public, pg_temp as $$
  select count(*)::integer from public.cargo c where public.cargo_feed_listed(c);
$$;

revoke all on function public.cargo_feed_listed(public.cargo) from public;
revoke all on function public.cargo_feed_promoted() from public;
revoke all on function public.cargo_feed_page(integer, uuid, timestamptz, timestamptz) from public;
revoke all on function public.cargo_feed_count() from public;
grant execute on function public.cargo_feed_listed(public.cargo) to anon, authenticated;
grant execute on function public.cargo_feed_promoted() to anon, authenticated;
grant execute on function public.cargo_feed_page(integer, uuid, timestamptz, timestamptz) to anon, authenticated;
grant execute on function public.cargo_feed_count() to anon, authenticated;
-- The 0067 helpers the page calls (pure computations, no data of their own).
grant execute on function public.cargo_lifted_at(public.cargo) to anon;
grant execute on function public.cargo_vip_active(boolean, timestamptz) to anon, authenticated;
grant execute on function public.cargo_premium_active(timestamptz) to anon, authenticated;

notify pgrst, 'reload schema';

commit;

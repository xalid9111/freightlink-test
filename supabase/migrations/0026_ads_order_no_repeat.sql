-- =====================================================================
-- 0026 — ADS: no repeats, admin order (priority), rotation
--
-- * One ad = one place in the loads list. Ad slot 1 → ad 1, slot 2 → ad 2…
--   When there are more slots than live ads, the extra slots stay empty
--   (no ad), unless the admin turns "repeat" on.
-- * ads.priority: the admin decides which ad comes first (smaller = first).
-- * Rotation (rotate_minutes from 0025): every X minutes the order moves by
--   one — the last ad comes to the front, the others move down one place.
--
-- Safe: forward-only, re-runnable. Adds one column with a default; no row
-- is deleted. Existing ads keep their order (by creation time).
-- =====================================================================

alter table public.ads add column if not exists priority integer not null default 100;

-- Layout now also carries "repeat" (default false = never the same ad twice).
create or replace function public.ads_feed_layout()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'first_after',    coalesce((select (value->>'first_after')::int     from platform_settings where key = 'ads_feed_layout'), 6),
    'every',          coalesce((select (value->>'every')::int           from platform_settings where key = 'ads_feed_layout'), 6),
    'rotate_minutes', coalesce((select (value->>'rotate_minutes')::int  from platform_settings where key = 'ads_feed_layout'), 0),
    'repeat',         coalesce((select (value->>'repeat')::boolean      from platform_settings where key = 'ads_feed_layout'), false));
$$;

create or replace function public.admin_set_ads_feed_layout(
  p_first_after integer, p_every integer, p_rotate_minutes integer, p_repeat boolean
)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb := public.ads_feed_layout(); v_new jsonb;
begin
  perform public._require_admin();
  if p_first_after is null or p_first_after not between 1 and 50 then raise exception 'invalid_first_after' using errcode = '22023'; end if;
  if p_every is null or p_every not between 2 and 50 then raise exception 'invalid_every' using errcode = '22023'; end if;
  if p_rotate_minutes is null or p_rotate_minutes not between 0 and 1440 then raise exception 'invalid_rotate_minutes' using errcode = '22023'; end if;
  v_new := jsonb_build_object('first_after', p_first_after, 'every', p_every, 'rotate_minutes', p_rotate_minutes,
                              'repeat', coalesce(p_repeat, false));
  insert into platform_settings (key, value) values ('ads_feed_layout', v_new)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  perform public._admin_log('ads_feed_layout.update', 'setting', 'ads_feed_layout', v_old, v_new);
  return v_new;
end;
$$;

-- The 3-argument version (0025) keeps working and keeps the current "repeat".
create or replace function public.admin_set_ads_feed_layout(p_first_after integer, p_every integer, p_rotate_minutes integer)
returns jsonb language sql security definer set search_path = public, pg_temp as $$
  select public.admin_set_ads_feed_layout(p_first_after, p_every, p_rotate_minutes,
                                          coalesce((public.ads_feed_layout()->>'repeat')::boolean, false));
$$;

-- Admin: the order of the ads. p_ids = ads in the wanted order (first =
-- shown first). Ads not in the list keep their priority.
create or replace function public.admin_set_ads_order(p_ids uuid[])
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  if p_ids is null or cardinality(p_ids) = 0 then raise exception 'empty_order' using errcode = '22023'; end if;
  if cardinality(p_ids) > 500 or (select count(distinct x) from unnest(p_ids) x) <> cardinality(p_ids) then
    raise exception 'invalid_order' using errcode = '22023';
  end if;
  select coalesce(jsonb_object_agg(id, priority), '{}'::jsonb) into v_old from ads where id = any(p_ids);
  update ads a set priority = o.n * 10, updated_at = now()
    from unnest(p_ids) with ordinality as o(id, n)
   where a.id = o.id;
  perform public._admin_log('ads.reorder', 'ad', null, v_old,
    (select coalesce(jsonb_object_agg(id, priority), '{}'::jsonb) from ads where id = any(p_ids)));
end;
$$;

-- Feed: same rules as 0023, now in the admin's order.
create or replace function public.home_feed_ads()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select case when not public.home_ads_enabled() or auth.uid() is null then '[]'::jsonb else
    coalesce((
      select jsonb_agg(to_jsonb(a) order by a.priority, a.created_at)
      from ads a
      join ad_orders o on o.id = a.order_id
      where a.is_active and now() >= a.starts_at and now() < a.ends_at
        and o.payment_status = 'paid'
        and a.creative->>'version' = '2'
        and not public.is_blocked(a.advertiser_id)
    ), '[]'::jsonb)
  end;
$$;

revoke all on function public.ads_feed_layout() from public, anon;
revoke all on function public.admin_set_ads_feed_layout(integer, integer, integer, boolean) from public, anon;
revoke all on function public.admin_set_ads_feed_layout(integer, integer, integer) from public, anon;
revoke all on function public.admin_set_ads_order(uuid[]) from public, anon;
revoke all on function public.home_feed_ads() from public, anon;
grant execute on function public.ads_feed_layout() to authenticated;
grant execute on function public.admin_set_ads_feed_layout(integer, integer, integer, boolean) to authenticated;
grant execute on function public.admin_set_ads_feed_layout(integer, integer, integer) to authenticated;
grant execute on function public.admin_set_ads_order(uuid[]) to authenticated;
grant execute on function public.home_feed_ads() to authenticated;

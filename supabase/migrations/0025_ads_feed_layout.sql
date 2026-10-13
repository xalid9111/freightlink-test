-- =====================================================================
-- 0025 — ADS: where ads appear in the loads list, and how long each stays
--
-- Admin → Reklamlar → "Reklamın yeri və müddəti":
--   first_after    : the first ad comes after this many loads (1–50)
--   every          : then one ad after every N loads (2–50)
--   rotate_minutes : with several live ads, each ad slot shows one ad for
--                    this many minutes, then the next one (0 = no change,
--                    every slot keeps its own ad; 1–1440)
-- Defaults = the behaviour so far: 6 / 6 / 0.
--
-- Safe: forward-only, re-runnable; only adds one settings row when the
-- admin saves. No data is changed or deleted.
-- =====================================================================

create or replace function public.ads_feed_layout()
returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'first_after',    coalesce((select (value->>'first_after')::int    from platform_settings where key = 'ads_feed_layout'), 6),
    'every',          coalesce((select (value->>'every')::int          from platform_settings where key = 'ads_feed_layout'), 6),
    'rotate_minutes', coalesce((select (value->>'rotate_minutes')::int from platform_settings where key = 'ads_feed_layout'), 0));
$$;

create or replace function public.admin_set_ads_feed_layout(p_first_after integer, p_every integer, p_rotate_minutes integer)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb := public.ads_feed_layout(); v_new jsonb;
begin
  perform public._require_admin();
  if p_first_after is null or p_first_after not between 1 and 50 then raise exception 'invalid_first_after' using errcode = '22023'; end if;
  if p_every is null or p_every not between 2 and 50 then raise exception 'invalid_every' using errcode = '22023'; end if;
  if p_rotate_minutes is null or p_rotate_minutes not between 0 and 1440 then raise exception 'invalid_rotate_minutes' using errcode = '22023'; end if;
  v_new := jsonb_build_object('first_after', p_first_after, 'every', p_every, 'rotate_minutes', p_rotate_minutes);
  insert into platform_settings (key, value) values ('ads_feed_layout', v_new)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  perform public._admin_log('ads_feed_layout.update', 'setting', 'ads_feed_layout', v_old, v_new);
  return v_new;
end;
$$;

revoke all on function public.ads_feed_layout() from public, anon;
revoke all on function public.admin_set_ads_feed_layout(integer, integer, integer) from public, anon;
grant execute on function public.ads_feed_layout() to authenticated;
grant execute on function public.admin_set_ads_feed_layout(integer, integer, integer) to authenticated;

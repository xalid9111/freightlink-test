-- =====================================================================
-- 0057 — AutoFix: old hidden problems are moved to "solved" too
-- (owner, 22.10.2026)
--
-- 0042 only marked OPEN problems as solved when nobody had hit them for
-- p_days days; HIDDEN ("gizlədilib") ones stayed in the list for ever.
-- Now admin_autofix_auto_resolve(p_days) treats both the same: an open or
-- hidden problem not seen for p_days days becomes "fixed" (resolved_by =
-- null → "avtomatik"). Then "Həll olunanları sil" can clean it up. If it
-- happens again, 0034 opens it again on its own.
--
-- Safe: forward-only, re-runnable. Replaces one admin-only function (same
-- signature, same rights); no table or policy changes; deletes nothing.
-- =====================================================================

create or replace function public.admin_autofix_auto_resolve(p_days integer default 3)
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n integer;
begin
  perform public._require_admin();
  with done as (
    update app_errors
       set status = 'fixed', resolved_at = now(), resolved_by = null
     where status in ('open', 'ignored') -- 0057: hidden ones too
       and last_seen_at < now() - make_interval(days => least(greatest(coalesce(p_days, 3), 1), 365))
    returning id
  ), logged as (
    insert into autofix_actions (error_id, action, ok, note, executed_by)
    select id, 'status:fixed', true, 'auto_not_seen', auth.uid() from done
    returning 1
  )
  select count(*) into v_n from logged;
  return v_n;
end;
$$;

revoke all on function public.admin_autofix_auto_resolve(integer) from public, anon;
grant execute on function public.admin_autofix_auto_resolve(integer) to authenticated;

notify pgrst, 'reload schema';

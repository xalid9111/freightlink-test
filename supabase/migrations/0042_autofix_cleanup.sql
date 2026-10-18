-- =====================================================================
-- 0042 — AutoFix: solved problems are found automatically and can be
-- deleted in one go (owner, 18.10.2026)
--
-- * admin_autofix_auto_resolve(p_days): an OPEN problem that nobody has
--   hit for p_days days (default 3) is marked "fixed" by the system
--   (resolved_by = null → "avtomatik"). If it happens again, 0034 already
--   reopens it on its own. Called when the admin opens Admin → AutoFix.
-- * admin_autofix_delete_fixed(): deletes ONLY problems with status
--   'fixed'. Open and hidden (ignored) problems are never touched.
--   Only the AutoFix error list is cleaned — no user data.
--
-- Safe: forward-only, re-runnable. Adds two admin-only functions; no
-- table, policy or existing function changes; this file deletes nothing.
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
     where status = 'open'
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

create or replace function public.admin_autofix_delete_fixed()
returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n integer;
begin
  perform public._require_admin();
  with gone as (
    delete from app_errors where status = 'fixed' returning id
  )
  select count(*) into v_n from gone;
  perform public._admin_log('autofix.delete_fixed', 'app_error', null, null, jsonb_build_object('deleted', v_n));
  return v_n;
end;
$$;

revoke all on function public.admin_autofix_auto_resolve(integer) from public, anon;
revoke all on function public.admin_autofix_delete_fixed() from public, anon;
grant execute on function public.admin_autofix_auto_resolve(integer) to authenticated;
grant execute on function public.admin_autofix_delete_fixed() to authenticated;

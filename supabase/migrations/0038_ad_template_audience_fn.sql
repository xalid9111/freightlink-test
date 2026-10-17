-- =====================================================================
-- 0038 — Restore admin_set_ad_template_audience (ad template "Kim üçündür")
--
-- On the live database 0029 had only partly applied: create_service_ad_order
-- exists (0032 re-created it) but admin_set_ad_template_audience does not,
-- so saving a template as "Servis" / "Hər ikisi" failed with "function not
-- found". Re-running the whole 0029 would put back older versions of
-- functions that later migrations replaced, so this file creates ONLY the
-- missing function (same body as in 0029) and nothing else.
--
-- Safe: forward-only, re-runnable. No table, row or other function changes.
-- =====================================================================

-- The column it writes (added by 0029; 0032 relies on it too).
alter table public.ad_templates add column if not exists audience text not null default 'cargo';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'ad_templates_audience_check') then
    alter table public.ad_templates add constraint ad_templates_audience_check check (audience in ('cargo','service','all'));
  end if;
end $$;

-- Admin: who a template is for.
create or replace function public.admin_set_ad_template_audience(p_id uuid, p_audience text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old text;
begin
  perform public._require_admin();
  if coalesce(p_audience, '') not in ('cargo','service','all') then raise exception 'invalid_audience' using errcode = '22023'; end if;
  select audience into v_old from ad_templates where id = p_id;
  if not found then raise exception 'not_found'; end if;
  update ad_templates set audience = p_audience, updated_at = now() where id = p_id;
  perform public._admin_log('ad_template.audience', 'ad_template', p_id::text,
    jsonb_build_object('audience', v_old), jsonb_build_object('audience', p_audience));
end;
$$;

revoke all on function public.admin_set_ad_template_audience(uuid, text) from public, anon;
grant execute on function public.admin_set_ad_template_audience(uuid, text) to authenticated;

-- Let the API see the function right away.
notify pgrst, 'reload schema';

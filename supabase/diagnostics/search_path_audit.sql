-- =====================================================================
-- READ-ONLY diagnostics — safe to run in the Supabase SQL Editor.
-- Changes nothing. Run before and after 0018 / 0019.
-- =====================================================================

-- 1) Every SECURITY DEFINER function in schema public and the status of
--    its search_path, using the same rule as the 0018 / 0019 self-check.
select p.oid::regprocedure                                   as function,
       pg_get_userbyid(p.proowner)                           as owner,
       pg_has_role(current_user, p.proowner, 'USAGE')        as migration_role_can_alter,
       exists (select 1 from pg_depend d
               where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
                                                             as extension_owned,
       coalesce(sp.v, '<none>')                              as search_path,
       case
         when exists (select 1 from pg_depend d
                      where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
                                                    then 'skipped (extension)'
         when sp.v is null                          then 'UNSAFE: no search_path'
         when btrim(sp.v) in ('', '""')             then 'ok (empty)'
         when sp.v ~* '(^|,)\s*"?pg_temp"?\s*$'     then 'ok (pg_temp last)'
         else                                            'UNSAFE: pg_temp not last (implicitly searched first)'
       end                                                   as status
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
left join lateral (select substr(c, 13) as v from unnest(coalesce(p.proconfig, '{}')) c
                   where c like 'search_path=%' limit 1) sp on true
where n.nspname = 'public' and p.prosecdef
order by status desc, 1;

-- 2) Which Package migrations are present (markers).
select to_regprocedure('public.service_provider_notes(uuid[])') is not null as migration_0018_applied,
       to_regclass('public.user_profiles') is not null                     as migration_0019_applied,
       exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'users'
               and policyname = 'users_select_all')                       as old_open_users_policy_present;

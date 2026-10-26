-- =====================================================================
-- 0070 — İş Mərkəzi: "Vakansiya yerləşdir" in 4 steps (owner, 26.10.2026)
--
-- * job_vacancies.job_type: 'tir' (TIR sürücüsü) | 'other' (Digər
--   sürücü / işçi) | null (older vacancies — nothing is rewritten).
-- * Work schedule "Layihə əsasında" ('project') on vacancies and work
--   profiles (the old values stay valid).
-- * Three more catalogue entries: ADR sertifikatı (document), Yük
--   qısa/uzun marşrut and Gecə sürüşü (skills).
-- * job_vacancies_list() also returns job_type (same rules, same safe
--   columns as 0069).
--
-- Safe: forward-only, re-runnable. One new nullable column, two check
-- constraints widened, three catalogue rows added. No row is changed or
-- deleted.
-- =====================================================================

begin;

-- 1) İş növü -------------------------------------------------------------------
alter table public.job_vacancies add column if not exists job_type text;
alter table public.job_vacancies drop constraint if exists job_vacancies_job_type_check;
alter table public.job_vacancies add constraint job_vacancies_job_type_check
  check (job_type is null or job_type in ('tir', 'other'));

-- 2) İş qrafiki: + 'project' ----------------------------------------------------
alter table public.job_vacancies drop constraint if exists job_vacancies_schedule_check;
alter table public.job_vacancies add constraint job_vacancies_schedule_check
  check (schedule is null or schedule in ('full_time', 'part_time', 'rotation', 'flexible', 'project'));
alter table public.job_seeker_profiles drop constraint if exists job_seeker_profiles_schedule_check;
alter table public.job_seeker_profiles add constraint job_seeker_profiles_schedule_check
  check (schedule is null or schedule in ('full_time', 'part_time', 'rotation', 'flexible', 'project'));

-- 3) Catalogue ------------------------------------------------------------------
insert into public.job_skills (code, kind, name, sort_order) values
  ('adr', 'document', 'ADR sertifikatı', 130),
  ('route_mix', 'skill', 'Yük qısa/uzun marşrut', 250),
  ('night', 'skill', 'Gecə sürüşü', 260)
on conflict (code) do nothing;

-- 4) The safe list also carries job_type -------------------------------------------
create or replace function public.job_vacancies_list(p_limit integer default 300, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_admin boolean := public.is_admin();
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  return coalesce((
    select jsonb_agg(r order by r ->> 'updated_at' desc)
      from (
        select jsonb_build_object(
                 'id', v.id, 'owner_id', v.owner_id, 'owner_name', u.full_name, 'avatar_url', u.avatar_url,
                 'company_name', v.company_name, 'country', v.country, 'city', v.city,
                 'job_type', v.job_type,
                 'specialties', v.specialties, 'requirements', v.requirements, 'can_help', v.can_help,
                 'min_experience', v.min_experience, 'countries', v.countries, 'routes', v.routes,
                 'salary_min', v.salary_min, 'salary_max', v.salary_max, 'currency', v.currency,
                 'schedule', v.schedule, 'conditions', v.conditions,
                 'phone', case when v.show_phone or v_admin or v.owner_id = auth.uid() then v.phone end,
                 'whatsapp', v.whatsapp and (v.show_phone or v_admin or v.owner_id = auth.uid()),
                 'status', v.status, 'is_hidden', v.is_hidden and v_admin,
                 'updated_at', v.updated_at) r
          from public.job_vacancies v
          join public.users u on u.id = v.owner_id
         where v.status = 'active'
           and (not v.is_hidden or v_admin)
           and (not coalesce(u.is_blocked, false) or v_admin)
         order by v.updated_at desc
         limit least(greatest(coalesce(p_limit, 300), 1), 500) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.job_vacancies_list(integer, integer) from public, anon;
grant execute on function public.job_vacancies_list(integer, integer) to authenticated;

-- 5) Final check ------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'job_vacancies' and column_name = 'job_type')
     or (select count(*) from public.job_skills where code in ('adr', 'route_mix', 'night')) <> 3 then
    raise exception '0070: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

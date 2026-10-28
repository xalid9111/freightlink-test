-- =====================================================================
-- 0072 — İş Mərkəzi forms as in the owner's pictures 2 and 3
-- (owner, 28.10.2026)
--
-- * Transport: + Açıq ('open'). QRUPAJ is a way of carrying, not a
--   vehicle — not added.
-- * Licence categories: + D1, C1E, D1E, DE (B, C1, C, CE, D stay).
-- * Documents: + Beynəlxalq sürücülük vəsiqəsi ('idp').
-- * İş rejimi: + Daimi, Müvəqqəti, Uzun marşrut, Regional (the older
--   values stay valid, stored rows are not rewritten).
-- * Vacancy: age range (age_min / age_max); both sides: salary
--   "Danışılacaq" (salary_negotiable).
-- * The safe lists also return the new fields (same rules as 0069 /
--   0070: signed in only, the phone only when its owner shows it).
--
-- Safe: forward-only, re-runnable. New nullable / defaulted columns,
-- check constraints widened, catalogue rows added. No row is changed or
-- deleted.
-- =====================================================================

begin;

-- 1) Catalogue -------------------------------------------------------------------
insert into public.job_specialties (code, name, sort_order) values ('open', 'Açıq', 65)
on conflict (code) do nothing;
insert into public.job_skills (code, kind, name, sort_order) values
  ('lic_d1', 'license', 'D1', 45), ('lic_c1e', 'license', 'C1E', 60),
  ('lic_d1e', 'license', 'D1E', 70), ('lic_de', 'license', 'DE', 80),
  ('idp', 'document', 'Beynəlxalq sürücülük vəsiqəsi', 140)
on conflict (code) do nothing;

-- 2) İş rejimi ---------------------------------------------------------------------
alter table public.job_vacancies drop constraint if exists job_vacancies_schedule_check;
alter table public.job_vacancies add constraint job_vacancies_schedule_check
  check (schedule is null or schedule in ('full_time', 'part_time', 'rotation', 'flexible', 'project',
                                          'permanent', 'temporary', 'long_haul', 'regional'));
alter table public.job_seeker_profiles drop constraint if exists job_seeker_profiles_schedule_check;
alter table public.job_seeker_profiles add constraint job_seeker_profiles_schedule_check
  check (schedule is null or schedule in ('full_time', 'part_time', 'rotation', 'flexible', 'project',
                                          'permanent', 'temporary', 'long_haul', 'regional'));

-- 3) Age range, "Danışılacaq" -------------------------------------------------------
alter table public.job_vacancies add column if not exists age_min integer;
alter table public.job_vacancies add column if not exists age_max integer;
alter table public.job_vacancies add column if not exists salary_negotiable boolean not null default false;
alter table public.job_seeker_profiles add column if not exists salary_negotiable boolean not null default false;
alter table public.job_vacancies drop constraint if exists job_vacancies_age_check;
alter table public.job_vacancies add constraint job_vacancies_age_check
  check ((age_min is null or age_min between 16 and 80) and (age_max is null or age_max between 16 and 80)
         and (age_min is null or age_max is null or age_max >= age_min));

-- 4) The safe lists carry the new fields --------------------------------------------
create or replace function public.job_seekers_list(p_limit integer default 300, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_admin boolean := public.is_admin();
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  return coalesce((
    select jsonb_agg(r order by r ->> 'updated_at' desc)
      from (
        select jsonb_build_object(
                 'user_id', p.user_id, 'full_name', p.full_name, 'avatar_url', u.avatar_url,
                 'age', case when p.birth_date is not null then date_part('year', age(current_date, p.birth_date))::int end,
                 'country', p.country, 'city', p.city, 'experience_years', p.experience_years,
                 'specialties', p.specialties, 'skills', p.skills, 'other_docs', p.other_docs,
                 'countries', p.countries, 'routes', p.routes, 'salary_min', p.salary_min, 'currency', p.currency,
                 'schedule', p.schedule, 'note', p.note, 'salary_negotiable', p.salary_negotiable,
                 'phone', case when p.show_phone or v_admin or p.user_id = auth.uid() then p.phone end,
                 'whatsapp', p.whatsapp and (p.show_phone or v_admin or p.user_id = auth.uid()),
                 'is_hidden', p.is_hidden and v_admin,
                 'updated_at', p.updated_at) r
          from public.job_seeker_profiles p
          join public.users u on u.id = p.user_id
         where p.is_active
           and (not p.is_hidden or v_admin)
           and (not coalesce(u.is_blocked, false) or v_admin)
         order by p.updated_at desc
         limit least(greatest(coalesce(p_limit, 300), 1), 500) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.job_seekers_list(integer, integer) from public, anon;
grant execute on function public.job_seekers_list(integer, integer) to authenticated;

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
                 'age_min', v.age_min, 'age_max', v.age_max, 'salary_negotiable', v.salary_negotiable,
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

-- 5) Final check ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'job_vacancies' and column_name = 'age_min')
     or not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'job_seeker_profiles' and column_name = 'salary_negotiable')
     or (select count(*) from public.job_skills where code in ('lic_d1', 'lic_c1e', 'lic_d1e', 'lic_de', 'idp')) <> 5
     or not exists (select 1 from public.job_specialties where code = 'open') then
    raise exception '0072: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;

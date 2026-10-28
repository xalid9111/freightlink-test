-- =====================================================================
-- 0073 — İş Mərkəzi: several İş rejimi at once (owner, 28.10.2026)
--
-- "Çalışma düzeni / İş rejimi" can be 2 or 3 choices in both forms
-- (e.g. Daimi + Uzun marşrut). New column schedules text[] on vacancies
-- and work profiles; the old single "schedule" stays and keeps the first
-- choice, so older app versions still read it. Rows saved before keep
-- their single value (the app reads it as a one-item list) — nothing is
-- rewritten.
--
-- Safe: forward-only, re-runnable. Two new defaulted columns with checks;
-- the safe lists also return them (same phone rules as before). No row is
-- changed or deleted.
-- =====================================================================

begin;

alter table public.job_vacancies add column if not exists schedules text[] not null default '{}';
alter table public.job_seeker_profiles add column if not exists schedules text[] not null default '{}';
alter table public.job_vacancies drop constraint if exists job_vacancies_schedules_check;
alter table public.job_vacancies add constraint job_vacancies_schedules_check
  check (cardinality(schedules) <= 9 and schedules <@ array['full_time', 'part_time', 'rotation', 'flexible', 'project',
                                     'permanent', 'temporary', 'long_haul', 'regional']::text[]);
alter table public.job_seeker_profiles drop constraint if exists job_seeker_profiles_schedules_check;
alter table public.job_seeker_profiles add constraint job_seeker_profiles_schedules_check
  check (cardinality(schedules) <= 9 and schedules <@ array['full_time', 'part_time', 'rotation', 'flexible', 'project',
                                     'permanent', 'temporary', 'long_haul', 'regional']::text[]);

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
                 'schedule', p.schedule, 'note', p.note, 'salary_negotiable', p.salary_negotiable, 'schedules', p.schedules,
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
                 'age_min', v.age_min, 'age_max', v.age_max, 'salary_negotiable', v.salary_negotiable, 'schedules', v.schedules,
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

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'job_vacancies' and column_name = 'schedules')
     or not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'job_seeker_profiles' and column_name = 'schedules') then
    raise exception '0073: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
